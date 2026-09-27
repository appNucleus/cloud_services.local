# Caddy and dashboard routing

The canonical local hostname is:

```text
aws.home.arpa
```

## Main dashboard

The Nginx dashboard is bound only to loopback:

```env
DASHBOARD_HOST_BIND=127.0.0.1
DASHBOARD_PORT=8003
```

System-level Caddy should publish it:

```caddyfile
aws.home.arpa {
    tls internal
    reverse_proxy 127.0.0.1:8003
}
```

Validate and reload host Caddy after changing the server configuration:

```bash
sudo caddy fmt --overwrite /etc/caddy/Caddyfile
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

Server-side test:

```bash
curl -kI --resolve aws.home.arpa:443:127.0.0.1 https://aws.home.arpa
```

LAN DNS must resolve `aws.home.arpa` to the server.

## Compose admin UI gateway

The Compose `db-ui-gateway` is separate from host Caddy. It serves these HTTPS endpoints with Caddy `tls internal`:

- pgAdmin — `https://aws.home.arpa:5050`
- RedisInsight — `https://aws.home.arpa:5540`
- Neo4j Browser — `https://aws.home.arpa:7474`
- MinIO Console — `https://aws.home.arpa:9001`
- ElasticMQ UI — `https://aws.home.arpa:9325`
- Cognito Local UI + User Pools API — `https://aws.home.arpa:9229`

The gateway stays running even when a logical backend is disabled. The dashboard makes disabled admin links non-clickable, and deployment verification does not expect a disabled backend to answer.

Raw non-HTTP service protocols are not reverse-proxied through this gateway:

- PostgreSQL `5432`
- Redis `6379`
- Neo4j Bolt `7687`
- MinIO S3 API `9000`
- ElasticMQ SQS API `9324`
