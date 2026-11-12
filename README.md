# EKS Auto Mode and AI Gateway data plane template

**Kong Professional Services | Customer implementation template**

This template provisions an AWS infrastructure foundation for a workload running on EKS Auto Mode. Optionally, it creates an IAM role and an EKS Pod Identity association that allow an approved Kubernetes ServiceAccount to invoke explicitly approved Amazon Bedrock models and read selected AWS Secrets Manager secrets. A separate disabled-by-default option installs a hybrid data plane for an existing Konnect AI Gateway.

This is a starting point for STS infrastructure review, not a deployed or production-certified configuration. STS owns the AWS account, networking, Terraform execution, and operational controls. Values such as CIDRs, cluster access, availability zones, model ARNs, and tags must be approved for each environment.

**Important:** The optional TLS Secret stores its private key in Terraform state and saved plans. Use an approved encrypted, access-controlled backend and protect plan files and backups. The sample `kongctl` OpenAI flow is illustrative; the engagement's intended provider is Amazon Bedrock, subject to STS decisions.

## Scope

Terraform manages:

- A VPC with public and private subnets in at least two availability zones, internet connectivity, and NAT gateways.
- An EKS Auto Mode cluster, AWS-managed node pools, and the cluster and node IAM roles managed by the EKS module.
- Explicit EKS access entries for approved administrator principals, or an explicitly enabled creator-admin entry.
- Optionally, one data plane IAM role, its Pod Identity trust policy, a Bedrock inference permission policy, and an EKS Pod Identity association.
- Optionally, Secrets Manager secret containers and a read-only IAM policy for those exact secrets and/or an explicitly approved name prefix. Terraform creates secret metadata only, not values or versions.
- Optionally, a Kubernetes namespace and TLS Secret, and a Helm data plane release connected to an existing Konnect AI Gateway.

Terraform **does not** create the Konnect control plane, register its certificate, generate TLS certificates, or configure gateway vaults, providers, models, Secrets Manager values, or PrivateLink endpoints. The optional Helm release can create the ServiceAccount. Gateway configuration is performed separately using `kongctl`. This template does not implement disaster recovery, Bedrock PrivateLink, Konnect PrivateLink, application authentication, or AI governance.

## Repository structure

Terraform combines all `.tf` files in this directory into **one configuration and one state**. The file boundaries organize the code; they do not change execution order or make resources independently deployable. Configure environment-specific inputs in a separate, untracked `.tfvars` file rather than editing the resource files.

| File | What it defines or configures |
| --- | --- |
| `versions.tf` | Terraform/provider version constraints, the AWS region, expected account guard, and default tags. |
| `variables.tf` | The input schema, descriptions, defaults, and validation for network, EKS, Bedrock, and Secrets Manager settings. |
| `network.tf` | The new VPC, public/private subnets, DNS settings, Internet Gateway, and NAT gateway topology. |
| `eks.tf` | The EKS Auto Mode cluster, node pools, API endpoint access, logging, deletion protection, cluster access entries, and cross-input checks. The EKS module manages the EKS cluster and node IAM roles. |
| `pod-identity.tf` | The data plane IAM role, its EKS Pod Identity trust policy, and the cluster/namespace/ServiceAccount association. |
| `bedrock.tf` | The data plane role's permissions to invoke approved Bedrock models and, when specified, read inference profiles. It does not provision models. |
| `secrets-manager.tf` | Optional secret containers and the data plane role's scoped read/KMS permissions. It does not create secret values. |
| `kong.tf`, `kong-variables.tf` | Optional namespace, TLS Secret, Helm data plane release, and associated inputs. |
| `kongctl/` | Separate, illustrative AI Gateway 2.x declarative configuration; see its README before use. |
| `outputs.tf` | Non-secret infrastructure identifiers exposed after deployment. |
| `terraform.tfvars.example` | Illustrative input values to copy and replace; not a deployable STS configuration. |
| `.terraform.lock.hcl` | Locked provider versions and checksums; review and commit updates deliberately. |
| `.gitignore` | Excludes local Terraform state, provider downloads, plan files, and `.tfvars` files. |

## Architecture

