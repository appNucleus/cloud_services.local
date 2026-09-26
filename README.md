# db.local

Local Docker database/storage/messaging stack for a LangGraph/FastAPI/LLM app, with GitHub Actions deployment and automatic rollback support.

This repo provides the local DB/storage layer for the home server.

## Included

Long-running containers in this stack:

1. `db-postgres` - PostgreSQL 17 + pgvector
2. `db-pgadmin` - pgAdmin PostgreSQL admin UI
3. `db-redis` - Redis
4. `db-redisinsight` - RedisInsight Redis admin UI
5. `db-neo4j` - Neo4j Community + Neo4j Browser
6. `db-minio` - MinIO S3-compatible object storage + console
7. `db-elasticmq` - ElasticMQ SQS-compatible local message queue
8. `db-elasticmq-ui` - official ElasticMQ web UI for queues and messages
9. `db-dashboard` - tiny BusyBox static HTML launcher page

Temporary one-shot container:

- `db-minio-init` - creates the default MinIO bucket, then exits

PostgreSQL and Redis do not include full web admin panels inside their own DB containers, so this project adds `pgAdmin` and `RedisInsight`. ElasticMQ uses SoftwareMill's official `elasticmq-ui` image.

`db-minio-init` is intentionally not long-running. It runs after MinIO is healthy, creates the configured bucket, exits with code `0`, and is removed.

## Deployment model

This repo follows the successful-deployment backup and rollback pattern used by the app/MCP strategy repos, adjusted safely for a DB stack.

Important difference: this repo has persistent database volumes and mostly third-party images. Deployment rollback restores the last successful Compose source and runtime environment. It never deletes database volumes.

Server folders expected for the current server:

```text
/home/abrar/actions_db.local
/home/abrar/backup_db.local
```

Runtime environment file used by GitHub Actions:

```text
/home/abrar/.config/db.local/runtime.env
```

The workflow creates that runtime environment file from `.env.example` on first deployment and preserves it afterward.

Some deployment-critical values are forced by the workflow on every deploy so stale runtime values do not keep old port bindings.

## GitHub Actions deployment

Workflow file:

```text
.github/workflows/deploy-release.yml
```

Trigger:

```text
push to release branch
```

Expected self-hosted runner labels:

```text
self-hosted, Linux, X64, dbs-prod
```

Recommended server-side runner folder:

```text
/home/abrar/actions_db.local
```

Recommended backup folder:

```text
/home/abrar/backup_db.local
```

The deployment flow is:

```text
checkout release commit
validate scripts and server prerequisites
create/preserve runtime.env
force deployment-critical network values in runtime.env
generate pgAdmin servers.json
validate docker compose config
prepare rollback point
start candidate stack with health checks
run smoke test
replace successful deployment backup
on failure, restore last successful Compose source and runtime env
```

The backup folder keeps exactly one successful deployment backup, matching the strategy repo. This backup is a compact source/config snapshot, not a database-data backup.

Docker volumes are preserved during deploy and rollback.

## Quick start manually on the server

```bash
mkdir -p ~/db.local
cd ~/db.local

# copy this project here, then:
cp .env.example .env
nano .env

chmod +x scripts/*.sh
./scripts/start.sh --wait
./scripts/status.sh
./scripts/verify.sh
```

Or use the same local deploy wrapper as GitHub Actions:

```bash
DEPLOY_ENV_FILE="$HOME/.config/db.local/runtime.env" ./scripts/deploy-local.sh
```

## `.env` controls repeated names, paths, ports, and credentials

The `.env.example` file controls:

- server deployment folders: `ACTIONS_ROOT`, `BACKUP_ROOT`, `DEPLOY_ENV_FILE`
- generated/config folders: `GENERATED_DIR`, `PGADMIN_SERVERS_JSON`, `DASHBOARD_WWW_DIR`, `POSTGRES_BACKUP_DIR`
- Compose project/network names
- container names
- Docker volume names
- host bind addresses
- service ports
- default usernames/passwords
- MinIO default bucket
- ElasticMQ API/UI ports and persistent storage volume

