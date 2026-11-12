# AI Gateway declarative examples

**Kong Professional Services | Illustrative non-production configuration**

These files are independent of Terraform. They illustrate an existing or new hybrid AI Gateway, an AWS Secrets Manager vault, an OpenAI provider, a short-lived application credential, and a logical `sts-chat` model. OpenAI and this model are lab examples, not approved STS production decisions. The intended customer use case is Bedrock; its exact model and access remain subject to approval.

## Contents

- [Files and order](#files-and-order)
- [Prerequisites and example commands](#prerequisites-and-example-commands)
- [Apply child objects together](#apply-child-objects-together)
- [Bedrock validation example](#bedrock-validation-example)
- [Example synthetic request](#example-synthetic-request)

## Files and order

1. `00-ai-gateway-control-plane.yaml`: example for creating a **new** control plane and registering a public certificate. It reads `certs/data-plane.crt` relative to this file. Generate the certificate and key separately; do not commit the key. Set a unique name and namespace before use.
2. `10-aws-secrets-manager-vault.yaml`: AWS vault in `us-east-1`, using the data plane's AWS credential chain. Adjust the region to match the secret.
3. `20-provider-openai.yaml`: provider whose write-only Authorization field receives a vault reference, not the OpenAI credential itself.
4. `30-application-consumer.yaml`: key-auth strategy, consumer and one-hour application key.
5. `40-model-sts-chat.yaml`: logical model targeting `gpt-4o-mini`; select an approved model before use.

For the intended Bedrock path, `20-provider-bedrock.yaml` and `40-model-bedrock.yaml` provide an alternative provider and model; they reuse the `sts-key-auth` strategy from `30-application-consumer.yaml`.

**Ownership:** `00` is only for a new gateway managed by `kongctl`. Do not apply it to an existing Terraform-managed gateway or adopt that gateway without a separately reviewed ownership migration. For an existing gateway, skip `00` and use its ID for files 10–40. Use `apply`, not `sync`, for these partial examples; review each scoped diff before applying.

## Prerequisites and example commands

Authenticate `kongctl` securely and confirm the Konnect organization and region. Create the control plane and register its public certificate before deploying the data plane. The data plane's namespace, TLS Secret, IAM access, network access, and Helm deployment are described in the parent README. The secret's plain-text value must be the complete OpenAI Authorization header (`Bearer ` followed by the key); create it with an approved secure workflow and never include it in YAML, shell history, Git, or output. The sample path is `kong-ai-non-prod/openai-auth-header`, permitted by an appropriately configured Pod Identity role.

For a **new** control plane, generate a self-signed certificate only if the selected Konnect deployment and STS policy allow it. For example, from this directory, with an approved private directory outside the repository:

```bash
umask 077
CERT_DIR="/secure/path"  # Replace with an existing private directory.
openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 30 \
  -keyout "$CERT_DIR/data-plane.key" -out "$CERT_DIR/data-plane.crt" \
  -subj '/CN=ai-gateway-data-plane'
mkdir -p certs
cp "$CERT_DIR/data-plane.crt" certs/data-plane.crt
```

Use an existing approved private directory instead of the placeholder; copy **only the public certificate** to `certs/data-plane.crt` for `00`. Never copy the private key into this repository. Check the certificate's validity and its public key against the private key, and consult the Konnect wizard for supported requirements. The `certs/` directory is ignored by Git but ignoring a directory is not a substitute for key protection. A 30-day certificate requires a planned rotation; this command is an example, not a production certificate policy.

Edit the sample gateway name and namespace, then review and apply `00-ai-gateway-control-plane.yaml` with `kongctl diff --mode apply` and `kongctl apply`. Retrieve the resulting gateway ID and endpoints with `kongctl get ai-gateway <name> -o json`. Use the **same** public certificate and matching key paths for the Terraform gateway stage. Do not proceed if the plan would change an unrelated control plane or certificate.

After verifying the existing gateway and its ID, set non-secret references and a temporary application key in a protected shell:

```bash
export AI_GATEWAY_ID="<existing-gateway-id>"
export OPENAI_VAULT_REFERENCE='{vault://aws-secrets-manager/kong-ai-non-prod%2Fopenai-auth-header}'
export STS_TEST_APP_KEY="$(openssl rand -hex 24)"
```

The encoded `%2F` is part of the Secrets Manager secret name in the vault reference. Keep the temporary application key for the test; it is distinct from the OpenAI key. It expires after one hour. Avoid shell tracing and protect the process environment.

The provider and application credential contain write-only fields. A diff should show an intentional secret write without revealing the value; do not use `--write-secrets` broadly. Calls to OpenAI can incur charges. Never use production personal data.

## Apply child objects together

After the control plane exists and `AI_GATEWAY_ID`, `OPENAI_VAULT_REFERENCE`, and `STS_TEST_APP_KEY` are set as above, you can pass the four child files together. Review the complete diff, especially the target gateway, secret writes, and creation order, before applying:

```bash
kongctl diff --mode apply \
  -f 10-aws-secrets-manager-vault.yaml \
  -f 20-provider-openai.yaml \
  -f 30-application-consumer.yaml \
  -f 40-model-sts-chat.yaml

kongctl apply \
  -f 10-aws-secrets-manager-vault.yaml \
  -f 20-provider-openai.yaml \
  -f 30-application-consumer.yaml \
  -f 40-model-sts-chat.yaml
```

Run these commands from this directory. This combines the child configuration in one invocation; it does **not** create the control plane. Each child uses `!lookup` against an already existing gateway ID. Do not include `00` in this invocation or use `sync` on a partial configuration. The ordered, separate-file workflow remains the tested approach; review the combined plan and dependency order before using it on new objects. Do not use `--write-secrets` unless an intentional write-only field update has been reviewed.

## Example synthetic request

From an authorized test host, set `PROXY_URL` to the approved HTTPS endpoint. Use a trusted certificate in shared environments. The following tests send only a synthetic prompt:

```bash
export PROXY_URL="https://<approved-proxy-host>"
curl -sS "$PROXY_URL/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -d '{"model":"sts-chat","messages":[{"role":"user","content":"Say hello"}],"max_tokens":32}'
```

Expect a `401` without an application key. Repeat with `-H "apikey: $STS_TEST_APP_KEY"`; a successful response verifies that Kong accepted the key and the upstream call completed. Protect process arguments and avoid running this on a shared host where other users can inspect them. An upstream `401`, `429`, timeout or other error requires separate diagnosis and must not be reported as a successful inference. Rotate expired application credentials through an approved process; do not assume reapplying a create-only credential replaces its key.

## Bedrock validation example

The data plane must be connected and use the intended EKS Pod Identity role. Approve the actual Bedrock model or inference profile, region, model access, data residency and IAM ARNs first; set `bedrock_model_arns` and, where relevant, `inference_profile_arns` in Terraform. Cross-region profiles may also require foundation-model ARNs in destination regions. Verify account access and the AWS SDK credential chain in the selected AI Gateway runtime. The Bedrock provider uses `type: aws` without static credentials.

Create the key-auth strategy and consumer using `30-application-consumer.yaml` first, or use a separately approved existing strategy named `sts-key-auth`. From this directory set the already existing gateway ID and select an approved target; the example ID below is a lab model, **not an STS-approved choice**:

```bash
export AI_GATEWAY_ID="<existing-gateway-id>"
export AWS_REGION="us-east-1"
export BEDROCK_MODEL_ID="amazon.nova-micro-v1:0"
kongctl diff --mode apply -f 20-provider-bedrock.yaml -f 40-model-bedrock.yaml
kongctl apply -f 20-provider-bedrock.yaml -f 40-model-bedrock.yaml
```

The diff must contain only the intended provider and model. `!env` values resolve again at apply time; keep the same reviewed environment. The target is a model ID or profile ID, **not its IAM ARN**. After configuration propagates, use an approved proxy endpoint and application key to send a synthetic request:

```bash
export PROXY_URL="https://<approved-proxy-host>"
curl -sS "$PROXY_URL/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -H "apikey: $STS_TEST_APP_KEY" \
  -d '{"model":"sts-bedrock-chat","messages":[{"role":"user","content":"Say hello"}],"max_tokens":32}'
```

Remove the `apikey` header to check that an unauthenticated request returns 401. Protect process arguments on shared hosts and use a trusted TLS certificate. A successful response proves the selected Bedrock route, not fallback, streaming, or other models; calls may incur AWS charges. In one lab, this configuration returned 401 without an application key and 200 with a valid key using `amazon.nova-micro-v1:0` and Pod Identity. STS must validate its approved model and environment separately.