```text
VPC
  private subnets ── EKS Auto Mode nodes and data plane pods
                           │
                           ├─ ServiceAccount: <namespace>/<service-account>
                           │          │
                           │          └─ EKS Pod Identity association
                           │                       │
                           │                       └─ IAM role + Bedrock policy
                           │                           └─ optional secret read policy
                           │
                           └─ NAT gateway ── external destinations
```

When the gateway option is enabled, Terraform creates the namespace and TLS Secret. The Helm release creates the ServiceAccount by default; otherwise, it must already exist. The workload must use the **same names** configured here. Pod Identity does not require ServiceAccount annotations or an IAM OIDC provider. AWS credentials are temporary; no IAM user access keys are created.

The data plane connects outbound to the existing Konnect configuration and telemetry endpoints over TLS on port 443. With the optional AWS vault, it also needs access to the regional Secrets Manager endpoint; Bedrock calls need access to the approved Bedrock endpoint. The IAM role and networking must both permit the intended traffic.

### Naming and ownership

| Terraform identifier | Purpose |
| --- | --- |
| `module.ai_gateway_vpc` | Network infrastructure for the cluster. |
| `module.ai_gateway_eks_auto` | EKS Auto Mode cluster, node pools, and associated cluster/node roles. |
| `aws_iam_role.ai_gateway_data_plane` | IAM role assumed by the AI Gateway data plane through EKS Pod Identity. It can have separate permissions for multiple AWS services. |
| `data.aws_iam_policy_document.ai_gateway_data_plane_pod_identity_trust` | Who can assume the data plane role and under what conditions. |
| `aws_iam_role_policy.ai_gateway_bedrock_inference` | Approved Bedrock inference permissions attached to the data plane role. |
| `aws_iam_role_policy.ai_gateway_secrets_manager_read` | Optional Secrets Manager read and KMS decrypt permissions attached to the same role. |
| `aws_eks_pod_identity_association.ai_gateway_data_plane` | Association between the EKS cluster, namespace, ServiceAccount, and data plane role. |
| `aws_secretsmanager_secret.ai_gateway_secret_container` | Optional secret containers; secret values remain outside Terraform. |

The physical IAM role name is `<cluster-name>-ai-gateway-dp`. Customer deployment requires STS review and execution.

EKS Auto Mode includes the Pod Identity capability on Auto Mode nodes. Workloads on other compute types need separate compatibility and agent checks. The IAM principal executing Terraform must have the permissions to create the AWS resources, including `iam:PassRole` for the relevant role. Kubernetes RBAC and permissions to create Pod Identity associations must also be tightly controlled: principals able to create workloads using the selected ServiceAccount or associate roles can affect which workloads obtain credentials.

## Prerequisites

1. Terraform >= 1.5.7 and < 2.0, and AWS provider 6.x. The module versions are pinned in this template. Install AWS CLI and authenticate using the approved AWS credential chain. Do not put credentials in `.tf` or `.tfvars` files.
2. An approved account ID, region, Kubernetes version, unique cluster name, tags, non-overlapping VPC/subnet CIDRs, and at least two availability zones. Verify the selected Kubernetes version is supported by EKS and the gateway components at deployment time.
3. An approved path to the Kubernetes API. The API endpoint is private by default. The administrator must have network connectivity and DNS resolution to the VPC, for example through an existing corporate connection or an approved management host. Public API access is optional and must use explicitly approved IPv4 CIDRs; `0.0.0.0/0` is rejected.
4. At least one approved IAM role or user ARN in `cluster_admin_principal_arns`, or explicitly enable `enable_cluster_creator_admin_permissions`. Plan who can administer the cluster before applying.
5. For the optional Bedrock identity: exact approved model and/or inference-profile ARNs, the namespace and ServiceAccount, relevant Bedrock model access and regional availability, and the approved model routing and data residency requirements. Enabling Pod Identity with no approved model ARN fails the plan.
6. A customer-approved remote Terraform backend with encryption, access control, locking, backups, and a recovery procedure. The template intentionally does not hardcode a backend. Local state is suitable only for a controlled temporary lab and can contain sensitive infrastructure details. Configure the backend before using this template for shared environments.

