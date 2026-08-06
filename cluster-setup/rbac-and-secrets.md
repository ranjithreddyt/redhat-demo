# Cluster bootstrap — commands already run

One-time, imperative setup that isn't GitOps-managed (registry orgs, robot
accounts, secrets). Captured here so it's reviewable and reproducible —
**no live secret values are stored in this file or anywhere in this repo.**

## 1. Namespaces

```
oc apply -f cluster-setup/namespaces.yaml
```
Creates `app-dev`, `app-stage`, `app-prod`. The OpenShift Pipelines operator
auto-provisions a `pipeline` ServiceAccount (bound to the `pipelines-scc`
restricted SCC) in any namespace once it exists — no extra RBAC needed for
Tekton to run non-root.

## 2. Quay Enterprise — org, repos, scoped robot accounts

Registry: `quay-8rnsl.apps.cluster-8rnsl.8rnsl.sandbox2169.opentlc.com`
(in-cluster Quay Enterprise, Clair scanning enabled per-repo by default).

- Org: `nginx-demo`
- Repos (one per environment, private): `nginx-app-dev`, `nginx-app-stage`, `nginx-app-prod`
- Chart repo (one, shared across all environments): `nginx-app` — holds the
  Helm chart as a versioned OCI artifact (`oci://quay-host/nginx-demo/nginx-app:0.1.0`).
  Same chart version, unchanged, referenced by every environment's ArgoCD
  `Application` — only the values file layered on top differs per env.
- Robot accounts, least-privilege:
  - `nginx-demo+dev_pusher` — **write** on `nginx-app-dev` only. Used by the
    build pipeline's `pipeline` ServiceAccount in `app-dev`.
  - `nginx-demo+promoter` — **read** on `nginx-app-dev`, **write** on
    `nginx-app-stage` and `nginx-app-prod`. Used by the promotion pipeline.
    Cannot push to dev — a leaked promoter credential can't poison the build.
  - `nginx-demo+chart_publisher` — **write** on `nginx-app` (the chart repo)
    only. Used by the chart-publish pipeline, and also by ArgoCD to pull the
    chart (write implies read; kept as one robot since there's only one
    chart repo and one version to protect).

Created via the Quay API (`/api/v1/organization/`, `/api/v1/repository`,
`/api/v1/organization/nginx-demo/robots/<name>`,
`/api/v1/repository/nginx-demo/<repo>/permissions/user/<robot>`) using the
sandbox's `quayadmin` superuser token.

## 3. Kubernetes Secrets (created directly in-cluster, not in Git)

| Secret | Namespace | Type | Contents | Used by |
|---|---|---|---|---|
| `quay-dev-pusher` | `app-dev` | `dockerconfigjson` | `dev_pusher` robot creds | build pipeline push; linked as `imagePullSecret` on `pipeline` SA |
| `quay-promoter-push` | `app-dev` | `dockerconfigjson` | `promoter` robot creds | promotion pipeline push/pull; linked on `pipeline` SA |
| `quay-promoter-pull` | `app-stage` | `dockerconfigjson` | `promoter` robot creds (read-only use) | Deployment `imagePullSecrets` in stage |
| `quay-promoter-pull` | `app-prod` | `dockerconfigjson` | `promoter` robot creds (read-only use) | Deployment `imagePullSecrets` in prod |
| `git-credentials` | `app-dev` | Opaque (`.git-credentials` + `.gitconfig`) | GitHub PAT for write-back commits | `git-cli` ClusterTask `basic-auth` workspace, in both pipelines |
| `quay-chart-publisher` | `app-dev` | Opaque (`username` + `password`) | `chart_publisher` robot creds | chart-publish pipeline's `helm registry login` |
| `quay-nginx-chart-repo` | `janus-argocd` | Opaque, labeled `argocd.argoproj.io/secret-type: repository` | `chart_publisher` robot creds, OCI repo URL | ArgoCD's Helm OCI chart pull for all 3 `Application` sources |
| `redhat-demo-git-repo` | `janus-argocd` | Opaque, labeled `argocd.argoproj.io/secret-type: repository` | GitHub PAT | ArgoCD's git clone of the private `redhat-demo` repo (the `ref: values` source in each multi-source `Application`) |

**Annotation required for Tekton auto-injection:** `quay-dev-pusher` and
`quay-promoter-push` are annotated `tekton.dev/docker-0: <quay-host>` so
Tekton's credential-initializer mounts them into `~/.docker/config.json`
automatically for any step running as the `pipeline` ServiceAccount — this is
what lets `skopeo-copy` authenticate without an explicit workspace param.

```
oc secrets link pipeline quay-dev-pusher quay-promoter-push -n app-dev --for=pull
oc annotate secret quay-dev-pusher quay-promoter-push -n app-dev \
  tekton.dev/docker-0=quay-8rnsl.apps.cluster-8rnsl.8rnsl.sandbox2169.opentlc.com
```

## 4. Production-hardening notes 

- Vault + External Secrets Operator are already running on this cluster
  (`vault-secret-store` ClusterSecretStore is `Ready`). The next step past
  demo-stage is moving these five secrets into Vault and replacing each with
  an `ExternalSecret`, so nothing sensitive is a static Kubernetes Secret at
  rest — not done here only for time, not because it's hard.
- The GitHub PAT in `git-credentials` belongs to a personal account; a
  production setup would use a GitHub App or deploy key scoped to this repo
  only.
- `nginx-demo+promoter` currently has write on two repos — for stricter
  separation of duties, split into `stage_promoter` and `prod_promoter` robots
  so a compromised stage credential still can't reach prod.
