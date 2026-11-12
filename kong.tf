# When enabled, provision the cluster first; the runner needs Kubernetes API
# connectivity and authorization before the namespace, Secret, and Helm stage.
provider "kubernetes" {
  host                   = module.ai_gateway_eks_auto.cluster_endpoint
  cluster_ca_certificate = base64decode(module.ai_gateway_eks_auto.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--region", var.aws_region, "--cluster-name", module.ai_gateway_eks_auto.cluster_name]
  }
}

provider "helm" {
  kubernetes = {
    host                   = module.ai_gateway_eks_auto.cluster_endpoint
    cluster_ca_certificate = base64decode(module.ai_gateway_eks_auto.cluster_certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--region", var.aws_region, "--cluster-name", module.ai_gateway_eks_auto.cluster_name]
    }
  }
}

resource "kubernetes_namespace_v1" "ai_gateway_data_plane" {
  count = var.enable_kong_ai_gateway ? 1 : 0

  metadata {
    name = var.ai_gateway_data_plane_namespace
  }
}

# The private key and certificate will be stored in Terraform state and plans.
resource "kubernetes_secret_v1" "ai_gateway_data_plane_tls" {
  count = var.enable_kong_ai_gateway ? 1 : 0

  metadata {
    name      = var.kong_data_plane_tls_secret_name
    namespace = kubernetes_namespace_v1.ai_gateway_data_plane[0].metadata[0].name
  }

  type = "kubernetes.io/tls"
  data = {
    "tls.crt" = try(file(var.kong_data_plane_public_certificate_path), "")
    "tls.key" = try(file(var.kong_data_plane_private_key_path), "")
  }

  lifecycle {
    precondition {
      condition     = can(regex("-----BEGIN CERTIFICATE-----", file(var.kong_data_plane_public_certificate_path))) && !can(regex("-----BEGIN ([A-Z ]* )?PRIVATE KEY-----", file(var.kong_data_plane_public_certificate_path))) && can(regex("-----BEGIN ([A-Z ]* )?PRIVATE KEY-----", file(var.kong_data_plane_private_key_path)))
      error_message = "Provide readable PEM certificate and private key files; the certificate file must not contain a private key."
    }
  }
}

resource "helm_release" "ai_gateway_data_plane" {
  count = var.enable_kong_ai_gateway ? 1 : 0

  name             = var.kong_helm_release_name
  namespace        = var.ai_gateway_data_plane_namespace
  create_namespace = false
  repository       = var.kong_helm_repository
  chart            = var.kong_helm_chart
  version          = var.kong_helm_chart_version
  wait             = true
  timeout          = var.kong_helm_timeout_seconds

  values = [yamlencode({
    ingressController = { enabled = false }
    image = {
      repository = var.kong_data_plane_image_repository
      tag        = var.kong_data_plane_image_tag
    }
    replicaCount  = var.kong_data_plane_replicas
    secretVolumes = [var.kong_data_plane_tls_secret_name]
    env = {
      role                          = "data_plane"
      database                      = "off"
      konnect_mode                  = "on"
      vitals                        = "off"
      cluster_mtls                  = "pki"
      cluster_control_plane         = "${var.konnect_control_plane_host}:443"
      cluster_server_name           = var.konnect_control_plane_host
      cluster_telemetry_endpoint    = "${var.konnect_telemetry_host}:443"
      cluster_telemetry_server_name = var.konnect_telemetry_host
      cluster_cert                  = "/etc/secrets/${var.kong_data_plane_tls_secret_name}/tls.crt"
      cluster_cert_key              = "/etc/secrets/${var.kong_data_plane_tls_secret_name}/tls.key"
      lua_ssl_trusted_certificate   = "system"
    }
    deployment = {
      serviceAccount = {
        create = var.kong_helm_create_service_account
        name   = var.ai_gateway_data_plane_service_account
      }
      kong = {
        initContainers = {
          clearStalePid = {
            image = {
              repository = var.kong_init_image_repository
              tag        = var.kong_init_image_tag
            }
          }
        }
      }
    }
    resources = {
      requests = {
        cpu    = var.kong_data_plane_cpu_request
        memory = var.kong_data_plane_memory_request
      }
    }
    proxy = {
      enabled           = true
      type              = var.kong_proxy_service_type
      loadBalancerClass = var.kong_proxy_service_type == "LoadBalancer" ? "eks.amazonaws.com/nlb" : ""
      http              = { enabled = var.kong_proxy_service_type != "LoadBalancer" }
      annotations = var.kong_proxy_service_type == "LoadBalancer" ? {
        "service.beta.kubernetes.io/aws-load-balancer-scheme"           = var.kong_proxy_nlb_scheme
        "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type"  = "ip"
        "service.beta.kubernetes.io/aws-load-balancer-ssl-cert"         = var.kong_proxy_acm_certificate_arn
        "service.beta.kubernetes.io/aws-load-balancer-ssl-ports"        = "443"
        "service.beta.kubernetes.io/aws-load-balancer-backend-protocol" = "ssl"
      } : {}
    }
    admin   = { enabled = false }
    manager = { enabled = false }
  })]

  lifecycle {
    precondition {
      condition     = var.kong_proxy_service_type != "LoadBalancer" || can(regex("^arn:[^:]+:acm:[^:]+:[0-9]{12}:certificate/[^/]+$", var.kong_proxy_acm_certificate_arn))
      error_message = "A valid ACM certificate ARN is required for the LoadBalancer proxy."
    }
    precondition {
      condition     = can(regex("^[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$", var.konnect_control_plane_host)) && can(regex("^[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$", var.konnect_telemetry_host))
      error_message = "Provide the existing Konnect configuration and telemetry hostnames without scheme or port."
    }
  }

  depends_on = [
    kubernetes_secret_v1.ai_gateway_data_plane_tls,
    aws_eks_pod_identity_association.ai_gateway_data_plane,
  ]
}