The sample creates new network resources; it does **not** attach a cluster to an existing VPC. If STS provisions the VPC or cluster separately, adapt the relevant modules or extract the identity resources into the team's existing Terraform root; do not deploy a duplicate VPC or cluster merely to use this template. The optional gateway stage also requires the `kubectl`, `helm`, `kongctl`, and OpenSSL tools for preparation and validation, plus Kubernetes API access and the permissions described below.

## Configure and review

Copy `terraform.tfvars.example` to an untracked `terraform.tfvars`, then replace all example values. No example account, CIDR, Kubernetes version, principal, or model is an STS approval. The sample deliberately has no admin principal configured; add one or explicitly enable creator admin before planning.

### Input reference

| Input | Required or default | What to decide |
| --- | --- | --- |
| `aws_account_id` | Required | Expected 12-digit account ID; the provider refuses another account. |
| `aws_region` | Required | Region for AWS resources and regional Secrets Manager access. |
| `environment` | Required | Environment tag, such as `nonprod`. |
| `cluster_name` | Required | Unique EKS name; also used as a prefix for created resources. |
| `kubernetes_version` | Required | EKS version approved for this deployment. |
| `vpc_cidr` | Required | New VPC CIDR; must not conflict with connected networks. |
| `availability_zones` | Required | At least two distinct AZs in the selected region. |
| `public_subnet_cidrs`, `private_subnet_cidrs` | Required | One of each per AZ, ordered to match `availability_zones`. |
| `single_nat_gateway` | `false` | `true` creates a single-AZ egress dependency for a lower-cost lab; `false` provisions NAT per AZ with this subnet layout. |
| `endpoint_public_access_cidrs` | `[]` | Approved CIDRs for optional public Kubernetes API access; an empty list leaves private access only. |
| `cluster_admin_principal_arns` | `[]` | IAM principals granted Kubernetes cluster-admin access through EKS access entries. |
| `enable_cluster_creator_admin_permissions` | `false` | Whether to grant cluster admin to the Terraform caller. At least one admin principal or this option is required. |
| `eks_control_plane_log_types` | `api`, `audit`, `authenticator` | Approved EKS control-plane logs; an empty list disables them. |
| `eks_control_plane_log_retention_days` | `90` | CloudWatch retention for the EKS log group, using an AWS-supported period. |
| `eks_cluster_deletion_protection` | `false` | Whether EKS must reject deletion until protection is disabled. Decide explicitly for each environment. |
| `enable_ai_gateway_pod_identity` | `false` | Whether to create the data plane role, Bedrock policy, and Pod Identity association. At least one Bedrock ARN is required when enabled. |
| `enable_kong_ai_gateway` | `false` | Whether to create the namespace and TLS Secret and install the Helm data plane for an existing control plane. |
| `konnect_control_plane_host`, `konnect_telemetry_host` | `""` | Existing Konnect configuration and telemetry hostnames, without scheme or port; required when enabled. |
| `kong_data_plane_public_certificate_path`, `kong_data_plane_private_key_path` | `""` | Local paths to the registered public PEM certificate and matching private key; required when enabled. The key enters Terraform state and plans. |
| `ai_gateway_data_plane_namespace`, `ai_gateway_data_plane_service_account` | `kong`, `kong-dp` | Exact namespace and ServiceAccount used by the data plane and Pod Identity association. |
| `kong_data_plane_tls_secret_name` | `kong-cluster-cert` | TLS Secret created by Terraform in the dedicated namespace. |
| `kong_helm_release_name`, `kong_helm_repository`, `kong_helm_chart`, `kong_helm_chart_version` | `kong-ai-gateway`, `https://charts.konghq.com`, `kong`, `3.4.1` | Helm release and chart settings; verify chart compatibility and registry access. |
| `kong_helm_timeout_seconds`, `kong_helm_create_service_account` | `600`, `true` | Release timeout and whether Helm creates the named ServiceAccount. |
| `kong_data_plane_image_repository`, `kong_data_plane_image_tag` | `kong/kong-ai-gateway`, `2.3.0-distroless` | AI Gateway image; verify architecture and availability. |
| `kong_init_image_repository`, `kong_init_image_tag` | `busybox`, `1.36` | Shell-based `clear-stale-pid` init-container image. |
| `kong_data_plane_replicas`, `kong_data_plane_cpu_request`, `kong_data_plane_memory_request` | `1`, `1`, `2Gi` | Initial pod count and resource requests; not a production sizing recommendation. |
| `kong_proxy_service_type`, `kong_proxy_acm_certificate_arn` | `ClusterIP`, `""` | Proxy exposure. `LoadBalancer` requests a public NLB and requires an ACM certificate ARN. |
| `bedrock_model_arns` | `[]` | Explicit approved model/profile ARNs on which invocation is allowed; no wildcards. |
| `enable_bedrock_streaming` | `true` | Whether to allow streaming invocation in addition to normal inference. |
| `inference_profile_arns` | `[]` | Profile ARNs allowed for `GetInferenceProfile`; include them in `bedrock_model_arns` too. |
| `secrets_manager_secrets` | `{}` | Optional metadata for new secret containers; STS supplies values separately. |
| `secrets_manager_read_prefix` | `null` | Optional name prefix allowing reads of existing and future matching secrets in this account and region. |
| `secrets_manager_prefix_kms_key_arns` | `[]` | Optional existing customer-managed KMS keys for prefix-scoped secrets. |
| `tags` | `{}` | Additional non-sensitive customer tags. The provider adds `Environment` and `ManagedBy`. |