This keeps repeated values consistent across Compose, scripts, and GitHub Actions.

## Desired network model

This repo uses two different exposure patterns:

1. Dashboard through Caddy only
2. DB/admin services directly through their native ports

## Dashboard access model

The dashboard should be exposed only through host Caddy:

```text
https://dbs.home.arpa
        |
        v
host Caddy
        |
        v
127.0.0.1:8003
        |
        v
db-dashboard BusyBox container
```

Runtime values:

```env
DASHBOARD_HOST_BIND=127.0.0.1
DASHBOARD_PORT=8003
```

Expected Docker mapping:

```text
127.0.0.1:8003->8080/tcp
```

or:

```text
127.0.0.1:8003->8003/tcp
```

Both are acceptable. The important part is the host-side binding:

```text
127.0.0.1:8003
```

That means the dashboard is not directly exposed to LAN on `:8003`. It is reachable through Caddy:

```text
https://dbs.home.arpa
```

## DB/admin service access model

DB/admin services should be accessed directly on their native ports, not through Caddy.

Caddy is good for HTTP/HTTPS web apps. It is not the ideal pattern for raw database protocols such as PostgreSQL, Redis, Neo4j Bolt, or S3-compatible MinIO API.

Runtime value:

```env
DB_HOST_BIND=0.0.0.0
```

This means Docker publishes DB/admin ports on all host interfaces. Access control must be handled by firewall policy.

Do not port-forward these DB/admin ports from the router to the internet.

Expected DB/admin ports:

| Service | Port | Access pattern |
|---|---:|---|
| pgAdmin | `5050` | Direct HTTP from LAN |
| PostgreSQL + pgvector | `5432` | Direct PostgreSQL client from LAN |
| RedisInsight | `5540` | Direct HTTP from LAN |
| Redis | `6379` | Direct Redis client from LAN |
| Neo4j Browser | `7474` | Direct HTTP from LAN |
| Neo4j Bolt | `7687` | Direct Bolt client from LAN |
| MinIO S3 API | `9000` | Direct S3-compatible client from LAN |
| MinIO Console | `9001` | Direct HTTP from LAN |
| ElasticMQ SQS API | `9324` | Direct SQS-compatible HTTP API from LAN |
| ElasticMQ UI | `9325` | Direct HTTP from LAN |

## Expected Docker port bindings

After deployment:

```bash
docker ps --format "table {{.Names}}\t{{.Ports}}" | grep db-
```

Expected DB/admin service mappings:

```text
db-pgadmin        443/tcp, 0.0.0.0:5050->80/tcp
db-postgres       0.0.0.0:5432->5432/tcp
db-redis          0.0.0.0:6379->6379/tcp
db-redisinsight   0.0.0.0:5540->5540/tcp
db-neo4j          0.0.0.0:7474->7474/tcp, 0.0.0.0:7687->7687/tcp
db-minio          0.0.0.0:9000-9001->9000-9001/tcp
db-elasticmq      0.0.0.0:9324->9324/tcp
db-elasticmq-ui   0.0.0.0:9325->3000/tcp
```

Expected dashboard mapping:

```text
db-dashboard      127.0.0.1:8003->8080/tcp
```

or:

```text
db-dashboard      127.0.0.1:8003->8003/tcp
```

Both dashboard mappings are acceptable.

## Recommended Caddy route for dbs.home.arpa

Keep the dashboard bound to localhost:

```env
DASHBOARD_HOST_BIND=127.0.0.1
DASHBOARD_PORT=8003
```

Add this to `/etc/caddy/Caddyfile`:

```caddyfile
dbs.home.arpa {
    tls internal
    reverse_proxy 127.0.0.1:8003
}
```

Then validate and reload Caddy:

```bash
sudo caddy fmt --overwrite /etc/caddy/Caddyfile
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl reload caddy
sudo systemctl status caddy --no-pager -l
```

Test from the server:

```bash
curl -kI --resolve dbs.home.arpa:443:127.0.0.1 https://dbs.home.arpa
```

Expected:

```text
HTTP/2 200
```

Open:

```text
https://dbs.home.arpa
```

