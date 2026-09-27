# LAN access

Canonical hostname:

```text
aws.home.arpa
```

LAN DNS should resolve this hostname to the Docker host. Do not router-port-forward these local development services to the public internet.

## Endpoints

| Service | Endpoint |
|---|---|
| Dashboard | `https://aws.home.arpa` |
| pgAdmin | `https://aws.home.arpa:5050` |
| PostgreSQL | `aws.home.arpa:5432` |
| RedisInsight | `https://aws.home.arpa:5540` |
| Redis | `redis://aws.home.arpa:6379/0` |
| Neo4j Browser | `https://aws.home.arpa:7474` |
| Neo4j Bolt | `bolt://aws.home.arpa:7687` |
| MinIO S3 API | `http://aws.home.arpa:9000` |
| MinIO Console | `https://aws.home.arpa:9001` |
| ElasticMQ SQS API | `http://aws.home.arpa:9324` |
| ElasticMQ UI | `https://aws.home.arpa:9325` |
| Cognito Local User Pools API | `http://aws.home.arpa:9229` |
| Cognito Local management UI | `https://aws.home.arpa:9230` |

Disabled logical services have no application container even though the shared UI gateway remains running.

## Binding model

```env
DB_HOST_BIND=0.0.0.0
UI_GATEWAY_HOST_BIND=0.0.0.0
DASHBOARD_HOST_BIND=127.0.0.1
DASHBOARD_PORT=8003
```

The main dashboard is loopback-only and published by system-level Caddy. Raw APIs and the Compose HTTPS UI gateway are LAN-bound and should be protected by firewall policy.

## Example UFW policy

For `192.168.1.0/24`:

```bash
sudo ufw allow from 192.168.1.0/24 to any port 22 proto tcp comment 'LAN SSH only'
sudo ufw allow from 192.168.1.0/24 to any port 5432 proto tcp comment 'PostgreSQL LAN only'
sudo ufw allow from 192.168.1.0/24 to any port 6379 proto tcp comment 'Redis LAN only'
sudo ufw allow from 192.168.1.0/24 to any port 7687 proto tcp comment 'Neo4j Bolt LAN only'
sudo ufw allow from 192.168.1.0/24 to any port 9000 proto tcp comment 'MinIO S3 LAN only'
sudo ufw allow from 192.168.1.0/24 to any port 9324 proto tcp comment 'ElasticMQ SQS LAN only'
sudo ufw allow from 192.168.1.0/24 to any port 9229 proto tcp comment 'Cognito Local API LAN only'
sudo ufw allow from 192.168.1.0/24 to any port 9230 proto tcp comment 'Cognito Local UI HTTPS LAN only'
sudo ufw allow from 192.168.1.0/24 to any port 5050 proto tcp comment 'pgAdmin HTTPS LAN only'
sudo ufw allow from 192.168.1.0/24 to any port 5540 proto tcp comment 'RedisInsight HTTPS LAN only'
sudo ufw allow from 192.168.1.0/24 to any port 7474 proto tcp comment 'Neo4j Browser HTTPS LAN only'
sudo ufw allow from 192.168.1.0/24 to any port 9001 proto tcp comment 'MinIO Console HTTPS LAN only'
sudo ufw allow from 192.168.1.0/24 to any port 9325 proto tcp comment 'ElasticMQ UI HTTPS LAN only'
sudo ufw allow from 192.168.1.0/24 to any port 443 proto tcp comment 'Caddy dashboard HTTPS LAN only'
```

Docker-published ports can interact with iptables independently of normal UFW input rules. Use the `DOCKER-USER` chain if strict enforcement is required.

## Tests

Server:

```bash
curl -I http://127.0.0.1:8003
curl -kI --resolve aws.home.arpa:443:127.0.0.1 https://aws.home.arpa
```

Windows/LAN client:

```powershell
Resolve-DnsName aws.home.arpa
curl.exe -kI https://aws.home.arpa
Test-NetConnection aws.home.arpa -Port 5432
Test-NetConnection aws.home.arpa -Port 6379
Test-NetConnection aws.home.arpa -Port 7687
Test-NetConnection aws.home.arpa -Port 9000
Test-NetConnection aws.home.arpa -Port 9324
Test-NetConnection aws.home.arpa -Port 9229
Test-NetConnection aws.home.arpa -Port 9230
```

Port `8003` should not be reachable directly from another LAN machine.