### Deployment steps

1. Configure the approved Terraform backend and authenticate to AWS. Confirm the caller and account with `aws sts get-caller-identity` without sharing credentials.
2. Copy the example, fill in the inputs, and verify network access, admin access, and model/secret decisions with STS. For the first deployment, leave `enable_kong_ai_gateway = false` so the cluster exists before Kubernetes and Helm access is needed:

```sh
cp terraform.tfvars.example terraform.tfvars
```

3. After editing `terraform.tfvars`, initialize and review validation and the deployment plan:

```sh
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -out=reviewed.tfplan
```

4. Review the plan, expected AWS account, permissions, network exposure, and estimated costs with the responsible teams. A saved plan can contain sensitive information: protect it like state and never commit it.
5. After approval, apply that exact reviewed plan:

```sh
terraform apply reviewed.tfplan
```

6. Use `terraform output` to retrieve infrastructure identifiers. If desired, follow the separate gateway stage below using the same root and state; otherwise install the workload separately. Ensure its namespace and ServiceAccount match the association.

This template does not execute Terraform or make AWS changes merely by being provided. The provider enforces `aws_account_id` to reduce the risk of targeting the wrong account.

## Optional Helm data plane for an existing Konnect AI Gateway

This option is disabled by default and is independent of Pod Identity. Enable Pod Identity separately for Bedrock or Secrets Manager access; the current identity implementation requires at least one approved Bedrock ARN even if only the vault is being tested. The optional gateway configuration is a starting point, not an STS-approved or end-to-end verified deployment.

1. Create the AI Gateway control plane with `kongctl`, generate the data plane certificate and private key with OpenSSL, and register the public certificate in Konnect separately. Obtain its configuration and telemetry endpoint hostnames. Confirm the key matches the registered certificate, the certificate is unexpired, and the intended control plane and region are correct. Never commit the key or credentials.
2. First deploy and verify the infrastructure in a separately reviewed operation. From an authorized network, confirm Kubernetes API access and RBAC for namespaces, Secrets and Helm resources. Enable the gateway and provide the two hostnames and paths to the PEM files available to the Terraform runner. Use a new, dedicated namespace: Terraform manages and can delete it. An existing namespace or Secret requires a separately reviewed import/migration; do not overwrite shared resources.
3. Review `kong-variables.tf`: the default chart is `kong` 3.4.1, runtime image `kong/kong-ai-gateway:2.3.0-distroless`, and shell-based init image `busybox:1.36`. Confirm compatibility, image availability, registry access, and the runtime version with the AI Gateway 2.x documentation or Konnect deployment wizard. The init-image override is needed because the distroless image lacks the shell used by the chart's init container. The proxy defaults to an internal `ClusterIP`.
4. Plan again, review changes, cost, state, access and scope, then apply only with approval. Both PEM files must exist on the Terraform runner at plan time. **The private key is stored in Terraform state and saved plans**, despite sensitive output redaction. Secure the state backend, backups, plans and runner with approved encryption and access controls; do not commit these files. Kubernetes Secret access and encryption must also be reviewed. This approach is not approved for production until STS accepts its security implications.
5. Verify the Helm release, pod readiness, intended ServiceAccount and connected data plane in Konnect. Configure providers, models and policies separately with `kongctl`, and test Bedrock using synthetic data. Helm readiness or certificate registration alone does not prove connectivity or inference.

