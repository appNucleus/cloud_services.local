# cloud_services.local

Local AWS-compatible data/authentication platform for LangGraph, FastAPI, and LLM application development. The stack is deployed with Docker Compose, a persistent runtime environment, GitHub Actions, health/smoke validation, and automatic source/config rollback.

Canonical LAN hostname:

```text
aws.home.arpa
```

## Logical services

Six logical services can be enabled or disabled independently from the persistent runtime environment:

| Logical service | Containers | Local AWS target |
|---|---|---|
| PostgreSQL + pgvector | `db-postgres`, `db-pgadmin` | Aurora / RDS PostgreSQL |
| Redis | `db-redis`, `db-redisinsight` | ElastiCache |
| Neo4j | `db-neo4j` | Neptune / Neo4j Aura |
| MinIO | `db-minio`, temporary `db-minio-init` | S3 |
| ElasticMQ | `db-elasticmq`, `db-elasticmq-ui` | SQS |
| Cognito Local | `db-cognito` | Cognito User Pools |

Platform infrastructure is always enabled:

- `db-ui-gateway` — Caddy HTTPS gateway for browser/admin UIs.
- `db-dashboard` — Nginx static dashboard served locally on `127.0.0.1:8003` and normally published through host Caddy.

## Service switches

All six logical services are enabled by default:

```env
ENABLE_POSTGRES=true
ENABLE_REDIS=true
ENABLE_NEO4J=true
ENABLE_MINIO=true
ENABLE_ELASTICMQ=true
ENABLE_COGNITO=true
```

Values must be exactly `true` or `false`. Invalid values fail deployment.

Disabling a logical service removes its application/admin containers but **does not remove named Docker volumes**. Re-enabling the service later reuses the same persistent data. The dashboard continues to show every service and marks disabled services as `DISABLED`; their admin links are non-clickable.

Docker Compose profiles are derived automatically from these six variables. Users should configure the `ENABLE_*` variables rather than setting `COMPOSE_PROFILES` manually.

## Runtime environment

Production-style deployment uses:

```text
$HOME/.config/db.local/runtime.env
```

The workflow creates this file from `.env.example` on first deployment and then preserves server-specific values. New keys are added automatically without replacing existing values, except deployment-critical values intentionally forced by the release workflow.

The canonical hostname is forced to:

```env
PLATFORM_HOSTNAME=aws.home.arpa
```

## Endpoints

With all logical services enabled:

| Service | Endpoint |
|---|---|
| Dashboard | `https://aws.home.arpa` |
| PostgreSQL | `aws.home.arpa:5432` |
| pgAdmin | `https://aws.home.arpa:5050` |
| Redis | `redis://aws.home.arpa:6379/0` |
| RedisInsight | `https://aws.home.arpa:5540` |
| Neo4j Browser | `https://aws.home.arpa:7474` |
| Neo4j Bolt | `bolt://aws.home.arpa:7687` |
| MinIO S3 API | `http://aws.home.arpa:9000` |
| MinIO Console | `https://aws.home.arpa:9001` |
| ElasticMQ SQS API | `http://aws.home.arpa:9324` |
| ElasticMQ UI | `https://aws.home.arpa:9325` |
| Cognito Local User Pools API | `https://aws.home.arpa:9229` |

Containers on `db-local-net` should use Compose service names (`postgres`, `redis`, `neo4j`, `minio`, `elasticmq`, `cognito`) rather than hairpinning through the host.

## Dashboard hostname and host Caddy

The dashboard container remains host-local:

```env
DASHBOARD_HOST_BIND=127.0.0.1
DASHBOARD_PORT=8003
```

The system-level Caddy installation on the server should contain:

```caddyfile
aws.home.arpa {
    tls internal
    reverse_proxy 127.0.0.1:8003
}
```

This host Caddy configuration is outside the repository and must be kept consistent with `PLATFORM_HOSTNAME`. LAN DNS must resolve `aws.home.arpa` to the server.

The Compose `db-ui-gateway` independently publishes the browser/admin UIs with Caddy `tls internal` on ports `5050`, `5540`, `7474`, `9001`, and `9325` under the same `aws.home.arpa` hostname.

## Cognito Local

The stack uses the pinned image:

```text
jagregory/cognito-local:5.3.0
```

Cognito Local is a development emulator for **Amazon Cognito User Pools**, not a complete Cognito/Identity Pools implementation. The Compose UI gateway provides a small browser landing/User Pools page at `https://aws.home.arpa:9229/` and proxies Cognito API requests on the same HTTPS origin.

