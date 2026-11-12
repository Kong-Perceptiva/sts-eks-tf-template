variable "enable_kong_ai_gateway" {
  description = "Install a hybrid data plane for an existing Konnect AI Gateway using Helm."
  type        = bool
  default     = false
}

variable "konnect_control_plane_host" {
  description = "Existing Konnect configuration endpoint hostname, without scheme or port."
  type        = string
  default     = ""
}

variable "konnect_telemetry_host" {
  description = "Existing Konnect telemetry endpoint hostname, without scheme or port."
  type        = string
  default     = ""
}

variable "kong_data_plane_public_certificate_path" {
  description = "Path to the public PEM certificate already registered in Konnect."
  type        = string
  default     = ""
}

variable "kong_data_plane_private_key_path" {
  description = "Path to the matching PEM private key; its contents are stored in Terraform state and plans."
  type        = string
  default     = ""
}

variable "kong_data_plane_tls_secret_name" {
  description = "Name of the Terraform-managed Kubernetes TLS Secret."
  type        = string
  default     = "kong-cluster-cert"
}

variable "kong_helm_release_name" {
  description = "Helm release name for the data plane."
  type        = string
  default     = "kong-ai-gateway"
}

variable "kong_helm_repository" {
  description = "Repository containing the Kong Helm chart."
  type        = string
  default     = "https://charts.konghq.com"
}

variable "kong_helm_chart" {
  description = "Helm chart used to deploy the AI Gateway data plane."
  type        = string
  default     = "kong"
}

variable "kong_helm_chart_version" {
  description = "Pinned Helm chart version; confirm compatibility with the runtime."
  type        = string
  default     = "3.4.1"
}

variable "kong_helm_timeout_seconds" {
  description = "Timeout for the data plane Helm release."
  type        = number
  default     = 600
}

variable "kong_helm_create_service_account" {
  description = "Whether Helm creates the data plane ServiceAccount; set false to reuse one created elsewhere."
  type        = bool
  default     = true
}

variable "kong_data_plane_image_repository" {
  description = "AI Gateway runtime image repository accessible from the cluster."
  type        = string
  default     = "kong/kong-ai-gateway"
}

variable "kong_data_plane_image_tag" {
  description = "AI Gateway runtime image tag."
  type        = string
  default     = "2.3.0-distroless"
}

variable "kong_init_image_repository" {
  description = "Image repository for the chart's shell-based clear-stale-pid init container."
  type        = string
  default     = "busybox"
}

variable "kong_init_image_tag" {
  description = "Image tag for the clear-stale-pid init container."
  type        = string
  default     = "1.36"
}

variable "kong_data_plane_replicas" {
  description = "Number of data plane replicas; choose based on workload and availability requirements."
  type        = number
  default     = 1
  validation {
    condition     = var.kong_data_plane_replicas >= 1 && floor(var.kong_data_plane_replicas) == var.kong_data_plane_replicas
    error_message = "Specify a positive integer for data plane replicas."
  }
}

variable "kong_data_plane_cpu_request" {
  description = "Kubernetes CPU request for each data plane pod."
  type        = string
  default     = "1"
}

variable "kong_data_plane_memory_request" {
  description = "Kubernetes memory request for each data plane pod."
  type        = string
  default     = "2Gi"
}

variable "kong_proxy_service_type" {
  description = "Proxy Service type; ClusterIP avoids creating a load balancer by default."
  type        = string
  default     = "ClusterIP"
  validation {
    condition     = contains(["ClusterIP", "NodePort", "LoadBalancer"], var.kong_proxy_service_type)
    error_message = "Use ClusterIP, NodePort, or LoadBalancer."
  }
}

variable "kong_proxy_acm_certificate_arn" {
  description = "ACM certificate ARN for the optional public NLB TLS listener; required with LoadBalancer."
  type        = string
  default     = ""
}