For example, after creating the control plane and certificate, the gateway stage inputs are:

```hcl
enable_kong_ai_gateway                  = true
konnect_control_plane_host              = "example.us.cp.konghq.com"
konnect_telemetry_host                  = "example.us.tp.konghq.com"
kong_data_plane_public_certificate_path = "/secure/path/data-plane.crt"
kong_data_plane_private_key_path        = "/secure/path/data-plane.key"
```

Replace the hostnames and paths with actual values. Terraform checks for PEM markers, but does **not** verify certificate/key matching, expiry, registration in Konnect, or compatibility. The namespace and Secret are created before Helm; Helm does not create the namespace. The `kongctl/` directory includes a control-plane example and independent child examples, not a prerequisite to enable every feature.

When `kong_helm_create_service_account = false`, a separately managed ServiceAccount must be present in the namespace before the release can start. For a newly Terraform-created namespace, arrange this prerequisite in a separate reviewed step or keep the default `true`.

Disabling the option after deployment plans to destroy the Terraform-managed Helm release, TLS Secret and namespace. **Deleting the namespace also deletes other resources inside it**, even those not managed by Terraform. The existing Konnect control plane and its certificate registration remain outside this root's lifecycle. Review ownership and every plan carefully.

For a state created by an earlier draft that managed Konnect resources, do not apply this version directly: Terraform may plan to destroy the existing control plane and certificate, while the new namespace and Secret may already exist. Review and agree a separate state migration and import procedure before making any changes.

### Optional public NLB for a lab

Set `kong_proxy_service_type = "LoadBalancer"` and supply `kong_proxy_acm_certificate_arn` for a certificate in the cluster's AWS account and region. This requests an internet-facing EKS Auto Mode NLB with a TLS listener on port 443, IP targets, and an SSL backend annotation targeting the chart's HTTPS port 8443. The HTTP proxy service port is disabled. Public access and a self-signed certificate are suitable only for an explicitly approved lab, not a production security baseline; review access restrictions, DNS and certificate trust. The NLB incurs additional charges.

In one EKS Auto Mode lab, this annotation produced a TLS target group on port 8443 and a TLS listener on port 443. AWS does not list the backend-protocol annotation among its documented Auto Mode annotations, so confirm support and inspect the actual listener, target group protocol and health for each deployment. Test an HTTPS request before relying on the design. An NLB TLS target group encrypts backend connections but does not validate the target certificate.

### Lab evidence and limits

In a separate non-production lab, a hybrid AI Gateway 2.3.0 data plane connected to Konnect, and an AWS vault read a Secrets Manager value through EKS Pod Identity. An illustrative OpenAI model request then completed through the public NLB; this is not a Bedrock-through-Kong test. That lab used a namespace and TLS Secret created outside Terraform and a control plane created by an earlier Terraform draft. The current namespace/Secret resources and existing-control-plane workflow have not been applied end to end. STS must validate its own account, network, credentials, model, versions and security controls.

## Bedrock permissions and trust

Pod Identity is **disabled by default** so that infrastructure-only labs do not inadvertently grant model access. To enable it, set `enable_ai_gateway_pod_identity = true` and supply approved ARNs and ServiceAccount details.

### Models identified during STS discovery

STS identified Amazon Bedrock as the intended provider and named the following Anthropic models in response to the approved-model question. These names capture the discovery answer; they are **not a verified list of deployable ARNs, enabled account access, or approved cross-region routes**.

| Model named by STS | AWS documentation reference | Decision still required |
| --- | --- | --- |
| Claude Opus 5 | [AWS model card](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-anthropic-claude-opus-5.html) | Confirm the exact model/profile, account access, endpoint, and permitted destination regions. |
| Claude Sonnet 5 | [AWS model card](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-anthropic-claude-sonnet-5.html) | Confirm the exact model/profile, account access, endpoint, and permitted destination regions. |
| Claude Haiku 5 | The exact model/version corresponding to this discovery name requires confirmation. | Obtain the exact AWS identifier and approval; do not substitute a different Haiku version automatically. |

