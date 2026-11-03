# Object storage

The repository deploys a single-replica MinIO StatefulSet and ClusterIP Service as an S3-compatible homelab endpoint (`minio.storage.svc:9000`). A static 20Gi hostPath PV is declared in `platform/storage/hostpath-storage.yaml`, pinned to a node labelled `ptic.storage/minio=true`. Create the `minio-root` Secret in namespace `storage` out-of-band.

This is intentionally a lab profile, not HA: MinIO data shares the cluster/node failure domain. Keep off-cluster backups. For production-grade durability, replace it with managed S3-compatible cloud storage and inject credentials through SOPS/External Secrets.
