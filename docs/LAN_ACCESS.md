# LAN access

This file documents the intended LAN exposure model for the DB stack.

## Intended model

Use two different access patterns:

1. Dashboard through Caddy only
2. DB/admin services directly on their native ports

## Dashboard

The dashboard should not be exposed directly to LAN clients on port `8003`.

It should stay bound to localhost:

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

Both are acceptable.

Access it through Caddy:

```text
https://dbs.home.arpa
```

Caddy should proxy:

```text
dbs.home.arpa -> 127.0.0.1:8003
```

## DB/admin services

DB/admin services should be accessed directly from LAN clients on their service ports.

Use:

```env
DB_HOST_BIND=0.0.0.0
```

This tells Docker to publish DB/admin ports on all host interfaces. Firewall policy controls who can connect.

Do not port-forward these DB/admin ports from the router to the internet.

## Expected service endpoints

| Service | Endpoint |
|---|---|
| Dashboard through Caddy | `https://dbs.home.arpa` |
| pgAdmin | `https://pgadmin.dbs.home.arpa` |
| PostgreSQL + pgvector | `dbs.home.arpa:5432` |
| RedisInsight | `https://redis.dbs.home.arpa` |
| Redis | `dbs.home.arpa:6379` |
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

## Expected Docker port state

After deployment:

```bash
docker ps --format "table {{.Names}}\t{{.Ports}}" | grep db-
```

Expected DB/admin services:

```text
db-pgadmin        443/tcp, 127.0.0.1:5050->80/tcp
db-postgres       0.0.0.0:5432->5432/tcp
db-redis          0.0.0.0:6379->6379/tcp
db-redisinsight   127.0.0.1:5540->5540/tcp
db-neo4j          127.0.0.1:7474->7474/tcp, 0.0.0.0:7687->7687/tcp
db-minio          0.0.0.0:9000->9000/tcp, 127.0.0.1:9001->9001/tcp
db-elasticmq      0.0.0.0:9324->9324/tcp
db-elasticmq-ui   127.0.0.1:9325->3000/tcp
```

Expected dashboard:

```text
db-dashboard      127.0.0.1:8003->8080/tcp
```

or:

```text
db-dashboard      127.0.0.1:8003->8003/tcp
```

If DB/admin services still show `127.0.0.1`, LAN clients will not be able to access them. Check the persistent runtime file:

```bash
grep -E '^(DB_HOST_BIND|DASHBOARD_HOST_BIND|DASHBOARD_PORT)=' ~/.config/db.local/runtime.env
```

Expected:

```env
DB_HOST_BIND=0.0.0.0
DASHBOARD_HOST_BIND=127.0.0.1
DASHBOARD_PORT=8003
```

## UFW firewall policy

Example LAN subnet:

```text
192.168.1.0/24
```

Recommended UFW rules with comments:

```bash
sudo ufw allow from 192.168.1.0/24 to any port 22 proto tcp comment 'LAN SSH only'

sudo ufw allow from 192.168.1.0/24 to any port 5432 proto tcp comment 'db.local PostgreSQL pgvector - LAN only'

sudo ufw allow from 192.168.1.0/24 to any port 6379 proto tcp comment 'db.local Redis - LAN only'

sudo ufw allow from 192.168.1.0/24 to any port 7687 proto tcp comment 'db.local Neo4j Bolt - LAN only'

sudo ufw allow from 192.168.1.0/24 to any port 9000 proto tcp comment 'db.local MinIO S3 API - LAN only'

sudo ufw allow from 192.168.1.0/24 to any port 9324 proto tcp comment 'db.local ElasticMQ SQS API - LAN only'
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

Check UFW:

```bash
sudo ufw status verbose
sudo ufw status numbered
```

Expected default policy:

```text
Default: deny (incoming), allow (outgoing)
```

## Docker and UFW warning

Docker-published ports can bypass normal UFW input rules on some Linux setups because Docker programs iptables directly.

Because this repo uses:

```env
DB_HOST_BIND=0.0.0.0
```

firewall enforcement matters.

For normal home/LAN use, the UFW rules above may be enough. For stricter firewall-only control, enforce LAN-only access using the `DOCKER-USER` chain.

DB/admin ports that need firewall control:

```text
5050, 5432, 5540, 6379, 7474, 7687, 9000, 9001, 9324, 9325
```

Dashboard port `8003` should not be directly exposed to LAN because it is bound to `127.0.0.1`.

## Test from the server

Check runtime env:

```bash
grep -E '^(DB_HOST_BIND|DASHBOARD_HOST_BIND|DASHBOARD_PORT)=' ~/.config/db.local/runtime.env
```

Check Docker bindings:

```bash
docker ps --format "table {{.Names}}\t{{.Ports}}" | grep db-
```

Test dashboard direct on the server:

```bash
curl -I http://127.0.0.1:8003
```

Test dashboard through Caddy on the server:

```bash
curl -kI --resolve dbs.home.arpa:443:127.0.0.1 https://dbs.home.arpa
```

## Test from Windows

PowerShell:

```powershell
Resolve-DnsName dbs.home.arpa
```

Expected:

```text
192.168.1.126
```

Test dashboard through Caddy:

```powershell
curl.exe -kI https://dbs.home.arpa
```

Test DB/admin ports:

```powershell
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

Direct dashboard port test from Windows should normally fail:

```powershell
Test-NetConnection dbs.home.arpa -Port 8003
```

That is expected because the dashboard should be available through Caddy only.

## Troubleshooting

### DB/admin ports fail from LAN

Check Docker binding:

```bash
docker ps --format "table {{.Names}}\t{{.Ports}}" | grep db-
```

If DB/admin services show `127.0.0.1`, fix runtime env:

```bash
grep -E '^(DB_HOST_BIND|DASHBOARD_HOST_BIND|DASHBOARD_PORT)=' ~/.config/db.local/runtime.env
```

Expected:

```env
DB_HOST_BIND=0.0.0.0
DASHBOARD_HOST_BIND=127.0.0.1
DASHBOARD_PORT=8003
```

Then redeploy/recreate containers. Docker port bindings cannot change on already-running containers.

### Dashboard through Caddy fails

Test the direct local dashboard on the server:

```bash
curl -I http://127.0.0.1:8003
```

Then test Caddy locally:

```bash
curl -kI --resolve dbs.home.arpa:443:127.0.0.1 https://dbs.home.arpa
```

Check Caddy logs:

```bash
sudo journalctl -u caddy --no-pager -n 100
```

### DNS fails

From Windows:

```powershell
Resolve-DnsName dbs.home.arpa
```

It should resolve to:

```text
192.168.1.126
```


## Hardened admin UI policy

Set `ADMIN_UI_HOST_BIND=127.0.0.1`. Ports 5050, 5540, 7474, 9001 and 9325 are host-local only and Caddy publishes them via the HTTPS subdomains above. Do not add LAN firewall allows for these localhost-only UI ports. Raw application ports 5432, 6379, 7687, 9000 and 9324 remain LAN-accessible subject to firewall policy.

Caddy hostnames require LAN DNS records (or an appropriate wildcard) resolving `*.dbs.home.arpa` to the DB server. Caddy's `tls internal` certificates are intentionally private; clients may leave the CA untrusted and accept browser warnings as agreed.
