# Security policy and pipeline notes

- Never commit plaintext credentials, private keys, kubeconfigs, tunnel tokens or generated database passwords.
- Use SOPS + Age or External Secrets. The `.sops.yaml` recipient is a placeholder and must be replaced.
- CI runs Gitleaks, Semgrep, Checkov, Trivy config, kubeconform and dependency review.
- Before production: pin every GitHub Action to a verified full commit SHA; add image build scanning (Trivy), SBOM (Syft), signing (Cosign), signature verification/admission policy, and protected environments.
- Kubernetes hardening baseline: non-root containers, seccomp RuntimeDefault, dropped Linux capabilities, read-only root filesystem, restricted namespace Pod Security labels, resource requests/limits, probes and PDBs.
- NetworkPolicies are examples only; validate CNI enforcement and add explicit egress policies for DNS, database, observability and tunnel paths.