The dashboard links should point to the admin panels by hostname and port, for example:

```text
https://pgadmin.dbs.home.arpa
https://redis.dbs.home.arpa
https://neo4j.dbs.home.arpa
https://minio.dbs.home.arpa
https://sqs.dbs.home.arpa
```

## Default endpoints

| Service | Endpoint |
|---|---|
| Static dashboard through Caddy | `https://dbs.home.arpa` |
| Static dashboard direct local only | `http://127.0.0.1:8003` |
| PostgreSQL | `dbs.home.arpa:5432` |
| pgAdmin | `https://pgadmin.dbs.home.arpa` |
| Redis | `dbs.home.arpa:6379` |
| RedisInsight | `https://redis.dbs.home.arpa` |
| Neo4j Browser | `https://neo4j.dbs.home.arpa` |
| Neo4j Bolt | `bolt://dbs.home.arpa:7687` |
| MinIO S3 API | `http://dbs.home.arpa:9000` |
| MinIO Console | `https://minio.dbs.home.arpa` |
| ElasticMQ SQS API | `http://dbs.home.arpa:9324` |
| ElasticMQ UI | `https://sqs.dbs.home.arpa` |

If DNS is not configured yet, use the server IP:

```text
192.168.1.126
```

Example:

```text
http://192.168.1.126:5050
```

## Default credentials

| Service | Username | Password |
|---|---|---|
| PostgreSQL | `langgraph_user` | `change_me_postgres_2026` |
| pgAdmin | `admin@local.dev` | `change_me_pgadmin_2026` |
| Redis | default user | `change_me_redis_2026` |
| RedisInsight | no app login by default | Redis connection is preconfigured |
| Neo4j | `neo4j` | `change_me_neo4j_2026` |
| MinIO | `minioadmin` | `change_me_minio_2026` |
| ElasticMQ / UI | no authentication | no password |

Change passwords in the runtime environment before serious use.

Important: PostgreSQL and Neo4j initialize credentials when their persistent volumes are first created. If credentials are changed after first startup, the old DB credentials may still remain in the existing volumes.

## Runtime environment

Main server runtime file:

```text
/home/abrar/.config/db.local/runtime.env
```

Important network values:

```env
DB_HOST_BIND=0.0.0.0
DASHBOARD_HOST_BIND=127.0.0.1
DASHBOARD_PORT=8003
```

`DB_HOST_BIND=0.0.0.0` publishes DB/admin ports on all host interfaces.

`DASHBOARD_HOST_BIND=127.0.0.1` keeps the dashboard private to the server so it is only reachable through Caddy.

The GitHub Actions workflow should force these values on every deployment:

```bash
set_runtime_env_value DB_HOST_BIND '0.0.0.0' "$DEPLOY_ENV_FILE"
set_runtime_env_value DASHBOARD_HOST_BIND '127.0.0.1' "$DEPLOY_ENV_FILE"
set_runtime_env_value DASHBOARD_PORT '8003' "$DEPLOY_ENV_FILE"
```

This prevents old persistent runtime values from keeping stale port bindings.

## LAN access through dbs.home.arpa

DB/admin services are intended to be reachable directly from the LAN:

| Service | Endpoint |
|---|---|
| Static dashboard through Caddy | `https://dbs.home.arpa` |
| PostgreSQL | `dbs.home.arpa:5432` |
| pgAdmin | `https://pgadmin.dbs.home.arpa` |
| Redis | `dbs.home.arpa:6379` |
| RedisInsight | `https://redis.dbs.home.arpa` |
| Neo4j Browser | `https://neo4j.dbs.home.arpa` |
| Neo4j Bolt | `bolt://dbs.home.arpa:7687` |
| MinIO S3 API | `http://dbs.home.arpa:9000` |
| MinIO Console | `https://minio.dbs.home.arpa` |
| ElasticMQ SQS API | `http://dbs.home.arpa:9324` |
| ElasticMQ UI | `https://sqs.dbs.home.arpa` |

Do not port-forward these DB/admin ports from your router to the internet.

## Firewall example

Example LAN subnet:

```text
192.168.1.0/24
```