Persistent state is stored in:

```text
db-cognito-data
```

Deployment generates Cognito Local configuration and synchronizes it into the preserved external named volume before startup; Cognito can then update its own writable config while user-pool data remains persistent. The configured token issuer is:

```text
https://aws.home.arpa:9229
```

The smoke test calls the User Pools `ListUserPools` API rather than relying only on an open TCP port.

## Deployment model

Release workflow:

```text
.github/workflows/deploy-release.yml
```

Trigger:

```text
push to release
```

Runner labels:

```text
self-hosted, Linux, X64, dbs-prod
```

Deployment sequence:

```text
checkout release commit
validate shell/server prerequisites
create/preserve runtime.env
migrate new runtime keys
validate booleans/hostname/credentials
derive enabled Compose profiles
generate dashboard state + service config files
validate Compose configuration
preflight only enabled service images
prepare rollback point
remove newly-disabled containers (volumes preserved)
start enabled services
run MinIO init only when MinIO is enabled
run enabled/disabled smoke verification
replace successful-deployment snapshot
rollback source/config on failure
```

Rollback restores the previous source tree and previous `runtime.env`. It never deletes Docker data volumes.

## Dashboard state generation

`scripts/generate-dashboard-state.sh` regenerates the non-secret `www/runtime-config.js` file from `runtime.env`. Nginx continues to mount the stable tracked `www/` directory read-only, matching the pre-feature dashboard deployment model while still reflecting enabled/disabled service state.

The generated state contains only:

- `PLATFORM_HOSTNAME`
- six enabled/disabled booleans
- service port numbers

Credentials are never exposed to the browser.

## Manual deployment

```bash
cp .env.example .env
nano .env
chmod +x scripts/*.sh
./scripts/start.sh --wait
./scripts/status.sh
./scripts/verify.sh
```

Or use the deployment wrapper:

```bash
DEPLOY_ENV_FILE="$HOME/.config/db.local/runtime.env" ./scripts/deploy-local.sh
```

Stop all stack containers while preserving data:

```bash
./scripts/stop.sh
```

A full destructive reset requires interactive confirmation:

```bash
./scripts/reset-all-data.sh
```

That command removes volumes for enabled **and disabled** services and must never be used by the deployment workflow.

## Backups

Deployment snapshots are source/config metadata used for rollback. They are not database backups.

Data backup commands:

```bash
./scripts/backup-postgres.sh
./scripts/test-postgres-restore.sh
./scripts/backup-redis.sh
./scripts/backup-neo4j.sh
./scripts/backup-minio.sh
```

A service-specific backup command exits cleanly when that logical service is disabled.

Backups stored only on the same physical disk do not protect against disk failure.

## Application connection examples

Same host:

```env
DATABASE_URL=postgresql+asyncpg://langgraph_user:change_me_postgres_2026@127.0.0.1:5432/langgraph_app
REDIS_URL=redis://:change_me_redis_2026@127.0.0.1:6379/0
NEO4J_URI=bolt://127.0.0.1:7687
S3_ENDPOINT_URL=http://127.0.0.1:9000
SQS_ENDPOINT_URL=http://127.0.0.1:9324
COGNITO_ENDPOINT_URL=https://aws.home.arpa:9229
```

LAN:

```env
DATABASE_URL=postgresql+asyncpg://langgraph_user:change_me_postgres_2026@aws.home.arpa:5432/langgraph_app
REDIS_URL=redis://:change_me_redis_2026@aws.home.arpa:6379/0
NEO4J_URI=bolt://aws.home.arpa:7687
S3_ENDPOINT_URL=http://aws.home.arpa:9000
SQS_ENDPOINT_URL=http://aws.home.arpa:9324
COGNITO_ENDPOINT_URL=https://aws.home.arpa:9229
```

## Security and resource model

Raw service APIs are LAN-bound through `DB_HOST_BIND` and should not be router-port-forwarded to the internet. Browser/admin UIs are served through the Compose HTTPS gateway. The main dashboard stays on loopback and is published by host Caddy.

Containers use `no-new-privileges`, PID limits, CPU/memory ceilings, and Docker log rotation. Resource limits are ceilings, not reservations. See `.env.example`, `docs/LAN_ACCESS.md`, and `docs/RESOURCE_PLANNING.md`.
