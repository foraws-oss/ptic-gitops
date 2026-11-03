# PTIC GitOps Homelab

A GitOps-first Kubernetes reference repository for a bare-metal homelab with **Argo CD**, Kustomize, three logical environments, Cloudflare Tunnel-only ingress, hostPath-backed PostgreSQL, observability, object storage, and a DevSecOps validation pipeline.

> **Scope:** scaffold and operating model, not a production-ready cluster installation. Replace example images, domains, storage paths, and credentials before use. No real application source code or secrets are included.

## Architecture at a glance

```text
Developer PR / merge
       |
       v
GitHub Actions: Gitleaks -> Semgrep -> Checkov -> Trivy config -> kubeconform
       |
       v
Git main (desired state) <------------------------------+
       |                                                 |
       v                                                 |
Argo CD (App-of-Apps; automated sync + self-heal)        |
       |                                                 |
       +--> platform: Traefik Gateway / CNPG / MinIO / monitoring
       +--> dev namespace       +--> staging namespace  +--> prod namespace
                    |                    |                     |
               API + UI             API + UI              API + UI
                    |                    |                     |
                    +--------------------+---------------------+
                                         |
                           Cloudflare Tunnel connector(s)
                                         |
                                  Cloudflare Edge
                                         |
                                      Internet
```

All environments are logical namespaces on the same homelab cluster in this starter. For stronger isolation, use separate clusters and one Argo CD Application per cluster while retaining the same overlays. The single-cluster layout is explicit so the manifests can be reviewed and built without inventing cluster infrastructure.

## Repository layout

```text
bootstrap/argocd/                 Argo CD root Application and install notes
platform/                          Shared platform components
  cloudnative-pg/                   CNPG Cluster resources (operator installed by Argo CD)
  traefik/                          Gateway API objects and Traefik Helm Application
  cloudflared/                      Tunnel Deployment + ConfigMap (token from Secret)
  observability/                    kube-prometheus-stack + Loki Helm Applications
  object-storage/                   MinIO Tenant placeholder / S3 endpoint contract
  policies/                         Pod security and network policy examples
apps/{backend,frontend}/base/       reusable Deployments and Services
apps/{backend,frontend}/overlays/   dev, staging, prod settings
apps/postgres/overlays/             per-environment CNPG cluster sizing/storage
apps/kustomization.yaml             shared app composition
 environments/{dev,staging,prod}/   environment entrypoints
.github/workflows/                  CI validation and security scanning
scripts/                            local validation helpers
```

## Bootstrap assumptions

- A Kubernetes cluster already exists; nodes are labelled and have a dedicated local directory for database data.
- Argo CD is installed once using the official installation procedure, then `bootstrap/argocd/root-app.yaml` is applied. The root Application manages the environment Applications.
- Gateway API CRDs must be installed before the Traefik Gateway resources. The Traefik Helm release is configured with Gateway API support.
- CloudNativePG operator, MinIO Operator (if using the Tenant CR), Prometheus Operator CRDs and Loki are installed/managed by the declared Argo CD Helm Applications.
- Cloudflare Tunnel is already created in Cloudflare. Store its token as a Kubernetes Secret named `cloudflared-token` in namespace `networking`; do not commit it.
- Label storage nodes (`ptic.storage/dev=true`, `ptic.storage/staging=true`, `ptic.storage/prod=true`) and create `/var/lib/ptic/postgres/{dev,staging,prod}` on the matching nodes. Static PVs are declared in `platform/storage/hostpath-storage.yaml`. HostPath is node-local and is not replicated storage.
- Replace `ghcr.io/your-org/ptic-{backend,frontend}:0.1.0` with images built and published by your application CI. This assignment intentionally contains no application code.
- Change example hostnames under `*.example.com` to domains routed through the Cloudflare Tunnel.

## Environments and promotion

Each environment has its own Kustomize entrypoint and namespace. Differences are limited to replicas, resource requests/limits, hostnames, and database sizing. Promote by opening a PR that copies the tested image tag and approved configuration from `dev` to `staging`, then from `staging` to `prod`. Require CI and reviewer approval; production overlay changes should be protected by CODEOWNERS/branch protection. Do not let CI directly mutate the cluster: CI validates and builds artifacts; Argo CD pulls desired state from Git.

Suggested release flow:
1. Merge app source PR; application CI builds an immutable image tag and publishes an SBOM/provenance.
2. Update the dev overlay image tag via PR.
3. Validate in dev; promote the same digest/tag to staging via PR.
4. After approval, promote the exact same digest to prod via PR. No rebuild between environments.
5. Roll back by reverting the Git commit/PR or pinning the previous known-good image digest; Argo CD reconciles the revert.

## Secrets

- No raw secrets belong in Git. `.gitignore` excludes local secret material.
- Use SOPS with Age for encrypted Secret manifests. Commit only `*.enc.yaml`; keep the Age private key in an external secret store / secured operator environment, never in Git.
- Argo CD decryption can be provided by a CMP plugin or a SOPS integration installed in the Argo CD repo-server. This repository documents the boundary but does not embed a private key or assume a particular plugin image.
- For Cloudflare, create `cloudflared-token` out-of-band or use External Secrets Operator with a supported secret manager. `cloudflared` Deployment references the Secret by name only.
- Database credentials are generated by CloudNativePG and exposed through Kubernetes Secrets; avoid committing generated values.

## Storage and PostgreSQL design

