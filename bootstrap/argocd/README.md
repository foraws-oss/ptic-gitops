# Argo CD bootstrap

1. Install Argo CD using the official upstream installation instructions for your cluster.
2. Configure repository credentials using a Kubernetes Secret or Argo CD repository credential template (never commit credentials).
3. Replace the repository URL in `root-app.yaml` with your Git URL.
4. Apply: `kubectl apply -n argocd -f bootstrap/argocd/root-app.yaml`.
5. Argo CD creates the three environment Applications from `bootstrap/argocd/apps/`.

The root Application uses automated sync, prune and self-heal. For a regulated production environment, consider manual sync/approval for prod and a dedicated Argo CD project with restricted destinations and source repos.