For example, the AWS model cards list `us.anthropic.claude-opus-5` and `us.anthropic.claude-sonnet-5` as US geographic inference profile IDs. A geographic profile can route requests to multiple AWS regions. The IDs are **not IAM ARN values**, and their inclusion here does not authorize their use. STS must confirm the actual profiles and destination regions, account access, IAM ARNs, and compatibility with the selected AI Gateway runtime before populating `bedrock_model_arns` and `inference_profile_arns`. Recheck AWS documentation and `GetInferenceProfile` when preparing the deployment, since profile routing can change.

This template grants IAM permissions only; it does not define an AI Gateway provider, a default model, or fallback routing. Those are configured separately after STS's decisions.

For example, the following illustrates a single **regional on-demand** foundation model. It is an example, not an approved STS model or production setting:

```hcl
enable_ai_gateway_pod_identity        = true
ai_gateway_data_plane_namespace       = "kong"
ai_gateway_data_plane_service_account = "kong-dp"
bedrock_model_arns = [
  "arn:aws:bedrock:us-east-1::foundation-model/amazon.nova-micro-v1:0"
]
```

The trust policy allows `pods.eks.amazonaws.com` to perform `sts:AssumeRole` and `sts:TagSession`, scoped by the cluster ARN, namespace, and ServiceAccount request tags. Session tags are explicitly enabled in the association. If the tags are disabled or unavailable, the trust conditions will reject the assumption. Pod Identity and scoped trust were exercised in a separate lab; validate the exact configuration again in STS's environment.

The permission policy allows `bedrock:InvokeModel` and, by default, `bedrock:InvokeModelWithResponseStream` only for the ARNs provided. Set `enable_bedrock_streaming = false` when streaming is not needed. AWS uses these permissions for the corresponding Converse operations as well.

For an inference profile, `bedrock_model_arns` must include the profile and the underlying foundation-model ARNs required in the applicable destination regions. Put the profile ARNs in `inference_profile_arns` as well; this grants `bedrock:GetInferenceProfile` on those profiles. Cross-region routing, model availability, applicable SCPs, model access prerequisites, and permitted data residency must be confirmed independently. Additional features or model types may require different permissions; do not broaden this example without review.

## Optional Secrets Manager containers

AWS Secrets Manager is a managed service, not a provisioned "vault" resource. This template can create **secret containers** and grant the existing data plane role `secretsmanager:GetSecretValue` on exact secret ARNs and/or an approved secret-name prefix. An AI Gateway Vault is a separate Konnect entity that references the AWS backend; it does not create AWS secrets or define the IAM boundary. Configuring it remains a separate manual activity.

Enable Pod Identity, provide an approved Bedrock model ARN, and add an entry such as:

```hcl
secrets_manager_secrets = {
  provider_credentials = {
    name                    = "example-ai-gateway/nonprod/provider-credentials"
    description             = "Data plane credential container"
    recovery_window_in_days = 30
    # Optional customer-managed key in the same account and region:
    # kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/KEY-ID"
  }
}
```

Names and descriptions are metadata, not encrypted secret values. Terraform creates no secret version; STS must populate it outside Terraform using an approved secure workflow. Do not pass values in command-line arguments, shell history, Terraform variables, or source files. Reading an empty container fails until a version exists.

By default the secret uses the AWS managed `aws/secretsmanager` key. For a customer-managed KMS key, the IAM policy grants `kms:Decrypt` only via Secrets Manager in this region and for the corresponding secret's encryption context. The KMS key policy or grant must also allow the role; the identity writing a value needs its own permissions. This template does not create or modify a KMS key or its policy.

For a logical namespace of existing and future secrets in the **same account and region**, optionally set:

```hcl
secrets_manager_read_prefix = "kong-ai-non-prod/"
# Optional existing customer-managed keys encrypting secrets under that prefix:
secrets_manager_prefix_kms_key_arns = []
```

This grants the data plane role `GetSecretValue` for all Secrets Manager ARNs under the exact prefix, including future secrets created outside Terraform. The trailing slash is mandatory; wildcards are rejected in the input. Review who can create or rename secrets under the prefix, because any qualifying secret becomes readable by the role. Terraform does not create a folder or populate secret values, nor grant the workload `CreateSecret` or `PutSecretValue`. A separately authorized STS administrator or automation must create and populate secrets.