Recommended UFW rules with comments:

```bash
sudo ufw allow from 192.168.1.0/24 to any port 22 proto tcp comment 'LAN SSH only'

sudo ufw allow from 192.168.1.0/24 to any port 5050 proto tcp comment 'db.local pgAdmin UI - LAN only'
sudo ufw allow from 192.168.1.0/24 to any port 5432 proto tcp comment 'db.local PostgreSQL pgvector - LAN only'

sudo ufw allow from 192.168.1.0/24 to any port 5540 proto tcp comment 'db.local RedisInsight UI - LAN only'
sudo ufw allow from 192.168.1.0/24 to any port 6379 proto tcp comment 'db.local Redis - LAN only'

sudo ufw allow from 192.168.1.0/24 to any port 7474 proto tcp comment 'db.local Neo4j Browser HTTP - LAN only'
sudo ufw allow from 192.168.1.0/24 to any port 7687 proto tcp comment 'db.local Neo4j Bolt - LAN only'

sudo ufw allow from 192.168.1.0/24 to any port 9000 proto tcp comment 'db.local MinIO S3 API - LAN only'
sudo ufw allow from 192.168.1.0/24 to any port 9001 proto tcp comment 'db.local MinIO Console - LAN only'

sudo ufw allow from 192.168.1.0/24 to any port 9324 proto tcp comment 'db.local ElasticMQ SQS API - LAN only'
sudo ufw allow from 192.168.1.0/24 to any port 9325 proto tcp comment 'db.local ElasticMQ UI - LAN only'
```

For Caddy, choose one policy.

LAN-only Caddy:

```bash
sudo ufw allow from 192.168.1.0/24 to any port 80 proto tcp comment 'Caddy HTTP - LAN only'
sudo ufw allow from 192.168.1.0/24 to any port 443 proto tcp comment 'Caddy HTTPS - LAN only'
```

Public Caddy:

```bash
sudo ufw allow 80/tcp comment 'Caddy HTTP redirect'
sudo ufw allow 443/tcp comment 'Caddy HTTPS'
```

For `*.home.arpa`, LAN-only Caddy is usually cleaner.

## Important Docker and UFW note

Docker-published ports can bypass normal UFW input rules on some Linux setups because Docker programs iptables directly.

Because this repo uses:

```env
DB_HOST_BIND=0.0.0.0
```

the firewall policy is important.

For normal home/LAN use, the UFW rules above may be enough. For stricter firewall-only access control, add `DOCKER-USER` chain rules to enforce LAN-only access for Docker-published DB/admin ports.

The DB/admin ports that need firewall control are:

```text
5050, 5432, 5540, 6379, 7474, 7687, 9000, 9001, 9324, 9325
```

The dashboard port `8003` should not be exposed directly because it is bound to `127.0.0.1`.

## Test from the server

Test dashboard directly:

```bash
curl -I http://127.0.0.1:8003
```

Test dashboard through Caddy:

```bash
curl -kI --resolve dbs.home.arpa:443:127.0.0.1 https://dbs.home.arpa
```

Check Docker bindings:

```bash
docker ps --format "table {{.Names}}\t{{.Ports}}" | grep db-
```

Expected DB/admin service bindings should show `0.0.0.0`.

Expected dashboard binding should show `127.0.0.1:8003`.

## Test from Windows

PowerShell:

```powershell
Resolve-DnsName dbs.home.arpa

curl.exe -kI https://dbs.home.arpa

Test-NetConnection dbs.home.arpa -Port 5050
Test-NetConnection dbs.home.arpa -Port 5432
Test-NetConnection dbs.home.arpa -Port 5540
Test-NetConnection dbs.home.arpa -Port 6379
Test-NetConnection dbs.home.arpa -Port 7474
Test-NetConnection dbs.home.arpa -Port 7687
Test-NetConnection dbs.home.arpa -Port 9000
Test-NetConnection dbs.home.arpa -Port 9001
Test-NetConnection dbs.home.arpa -Port 9324
Test-NetConnection dbs.home.arpa -Port 9325
```

Expected:

```text
TcpTestSucceeded : True
```

