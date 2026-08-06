# Cluster bootstrap — commands already run

One-time, imperative setup that isn't GitOps-managed (registry org, robot
account, secrets). Captured here so it's reviewable and reproducible —
**no live secret values are stored in this file or anywhere in this repo.**

## 1. Namespace

```
oc apply -f cluster-setup/namespaces.yaml
```
Creates `app-dev`. The OpenShift Pipelines operator auto-provisions a
`pipeline` ServiceAccount (bound to the `pipelines-scc` restricted SCC) once
the namespace exists — no extra RBAC needed for Tekton to run non-root.

## 2. Quay Enterprise — org, repo, robot account

Registry: `quay-8rnsl.apps.cluster-8rnsl.8rnsl.sandbox2169.opentlc.com`
(in-cluster Quay Enterprise, Clair scanning enabled per-repo by default).

- Org: `nginx-demo`
- Repo (private): `nginx-app-dev`
- Robot account: `nginx-demo+dev_pusher` — write on `nginx-app-dev` only.
  Used by the pipeline's `pipeline` ServiceAccount to build, push, and pull.

Created via the Quay API (`/api/v1/organization/`, `/api/v1/repository`,
`/api/v1/organization/nginx-demo/robots/dev_pusher`,
`/api/v1/repository/nginx-demo/nginx-app-dev/permissions/user/dev_pusher`)
using the sandbox's `quayadmin` superuser token.

## 3. Kubernetes Secrets (created directly in-cluster, not in Git)

| Secret | Namespace | Type | Contents | Used by |
|---|---|---|---|---|
| `quay-dev-pusher` | `app-dev` | `dockerconfigjson` | `dev_pusher` robot creds | pipeline build/push (explicit workspace) and Deployment `imagePullSecrets` |
| `git-credentials` | `app-dev` | Opaque (`.git-credentials` + `.gitconfig`) | GitHub PAT (classic, `repo` scope) | `git-cli` ClusterTask `basic-auth` workspace, write-back commit |

```
oc secrets link pipeline quay-dev-pusher -n app-dev --for=pull
```
Links the secret to the `pipeline` ServiceAccount's `imagePullSecrets` (for
the deployed Pod to pull). The build step itself gets credentials via an
explicit `dockerconfig` workspace binding in the PipelineRun, not SA
injection - simpler and avoids the host-keyed credential collision that
comes up once you have more than one secret for the same registry host.

## 4. Production-hardening notes (not done for the demo, called out deliberately)

- Vault + External Secrets Operator are already running on this cluster
  (`vault-secret-store` ClusterSecretStore is `Ready`). The next step past
  demo-stage is moving these two secrets into Vault and replacing each with
  an `ExternalSecret` - not done here only for time, not because it's hard.
- The GitHub PAT in `git-credentials` belongs to a personal account; a
  production setup would use a GitHub App or deploy key scoped to this repo
  only.
- Multi-environment promotion (dev -> stage -> prod), per-environment
  registries, and an OCI-published Helm chart were built and validated in
  an earlier iteration of this demo and deliberately dropped to keep the
  live walkthrough to one clear loop. See git history if that design is
  needed again.