When prefix-scoped secrets use customer-managed KMS keys, list their full key ARNs in `secrets_manager_prefix_kms_key_arns`; this grants `kms:Decrypt` on those keys only through the regional Secrets Manager service and for matching secret-ARN encryption contexts. Key policies or grants must permit the role. AWS-managed key handling is different and does not require listing a key ARN here. Cross-account secrets, rotation, private connectivity and gateway vault configuration require separate design and validation.

The AI Gateway documentation describes references of the form `{vault://vault-name/secret-key}`; exact AWS secret names and JSON-key path encoding must be checked against the deployed version. The vault name is a Konnect identifier and is **not automatically an AWS secret-name prefix**. Verify the selected gateway version's AWS vault credential chain and the Pod Identity integration end to end; the template alone does not establish or prove either.

Each secret incurs charges. On destroy, the configured 7–30 day recovery window schedules deletion; the secret is not immediately removed and charges may continue until deletion completes. Do not force-delete secrets during routine teardown.

## Operational and security considerations

- NAT gateways and public IPv4 addresses incur hourly and data-processing charges. `single_nat_gateway = true` reduces the lab footprint but creates a single-AZ egress dependency; the default is one NAT gateway per AZ.
- EKS control plane, Auto Mode compute, EC2/EBS, logs, NAT, and any subsequently created load balancers or endpoints incur charges. Nodes are provisioned dynamically; the built-in pools do not guarantee a fixed node count or instance type.
- The VPC module provisions general outbound connectivity. This is not an egress allowlist or a private-only architecture. STS must approve firewalling, DNS, registry access, endpoint access, and any PrivateLink design. No Bedrock or Konnect interface endpoint is included here.
- The configurable EKS control-plane logging, retention, and deletion-protection settings and the module's remaining defaults for encryption/KMS, security groups, and nodes are not an STS security baseline. Review the plan against STS requirements, including sensitive log handling, monitoring, upgrades, and backups.
- Restrict who can assume or pass the workload IAM role, create associations, and create or modify workloads using the chosen ServiceAccount. Review AWS organization policies, permission boundaries, and IAM Access Analyzer findings.
- Model access decisions, budget controls, prompt logging policy, consumer identity and authorization, availability, and production controls remain STS decisions. Never use real sensitive prompts for a lab.
- Do not place credentials or certificate private keys in this repository. The optional TLS Secret places its private key in Terraform state and plans; protect the backend and artifacts accordingly.

## Validate after deployment

From an authorized network and IAM context, confirm the EKS API, access entry, and association. Replace placeholders with approved values:

```sh
aws eks describe-cluster --name <cluster-name> --region <region> --query 'cluster.status'
aws eks list-pod-identity-associations --cluster-name <cluster-name> --region <region>
```

After installation, verify that the pod uses the exact intended ServiceAccount and that the association matches it. For the optional gateway, also check `helm status`, pod readiness, `kongctl get ai-gateway nodes --gateway-id <gateway-id>`, and the proxy Service. If using an NLB, inspect listener, target group protocol and health, then test from an approved client. Verify effective IAM access and model availability using an approved synthetic test through the intended workload; never print temporary credentials. A successful Terraform apply or association alone does not prove that Bedrock invocation works.

## Cleanup for an approved temporary lab

First remove separately managed Kubernetes workloads and resources, including any load balancers and interface endpoints, in their owning workflow. Review the Terraform state and a destroy plan for the intended account and workspace before applying it. Preserve logs or other evidence as required by STS policy. Terraform must never destroy shared or customer-owned infrastructure that this root does not own.

If cluster deletion protection is enabled, disable it through an approved change and apply that change before destroying the cluster. Secrets Manager containers are scheduled for deletion using their configured recovery window; inspect and handle their lifecycle according to STS policy.

```sh
terraform plan -destroy -out=reviewed-destroy.tfplan
terraform apply reviewed-destroy.tfplan
```

Afterward verify that the cluster, Auto Mode nodes and volumes, NAT gateways, Elastic IPs, load balancers, and other billable lab resources are gone. Retain or remove state and logs according to the approved records policy.
