# EKS Auto Mode and AI Gateway template

**Kong Professional Services | Customer implementation template**

This Terraform root creates a new AWS network and EKS Auto Mode cluster. It can provide an EKS Pod Identity role for approved Bedrock models and the intended Secrets Manager backend, and install a hybrid AI Gateway data plane connected to an existing Konnect control plane. Both deployment flags are disabled by default; enable and configure them for the intended architecture.

This is a starting point for STS review, not a production-certified configuration. STS owns infrastructure, deployment, and approval of environment-specific settings.

## Contents

- [Prerequisites](#prerequisites)
- [1. Prepare the Konnect control plane](#1-prepare-the-konnect-control-plane)
- [2. Deploy AWS infrastructure](#2-deploy-aws-infrastructure)
- [3. Deploy the optional data plane](#3-deploy-the-optional-data-plane)
- [4. Validate the gateway](#4-validate-the-gateway)
- [Secrets Manager access](#secrets-manager-access)
- [NLB exposure](#nlb-exposure)
- [Lifecycle and cleanup](#lifecycle-and-cleanup)
- [Reference](#reference)

## Prerequisites

- Terraform `>= 1.5.7, < 2.0`, AWS CLI, and approved AWS credentials. The gateway stage also requires Kubernetes API access, Kubernetes RBAC, and an AWS CLI available to the Terraform runner. Install `kubectl`, Helm, `kongctl`, and OpenSSL for preparation and validation.
- An approved AWS account, region, cluster name, supported Kubernetes version, non-overlapping CIDRs, at least two availability zones, tags, and at least one cluster administrator.
- An approved network path to the Kubernetes API. Private access is always enabled; optional public access must be restricted to approved IPv4 CIDRs.
- An approved encrypted Terraform backend with access control, locking, backups, and recovery. **The optional Kubernetes TLS Secret puts its private key in Terraform state and saved plans.** Protect both and never commit them or the PEM key.
- For Bedrock: approved model or inference-profile ARNs, account access, regional availability, and data residency decisions. For Secrets Manager: approved secret names or prefix and, if applicable, KMS key permissions.
- For the gateway stage: an existing Konnect AI Gateway 2.x control plane, its configuration and telemetry hostnames, and the registered public certificate with matching private key. Provision these separately, as described below.

The template creates a **new VPC and cluster**; it does not attach to existing infrastructure. Adapt the configuration if STS owns those resources separately rather than creating duplicates.

## 1. Prepare the Konnect control plane

Create the AI Gateway control plane using `kongctl`, generate the data plane certificate and key with an approved procedure, and register **only the public certificate** in Konnect. Confirm the certificate is unexpired and matches the private key, and record the configuration and telemetry hostnames. The [kongctl examples](kongctl/README.md) include a control-plane example and certificate preparation guidance.

Terraform does not manage this control plane, register its certificate, or configure its providers, models, consumers or policies. Confirm Konnect organization, region and ownership before using the examples; never apply the new-control-plane example to an existing Terraform-managed gateway without an approved migration.

For an illustrative **new** control plane, first generate a certificate using a private directory outside this repository. Use a self-signed certificate only when the deployment and security policy allow it:

```sh
umask 077
CERT_DIR="/secure/path"  # Replace with an existing protected directory.
openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 30 \
  -keyout "$CERT_DIR/data-plane.key" -out "$CERT_DIR/data-plane.crt" \
  -subj '/CN=ai-gateway-data-plane'
mkdir -p kongctl/certs
cp "$CERT_DIR/data-plane.crt" kongctl/certs/data-plane.crt
```

Protect the private key, verify the certificate and its expiration, and plan rotation. The `kongctl/certs/` directory is ignored by Git; copy only the public certificate there. Edit the unique gateway name and namespace in `kongctl/00-ai-gateway-control-plane.yaml`, confirm your `kongctl` organization and region, and review before creating it:

```sh
kongctl get organization -o json
kongctl diff --mode apply -f kongctl/00-ai-gateway-control-plane.yaml
kongctl apply -f kongctl/00-ai-gateway-control-plane.yaml
kongctl get ai-gateway <gateway-name> -o json
```

Record the gateway ID and remove `https://` from its `endpoints.configuration` and `endpoints.telemetry` values when supplying the Terraform host inputs. For an existing gateway, skip `00` and use its verified ID and matching certificate instead.

The control plane and registered certificate are the only Konnect prerequisites for the Terraform deployment. Configure approved providers and models separately; the optional test configuration is described in [Validate the gateway](#4-validate-the-gateway).

## 2. Deploy AWS infrastructure

Copy and edit the example values:

```sh
cp terraform.tfvars.example terraform.tfvars
```

Set the required account, region, network, cluster and admin inputs. Leave `enable_kong_ai_gateway = false` for this first stage: the Kubernetes and Helm providers need an existing, reachable cluster. If the data plane needs Bedrock or Secrets Manager, set `enable_ai_gateway_pod_identity = true` and provide `bedrock_model_arns`. The current identity implementation requires at least one approved Bedrock ARN even if only Secrets Manager is used.

Initialize and review the plan:

```sh
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -out=reviewed.tfplan
```

Review account, scope, costs, permissions, networking and any replacements or deletions. After approval, apply the exact plan:

```sh
terraform apply reviewed.tfplan
terraform output
```

Saved plans can contain sensitive information; protect them like state. NAT gateways, EKS, compute, logs and other AWS resources incur charges until retired.

## 3. Deploy the optional data plane

After the cluster is running and reachable, add the following to the same `terraform.tfvars`, substituting the real hostnames and secure PEM paths:

```hcl
enable_kong_ai_gateway                  = true
konnect_control_plane_host              = "example.us.cp.konghq.com"
konnect_telemetry_host                  = "example.us.tp.konghq.com"
kong_data_plane_public_certificate_path = "/secure/path/data-plane.crt"
kong_data_plane_private_key_path        = "/secure/path/data-plane.key"
```

Both files must exist on the Terraform runner at plan time. Terraform checks PEM markers, but does **not** prove key matching, expiry, or registration in Konnect. The private key is stored in state and plans; STS must approve that security model before deployment.

Plan and apply again only after review:

```sh
terraform plan -out=reviewed-gateway.tfplan
terraform apply reviewed-gateway.tfplan
```

Terraform creates a dedicated namespace and TLS Secret, then installs the Helm release. By default Helm creates the `kong-dp` ServiceAccount in namespace `kong`; these names must match the Pod Identity association. If `kong_helm_create_service_account = false`, arrange the existing ServiceAccount separately before Helm starts. Existing namespaces or Secrets require a separately reviewed import or migration—do not overwrite shared resources.

The defaults are chart `kong` 3.4.1, image `kong/kong-ai-gateway:2.3.0-distroless`, one replica and a `ClusterIP` proxy. The `busybox:1.36` override supplies the shell required by the chart's `clear-stale-pid` init container. Confirm versions, architecture, resources and registry availability. All settings are exposed in `kong-variables.tf`.

## 4. Validate the gateway

After deploying the data plane, verify that Konnect and AWS access work together. The [Bedrock validation example](kongctl/README.md#bedrock-validation-example) provides a provider and model using Pod Identity; it was tested with a lab model, not an STS-approved model. For an illustrative OpenAI test instead, the [test guide](kongctl/README.md#apply-child-objects-together) describes the vault, provider, consumer and model. OpenAI is not the intended Bedrock production configuration; its combined-file workflow has not yet been tested on new objects.

Check the deployment from an authorized context:

```sh
aws eks describe-cluster --name <cluster-name> --region <region> --query 'cluster.status'
aws eks list-pod-identity-associations --cluster-name <cluster-name> --region <region>
helm status <release-name> -n <namespace>
kubectl get pods,serviceaccount,svc -n <namespace>
kongctl get ai-gateway nodes --gateway-id <gateway-id> -o json
```

Confirm the pod uses the intended ServiceAccount and that Konnect reports a compatible, recently connected node. Test approved model access with synthetic data; Helm readiness or Pod Identity association alone does not prove inference.

## Secrets Manager access

STS identified AWS Secrets Manager as the intended secret backend. Configure the data plane's IAM access to the approved secret names or prefix, and configure the corresponding AI Vault in Konnect. The template leaves the prefix unset until STS approves its scope; an unset prefix does not grant access.

To allow reads of current and future secrets under an approved prefix in the selected account and region:

```hcl
secrets_manager_read_prefix = "kong-ai-non-prod/"
```

Enable Pod Identity and specify an approved Bedrock ARN as described above. The prefix must end in `/` and contain no wildcards; the generated IAM policy grants `secretsmanager:GetSecretValue` to all matching names. It does not grant secret creation or writes. Control who can create secrets under the prefix. `secrets_manager_secrets` can optionally create named secret **containers**, not values; populate versions outside Terraform. For customer-managed KMS keys, configure `secrets_manager_prefix_kms_key_arns` or the container's `kms_key_arn`, and ensure the key policy or grant also permits access.

A Konnect AI Vault is a separate configuration object. Its name does not automatically constrain the AWS secret prefix; network connectivity, IAM and the vault reference must all be verified. See [kongctl examples](kongctl/README.md).

## NLB exposure

For the intended private deployment, set an ACM certificate ARN and request an internal NLB:

```hcl
kong_proxy_service_type         = "LoadBalancer"
kong_proxy_acm_certificate_arn = "<ACM-certificate-ARN>"
kong_proxy_nlb_scheme           = "internal"
```

The ARN must identify a certificate usable in the cluster's account and region. `kong_proxy_nlb_scheme` defaults to `internal`; review subnet tags, DNS, client connectivity and network controls with STS. The default Service type remains `ClusterIP` until `LoadBalancer` is selected. For an explicitly approved public lab only, set the scheme to `internet-facing`. The NLB uses a TLS listener on 443 and TLS backend targeting Kong on 8443; the HTTP proxy port is disabled. In one lab, the requested backend annotation produced a TLS target group, but AWS does not list it among the documented Auto Mode annotations. Verify listener, target protocol, target health and a client request in each environment. NLB backend TLS encrypts traffic but does not validate the target certificate. NLBs incur additional charges.

## Lifecycle and cleanup

Disabling the gateway option plans to remove the Helm release, TLS Secret and namespace. **Deleting a namespace also deletes resources inside it that Terraform may not manage.** The external Konnect control plane and certificate registration are not removed by this template. Review ownership and the full plan before every change.

If upgrading from an earlier draft that managed the Konnect gateway in Terraform, do **not** apply directly: Terraform may plan to destroy the existing control plane and certificate, and the namespace or Secret may already exist. Agree a separate state migration and import procedure first.

For an approved temporary-lab retirement, review the entire state and a destroy plan, including externally managed Kubernetes, Konnect and AWS resources. Disable EKS deletion protection separately if needed. Secrets Manager containers are scheduled for deletion using their recovery window; KMS keys and other resources may remain billable. Never destroy shared infrastructure or force-delete secrets without approval.

## Reference

- `variables.tf`, `kong-variables.tf`: inputs, defaults and validation.
- `network.tf`, `eks.tf`: VPC and EKS Auto Mode modules and cluster access.
- `pod-identity.tf`, `bedrock.tf`, `secrets-manager.tf`: IAM trust, model access and Secrets Manager permissions/containers.
- `kong.tf`: Kubernetes namespace, TLS Secret and Helm release for an existing control plane.
- `terraform.tfvars.example`: example inputs; replace placeholders before planning.
- [`kongctl/`](kongctl/README.md): separate declarative examples and test procedure.

Terraform combines all `.tf` files in this directory into **one configuration and state**. No PrivateLink endpoints, disaster recovery implementation, production security baseline, model fallback, or application governance are provisioned automatically. Review `terraform.tfvars.example` and the variable descriptions for all available settings.
