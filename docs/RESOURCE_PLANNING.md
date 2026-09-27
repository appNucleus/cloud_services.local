# Resource planning

With all six logical services enabled, expected long-running containers are:

1. `db-postgres`
2. `db-pgadmin`
3. `db-redis`
4. `db-redisinsight`
5. `db-neo4j`
6. `db-minio`
7. `db-elasticmq`
8. `db-elasticmq-ui`
9. `db-cognito`
10. `db-cognito-ui`
11. `db-ui-gateway`
12. `db-dashboard`

`db-minio-init` is temporary and removed after successful bucket initialization.

Disabled logical services remove their associated long-running containers, reducing resource use while preserving named volumes.

## Default ceilings

| Component | Memory | CPU |
|---|---:|---:|
| PostgreSQL | 2 GiB | 2.0 |
| pgAdmin | 768 MiB | 1.0 |
| Redis | 1 GiB | 1.0 |
| RedisInsight | 768 MiB | 1.0 |
| Neo4j | 2560 MiB | 2.0 |
| MinIO | 1536 MiB | 1.5 |
| ElasticMQ | 768 MiB | 1.0 |
| ElasticMQ UI | 512 MiB | 0.5 |
| Cognito Local | 512 MiB | 0.5 |
| Cognito Local UI | 256 MiB | 0.5 |
| UI gateway | 128 MiB | 0.5 |
| Dashboard | 64 MiB | 0.25 |
| MinIO init (temporary) | 256 MiB | 0.5 |

These values are ceilings, not reservations; normal idle usage is substantially lower.

For a 16 GiB development host, keep Neo4j heap/page-cache conservative, use Redis mainly for ephemeral/cache state, store large objects in MinIO, and monitor real usage with:

```bash
docker stats
```

The deployment requires at least 5 GiB free disk and warns below 10 GiB. Docker JSON logs rotate by default at 10 MiB × 3 files per container. Persistent service volumes are intentionally not assigned small filesystem quotas because a full database volume can cause abrupt failures.
