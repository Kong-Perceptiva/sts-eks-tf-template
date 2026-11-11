# EKS Auto Mode infrastructure and Pod Identity template

**Kong Professional Services | Customer implementation template**

This template provisions an AWS infrastructure foundation for a workload running on EKS Auto Mode. Optionally, it creates an IAM role and an EKS Pod Identity association that allow an approved Kubernetes ServiceAccount to invoke explicitly approved Amazon Bedrock models and read selected AWS Secrets Manager secrets.

This is a starting point for STS infrastructure review, not a deployed or production-certified configuration. STS owns the AWS account, networking, Terraform execution, and operational controls. Values such as CIDRs, cluster access, availability zones, model ARNs, and tags must be approved for each environment.

## Scope

Terraform manages:

- A VPC with public and private subnets in at least two availability zones, internet connectivity, and NAT gateways.
- An EKS Auto Mode cluster, AWS-managed node pools, and the cluster and node IAM roles managed by the EKS module.
- Explicit EKS access entries for approved administrator principals, or an explicitly enabled creator-admin entry.
- Optionally, one data plane IAM role, its Pod Identity trust policy, a Bedrock inference permission policy, and an EKS Pod Identity association.
- Optionally, Secrets Manager secret containers and a read-only IAM policy for those exact secrets and/or an explicitly approved name prefix. Terraform creates secret metadata only, not values or versions.

Terraform **does not** deploy the gateway, its ServiceAccount, Kubernetes manifests, Helm releases, Konnect resources, gateway vault configuration, provider/model configuration, TLS certificates, secret values, or PrivateLink endpoints. Gateway configuration and installation are performed separately. This template does not implement disaster recovery, Bedrock PrivateLink, Konnect PrivateLink, application authentication, or AI governance.

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
                           └─ NAT gateway ── approved external destinations
