# Operations and hardening

## Service selection

Six logical services are controlled by `ENABLE_POSTGRES`, `ENABLE_REDIS`, `ENABLE_NEO4J`, `ENABLE_MINIO`, `ENABLE_ELASTICMQ`, and `ENABLE_COGNITO` in the persistent runtime environment. All default to `true`.

Changing a value from `true` to `false` causes deployment to remove that logical service's containers while preserving named volumes. Re-enabling later reuses the data. The dashboard and UI gateway remain running.

## Network boundary

Canonical hostname: `aws.home.arpa`.

- Dashboard: `https://aws.home.arpa`
- pgAdmin: `https://aws.home.arpa:5050`
- RedisInsight: `https://aws.home.arpa:5540`
- Neo4j Browser: `https://aws.home.arpa:7474`
- MinIO Console: `https://aws.home.arpa:9001`
- ElasticMQ UI: `https://aws.home.arpa:9325`
- Cognito Local API: `http://aws.home.arpa:9229`

Host Caddy publishes the dashboard from `127.0.0.1:8003`. The Compose UI gateway provides the service-specific HTTPS ports.

## Verification

`./scripts/verify.sh` verifies both sides of the configuration:

- enabled service: exactly one running container plus protocol/API readiness
- disabled service: application/admin containers must be absent
- dashboard runtime metadata must match `runtime.env`
- Cognito Local must answer `ListUserPools` and contain the expected token issuer

## Storage safety and rollback

Deployment rollback restores the previous successful source/config snapshot and previous runtime environment. Docker data volumes are never deleted during deployment or rollback.

A service being disabled is not data deletion. Only the interactive `reset-all-data.sh` removes volumes.

## Backup commands

```bash
./scripts/backup-postgres.sh
./scripts/test-postgres-restore.sh
./scripts/backup-redis.sh
./scripts/backup-minio.sh
./scripts/backup-neo4j.sh
```

A backup command exits cleanly when its logical service is disabled. Neo4j Community backup briefly stops Neo4j while taking a volume snapshot.

Backups on the same SSD do not protect against physical disk failure.

## Runtime credentials

For backward compatibility, enabled-service `change_me_*` credentials currently produce deployment warnings rather than a hard failure. Replace them in `$HOME/.config/db.local/runtime.env` for serious use.

PostgreSQL and Neo4j credentials can be initialized into persistent volumes; changing only the environment later may not modify existing database credentials.