Direct dashboard test from Windows should normally fail:

```powershell
Test-NetConnection dbs.home.arpa -Port 8003
```

That is expected if the dashboard is correctly bound only to `127.0.0.1` and exposed only through Caddy.

## App connection strings

Same server:

```env
DATABASE_URL=postgresql+asyncpg://langgraph_user:change_me_postgres_2026@127.0.0.1:5432/langgraph_app
REDIS_URL=redis://:change_me_redis_2026@127.0.0.1:6379/0
NEO4J_URI=bolt://127.0.0.1:7687
NEO4J_USERNAME=neo4j
NEO4J_PASSWORD=change_me_neo4j_2026
S3_ENDPOINT_URL=http://127.0.0.1:9000
S3_ACCESS_KEY=minioadmin
S3_SECRET_KEY=change_me_minio_2026
S3_BUCKET=langgraph-app
SQS_ENDPOINT_URL=http://127.0.0.1:9324
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=test
AWS_SECRET_ACCESS_KEY=test
```

LAN:

```env
DATABASE_URL=postgresql+asyncpg://langgraph_user:change_me_postgres_2026@dbs.home.arpa:5432/langgraph_app
REDIS_URL=redis://:change_me_redis_2026@dbs.home.arpa:6379/0
NEO4J_URI=bolt://dbs.home.arpa:7687
NEO4J_USERNAME=neo4j
NEO4J_PASSWORD=change_me_neo4j_2026
S3_ENDPOINT_URL=http://dbs.home.arpa:9000
S3_ACCESS_KEY=minioadmin
S3_SECRET_KEY=change_me_minio_2026
S3_BUCKET=langgraph-app
SQS_ENDPOINT_URL=http://dbs.home.arpa:9324
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=test
AWS_SECRET_ACCESS_KEY=test
```

## Important password/volume note

PostgreSQL and Neo4j initialize credentials when their persistent volumes are first created. If you change `.env` after first startup, the old DB credentials may still remain in the existing volumes.

For a clean reset during testing:

```bash
./scripts/reset-all-data.sh
```

This deletes all stack volumes and should never be used by GitHub Actions.

## PostgreSQL logical backup

```bash
./scripts/backup-postgres.sh
```

By default this writes to:

```text
./backups/postgres
```

You can change that with:

```env
POSTGRES_BACKUP_DIR=./backups/postgres
```

## Full reset during testing

Use only when you intentionally want to delete all DB stack data:

```bash
./scripts/reset-all-data.sh
```

This deletes Docker volumes for the DB stack.

Never call this from GitHub Actions.

## Hardware note

This stack is appropriate for a Core i5-6400T, 16 GB RAM, and SSD for lightweight home-server use. Neo4j is the largest idle memory user in this stack; its heap/page-cache defaults are intentionally modest in `.env.example`.


## ElasticMQ / Amazon SQS development model

ElasticMQ provides the local SQS-compatible endpoint:

```text
http://dbs.home.arpa:9324
```

The official ElasticMQ UI is available at:

```text
https://sqs.dbs.home.arpa
```

Containers on the shared `db-local-net` network should use `http://elasticmq:9324` instead of routing through the host. The local stack persists ElasticMQ message storage in the `db-elasticmq-data` Docker volume.

For local AWS SDK clients, use dummy credentials such as `test` and set the SQS endpoint override to ElasticMQ. In AWS production, remove the endpoint override so the SDK uses Amazon SQS normally.


## Hardening profile

The hardened deployment keeps raw application protocols on LAN ports while binding all browser/admin UIs to localhost and publishing them through host Caddy with private `tls internal` HTTPS. See `docs/Caddyfile.internal.example` and `docs/OPERATIONS.md`.

Deployment requires at least 5 GiB free disk, rotates Docker logs, applies conservative CPU/memory/PID limits, validates all services, refuses placeholder passwords, and keeps exactly one successful deployment rollback snapshot. Database volumes are preserved across deployments. Explicit data-backup scripts use count-based retention.

Runtime images are pinned to reviewed stable/LTS versions instead of floating `:latest` tags. Update versions deliberately through a reviewed change.
