# Operations and hardening

## Network boundary

Browser/admin UIs bind only to 127.0.0.1 and are published through host Caddy using `tls internal`. Raw application protocols remain LAN-accessible where required.

HTTPS UIs:
- `https://dbs.home.arpa` — dashboard
- `https://pgadmin.dbs.home.arpa`
- `https://redis.dbs.home.arpa`
- `https://neo4j.dbs.home.arpa`
- `https://minio.dbs.home.arpa`
- `https://sqs.dbs.home.arpa`

The certificates are issued by Caddy's private CA. Installing the CA on clients is optional; without it, browsers show the expected certificate warning.

## Storage safety

Deployment requires at least 5 GiB free disk and warns below 10 GiB. Docker JSON logs are rotated at 10 MiB x 3 files per container by default. Database Docker volumes are never removed during deployment or rollback.

Deployment rollback snapshots retain exactly one successful deployment. Data backups use count-based retention:
- PostgreSQL: newest 7 by default
- Redis: newest 3
- MinIO: newest 3
- Neo4j: newest 3

These values are configurable in the runtime environment.

## Backup commands

```bash
./scripts/backup-postgres.sh
./scripts/test-postgres-restore.sh
./scripts/backup-redis.sh
./scripts/backup-minio.sh
./scripts/backup-neo4j.sh
```

Neo4j Community backup briefly stops Neo4j and creates a compressed snapshot of its data volume, then restarts and waits for health.

Backups stored only on the same SSD protect against accidental data changes but not physical disk failure. Copy important backups to another device or host for disaster recovery.

## Runtime secrets

Deployments refuse documented placeholder passwords. Before merging this hardening into `release`, update `$HOME/.config/db.local/runtime.env` with non-placeholder values.

The generated pgAdmin server definition intentionally does not store the PostgreSQL password. Enter/save it in pgAdmin's own protected state when needed.

## Version policy

Runtime images are pinned to explicit supported/stable versions rather than `:latest`. Update them deliberately in a reviewed PR. Redis uses the 7.4 extended-support line and Neo4j uses 5.26 LTS.

## Resource policy

The defaults are conservative guardrails for a 16 GiB local-development host. They can be increased later in `runtime.env`. Redis additionally has a 512 MiB data ceiling with `allkeys-lru`, appropriate for its cache/ephemeral-state role.
