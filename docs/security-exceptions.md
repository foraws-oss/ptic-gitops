# Security Exceptions and Remediation Plan

## Context

The GitOps repository contains frontend and backend Deployment templates.
The actual application source code and production container images are not
part of this assignment.

Checkov is enabled for Kubernetes manifests. Findings are retained and
reported; they are not silently skipped.

## Current Findings

The following findings are present in dev, staging and prod.

| Checkov ID | Workload | Reason | Required remediation |
|---|---|---|---|
| CKV_K8S_40 | Frontend and Backend | The actual container images and their supported runtime UID are not available. | Confirm image compatibility and configure a high non-root UID. |
| CKV_K8S_35 | Backend | Database credentials are currently injected through Secret-backed environment variables. | Update the application to read credentials from mounted Secret files, then remove environment-variable references. |
| CKV_K8S_43 | Frontend and Backend | Final immutable image digests are not available because application images are outside this repository. | Build, scan and publish images, then pin each Deployment image using its verified SHA256 digest. |

## Risk and Mitigation

- Workloads already set `runAsNonRoot: true`.
- Workloads disable privilege escalation.
- Workloads use read-only root filesystems.
- Workloads drop Linux capabilities.
- Service account token automount is disabled.
- Database credentials are sourced from Kubernetes Secret references,
  not hardcoded values in Git.
- Container images must be pinned by digest before production release.

These mitigations reduce risk but do not make the three findings resolved.

## CI Policy

Checkov runs on the repository and reports findings. Its current CI step uses
soft-fail mode temporarily so that known application-image dependencies do
not prevent the assignment validation workflow from completing.

Trivy HIGH/CRITICAL findings, Gitleaks findings, Semgrep failures and
manifest validation remain blocking checks according to their workflow
configuration.

Soft-fail mode is temporary. It must be removed before production promotion
or replaced with a narrowly scoped, reviewed exception policy.

## Production Exit Criteria

Before production promotion:

1. Confirm the frontend and backend images support a high non-root UID.
2. Configure and verify `runAsUser` for both workloads.
3. Change backend database credential handling to mounted Secret files.
4. Publish immutable application images and pin their SHA256 digests.
5. Re-run Checkov and resolve these findings.
6. Set Checkov `soft_fail: false`.
7. Verify all security and manifest-validation workflows pass.