```

The namespace and ServiceAccount are not created by this template. The installation that creates the workload must use the **same names** configured here. Pod Identity does not require ServiceAccount annotations or an IAM OIDC provider. AWS credentials are temporary; no IAM user access keys are created.

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

The physical IAM role name is `<cluster-name>-ai-gateway-dp`. No template deployment has been performed by Kong Professional Services.

EKS Auto Mode includes the Pod Identity capability on Auto Mode nodes. Workloads on other compute types need separate compatibility and agent checks. The IAM principal executing Terraform must have the permissions to create the AWS resources, including `iam:PassRole` for the relevant role. Kubernetes RBAC and permissions to create Pod Identity associations must also be tightly controlled: principals able to create workloads using the selected ServiceAccount or associate roles can affect which workloads obtain credentials.

## Prerequisites

1. Terraform >= 1.5.7 and < 2.0, and AWS provider 6.x. The module versions are pinned in this template. Install AWS CLI and authenticate using the approved AWS credential chain. Do not put credentials in `.tf` or `.tfvars` files.
2. An approved account ID, region, Kubernetes version, unique cluster name, tags, non-overlapping VPC/subnet CIDRs, and at least two availability zones. Verify the selected Kubernetes version is supported by EKS and the gateway components at deployment time.
3. An approved path to the Kubernetes API. The API endpoint is private by default. The administrator must have network connectivity and DNS resolution to the VPC, for example through an existing corporate connection or an approved management host. Public API access is optional and must use explicitly approved IPv4 CIDRs; `0.0.0.0/0` is rejected.
4. At least one approved IAM role or user ARN in `cluster_admin_principal_arns`, or explicitly enable `enable_cluster_creator_admin_permissions`. Plan who can administer the cluster before applying.
5. For the optional Bedrock identity: exact approved model and/or inference-profile ARNs, the namespace and ServiceAccount, relevant Bedrock model access and regional availability, and the approved model routing and data residency requirements. Enabling Pod Identity with no approved model ARN fails the plan.
6. A customer-approved remote Terraform backend with encryption, access control, locking, backups, and a recovery procedure. The template intentionally does not hardcode a backend. Local state is suitable only for a controlled temporary lab and can contain sensitive infrastructure details. Configure the backend before using this template for shared environments.

The sample creates new network resources; it does **not** attach a cluster to an existing VPC. If STS provisions the VPC or cluster separately, adapt the relevant modules or extract the identity resources into the team's existing Terraform root; do not deploy a duplicate VPC or cluster merely to use this template.

## Configure and review

Copy `terraform.tfvars.example` to an untracked `terraform.tfvars`, then replace all example values. No example account, CIDR, Kubernetes version, principal, or model is an STS approval.

```sh
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -out=reviewed.tfplan
```

Review the plan, expected AWS account, permissions, network exposure, and estimated costs with the responsible teams. After approval, apply the reviewed plan:

```sh
terraform apply reviewed.tfplan
```

This template does not execute Terraform or make AWS changes merely by being provided. The provider enforces `aws_account_id` to reduce the risk of targeting the wrong account.

## Bedrock permissions and trust

Pod Identity is **disabled by default** so that infrastructure-only labs do not inadvertently grant model access. To enable it, set `enable_ai_gateway_pod_identity = true` and supply approved ARNs and ServiceAccount details.

For example, the following illustrates a single **regional on-demand** foundation model. It is an example, not an approved STS model or production setting:

```hcl
enable_ai_gateway_pod_identity        = true
ai_gateway_data_plane_namespace       = "kong"
ai_gateway_data_plane_service_account = "kong-dp"
bedrock_model_arns = [
  "arn:aws:bedrock:us-east-1::foundation-model/amazon.nova-micro-v1:0"
]
```

The trust policy allows `pods.eks.amazonaws.com` to perform `sts:AssumeRole` and `sts:TagSession`, scoped by the cluster ARN, namespace, and ServiceAccount request tags. Session tags are explicitly enabled in the association. If the tags are disabled or unavailable, the trust conditions will reject the assumption. This restriction pattern must be validated in STS's environment; the earlier lab verified Pod Identity but did **not** validate these exact trust conditions.

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
secrets_manager_read_prefix = "example-ai-gateway/nonprod/"
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
- The EKS module's defaults for control-plane logging, encryption/KMS, security groups, node settings, and retention are not an STS security baseline. Review the plan and module configuration against STS requirements, including sensitive log handling, encryption, monitoring, upgrades, backups, and cluster deletion protection.
- Restrict who can assume or pass the workload IAM role, create associations, and create or modify workloads using the chosen ServiceAccount. Review AWS organization policies, permission boundaries, and IAM Access Analyzer findings.
- Model access decisions, budget controls, prompt logging policy, consumer identity and authorization, availability, and production controls remain STS decisions. Never use real sensitive prompts for a lab.
- Do not place credentials or certificate private keys in this repository. If secrets or private keys are managed using Terraform elsewhere, they may appear in state; protect the backend accordingly.

## Validate after deployment

From an authorized network and IAM context, confirm the EKS API, access entry, and association. Replace placeholders with approved values:

```sh
aws eks describe-cluster --name <cluster-name> --region <region> --query 'cluster.status'
aws eks list-pod-identity-associations --cluster-name <cluster-name> --region <region>
```

After the workload is installed separately, verify that the pod uses the exact intended ServiceAccount and that the association matches it. Verify effective IAM access and model availability using an approved synthetic test through the intended workload; never print temporary credentials. A successful Terraform apply or association alone does not prove that Bedrock invocation works.

## Cleanup for an approved temporary lab

First remove separately managed Kubernetes workloads and resources, including any load balancers and interface endpoints, in their owning workflow. Review the Terraform state and a destroy plan for the intended account and workspace before applying it. Preserve logs or other evidence as required by STS policy. Terraform must never destroy shared or customer-owned infrastructure that this root does not own.

```sh
terraform plan -destroy -out=reviewed-destroy.tfplan
terraform apply reviewed-destroy.tfplan
```

Afterward verify that the cluster, Auto Mode nodes and volumes, NAT gateways, Elastic IPs, load balancers, and other billable lab resources are gone. Retain or remove state and logs according to the approved records policy.
