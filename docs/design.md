# PTIC Design Notes

## Goals / non-goals

Provide a reviewable GitOps operating model for dev, staging and prod on a bare-metal Kubernetes homelab. Desired state is declarative and reconciled by Argo CD. This is a scaffold: no cluster provisioning, app source, real credentials or claim of tested production HA.

## Topology

One cluster with namespace isolation (`dev`, `staging`, `prod`) plus shared `networking`, `database`, `observability`, and `storage` namespaces. Shared platform services are installed once; application and database workloads are environment-scoped. A multi-cluster deployment can reuse the overlays by assigning each environment Application a distinct destination cluster.

## Key decisions

- Argo CD App-of-Apps: one root Application owns three environment Applications. CI never runs `kubectl apply` against the cluster.
- Kustomize base/overlays: shared workload definitions, environment-specific sizing and image tags.
- PostgreSQL: CloudNativePG operator. hostPath PVCs are pinned to labelled nodes. Single instance is the safe default under the given storage constraint; HA replicas require independent paths on independent nodes and do not protect against correlated node/storage failure.
- Ingress: Traefik with Gateway API; metrics and JSON access logs enabled. Cloudflared is an outbound connector Deployment; only its internal service target is exposed.
- Object storage: MinIO S3-compatible for homelab self-hosting. For stronger durability, use external S3-compatible object storage and store DB backups there.
- Observability: kube-prometheus-stack + Loki; apps expose health and metrics endpoints; stdout logs collected centrally.
- Secrets: SOPS/Age encrypted manifests or External Secrets; secret decryption key stays outside Git.

## Failure and risk model

| Risk | Mitigation / honest limitation |
|---|---|
| HostPath node loss | Node affinity, dedicated directories, off-node backups, restore drills; hostPath is not replicated |
| Tunnel connector failure | 2+ replicas, readiness/liveness probes; Cloudflare remains external dependency |
| Ingress failure | Traefik replicas >=2, PDB, metrics and access logs |
| App pod/node failure | >=2 replicas, topology spread, probes, PDB, resource requests |
| Bad Git change | PR checks, approvals, Argo CD health/sync status, revert commit |
| Secret exposure | Gitleaks, SOPS/External Secrets, rotation and least privilege |
| Object-store failure | backup outside cluster; MinIO on one homelab remains a single failure domain |

## Promotion / rollback

Build immutable app image once. Promote the same digest through environment overlays by PR. Protect prod with required checks and CODEOWNERS. Roll back with Git revert or restore previous digest; Argo CD reconciles. Do not use mutable `latest` tags.

## Security pipeline

Gitleaks, Semgrep, Checkov, Trivy config, kubeconform and dependency review are PR gates. Scan results do not prove runtime security; add image scanning, SBOM generation, signature verification and admission policy enforcement when app build pipelines are available.
