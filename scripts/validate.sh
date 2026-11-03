#!/usr/bin/env bash
set -euo pipefail
for env in dev staging prod; do
  echo "==> Building ${env}"
  kustomize build "environments/${env}" > "/tmp/ptic-${env}.yaml"
  if command -v kubeconform >/dev/null 2>&1; then
    kubeconform -strict -ignore-missing-schemas -summary "/tmp/ptic-${env}.yaml"
  else
    echo "kubeconform not installed; skipped schema validation"
  fi
done
echo "All Kustomize builds completed."