CloudNativePG manages PostgreSQL lifecycle, readiness, rolling updates, backup hooks and primary/replica roles. The sample uses one instance per environment to keep the hostPath constraint honest. A production HA PostgreSQL cluster needs at least three instances on **independent durable storage**; hostPath on one node cannot provide storage HA. If multiple instances are enabled, use node affinity/anti-affinity and separate pre-created paths per node, plus tested off-node backups. A node loss can make hostPath data unavailable. Treat backup/restore to S3-compatible storage as mandatory, and document RPO/RTO after testing. Never claim hostPath alone is HA.

MinIO is included as an in-cluster S3-compatible option for homelab independence. It is suitable for a lab/demo, but its own data also needs durable disks, distributed deployment across failure domains, and off-cluster backup. For a real production requirement, prefer managed S3-compatible cloud storage if internet egress and cost are acceptable. A single-replica MinIO StatefulSet is included for the lab; provision a matching static hostPath PV for its 20Gi PVC and keep off-cluster backups. It is not HA.

## Ingress and Cloudflare Tunnel model

Traefik is the in-cluster Gateway implementation. Gateway API `Gateway`/`HTTPRoute` objects route HTTP traffic to Services. Traefik exposes Prometheus metrics and JSON access logs. The Cloudflare Tunnel connector runs as a Deployment in `networking`; it makes outbound-only connections to Cloudflare and forwards configured hostnames to the internal Traefik Gateway Service. No NodePort, public LoadBalancer, router port-forward, or inbound firewall rule is required. Use at least two cloudflared replicas for connector availability. Cloudflare edge/Tunnel availability remains an external dependency.

## Observability paths

- Prometheus scrapes Kubernetes, Traefik metrics and app `/metrics` endpoints (annotated Services / ServiceMonitors where available).
- Grafana is the dashboard UI; provision dashboards and alert rules through Git in a follow-up iteration.
- Loki receives container logs via a log collector (e.g. Promtail/Alloy); Traefik access logs are emitted as JSON to stdout for collection.
- App health endpoints: `/health/live` and `/health/ready`; Kubernetes probes use these paths.
- Alert on pod restarts, unavailable replicas, API error rate/latency, PostgreSQL availability, disk pressure, backup age, and tunnel connector health.

## DevSecOps pipeline

GitHub Actions runs on PRs and pushes:
- **Gitleaks**: secret scanning.
- **Semgrep**: SAST for supported source/config files (no app source in this repo, still validates repository content).
- **Checkov**: Kubernetes/IaC misconfiguration checks.
- **Trivy config**: Kubernetes/YAML misconfiguration and vulnerability/misconfiguration scanning.
- **kubeconform + Kustomize**: schema validation/build for all overlays.
- **Dependency review**: dependency change review on PRs.

CI is a gate, not a deployer. Argo CD is the only reconciler. Pin GitHub Actions to full commit SHAs before production use; version tags are used here for readability in a take-home scaffold.

## Prepare hostPath nodes (operator action)

```bash
kubectl label node <node-dev> ptic.storage/dev=true
kubectl label node <node-staging> ptic.storage/staging=true
kubectl label node <node-prod> ptic.storage/prod=true
kubectl label node <node-minio> ptic.storage/minio=true
sudo install -d -m 0700 /var/lib/ptic/postgres/dev
sudo install -d -m 0700 /var/lib/ptic/postgres/staging
sudo install -d -m 0700 /var/lib/ptic/postgres/prod
sudo install -d -m 0700 /var/lib/ptic/minio
```

MinIO also needs a separate static 20Gi PV on a labelled node/path (or switch to external S3). Create `minio-root` and `cloudflared-token` Secrets out-of-band before syncing workloads.

## Validate locally

Requirements: `kubectl`, `kustomize`, `kubeconform`, `helm` (optional for chart rendering), and Docker (optional).

```bash
# Build all environment manifests
./scripts/validate.sh

# Or build individually
kustomize build environments/dev
kustomize build environments/staging
kustomize build environments/prod

# Validate the rendered manifests (requires kubeconform)
kustomize build environments/dev | kubeconform -strict -ignore-missing-schemas
```

Note: some CRDs (CNPG, Gateway API, Prometheus Operator, MinIO) require their CRD schemas to be installed or skipped by kubeconform. The script uses `-ignore-missing-schemas` for this reason. `kustomize build` validates composition, not runtime readiness.

## Security / operational checklist before real deployment

- [ ] Replace example domains and image references.
- [ ] Install Gateway API CRDs and verify Traefik GatewayClass name.
- [ ] Create `cloudflared-token` Secret in `networking` securely.
- [ ] Create hostPath directories and enforce node labels/taints/permissions.
- [ ] Decide CNPG backup destination and test restore from off-node backup.
- [ ] Deploy MinIO operator/tenant or configure external S3.
- [ ] Configure TLS origin policy, Cloudflare Access/WAF and DNS routes.
- [ ] Configure NetworkPolicies, Pod Security Admission, RBAC and resource quotas.
- [ ] Configure SOPS decryption in Argo CD and test secret rotation.
- [ ] Pin GitHub Actions to immutable SHAs and protect `main`/production paths.
- [ ] Run failure drills: node loss, DB restore, tunnel restart, Argo CD rollback.

## Spend note

**Estimated effort: 5 hours** (design 1.0h, repo/manifests 2.5h, CI/security 1.0h, validation/docs 0.5h). Adjust this note to actual time spent before submission.
