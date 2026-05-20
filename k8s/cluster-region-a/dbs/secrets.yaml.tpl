apiVersion: v1
kind: Secret
metadata:
  name: minio-credentials
  namespace: db-ops
type: Opaque
stringData:
  MINIO_ENDPOINT: "${MINIO_ENDPOINT}"
  MINIO_ACCESS_KEY: "${MINIO_ACCESS_KEY}"
  MINIO_SECRET_KEY: "${MINIO_SECRET_KEY}"
  MINIO_BUCKET_MARIADB: "${MINIO_BUCKET_MARIADB}"
  MINIO_BUCKET_MONGODB: "${MINIO_BUCKET_MONGODB}"
---
apiVersion: v1
kind: Secret
metadata:
  name: mariadb-replication-user
  namespace: db-ops
type: Opaque
stringData:
  REPLICATION_USER: "${MARIADB_REPLICATION_USER}"
  REPLICATION_PASSWORD: "${MARIADB_REPLICATION_PASSWORD}"
