# Resource planning

Expected long-running containers for this project:

1. db-postgres
2. db-pgadmin
3. db-redis
4. db-redisinsight
5. db-neo4j
6. db-minio
7. db-elasticmq
8. db-elasticmq-ui
9. db-dashboard

`db-minio-init` is temporary and exits after creating the default bucket.

With your two app containers (`mcp` and `langchain/langgraph app`), the host will normally run about 11 long-running containers.

For a Core i5-6400T, 16 GB RAM, and 500 GB SSD, this is acceptable for 2-3 users if workloads are light/moderate. The largest memory consumers are usually Neo4j, PostgreSQL under load, and any LLM/Ollama model processes. The static dashboard and ElasticMQ UI are lightweight; ElasticMQ adds a modest local queue-service footprint.

Recommended first-run memory approach:

- Keep Neo4j heap max at 1 GB.
- Keep Neo4j page cache at 512 MB.
- Use Redis mainly as cache/queue, not as the only durable source of truth.
- Store raw files in MinIO and metadata/chunks in PostgreSQL.
- Monitor with `docker stats` during real usage.

Basic command:

```bash
docker stats
```

## Default hard limits

The Compose defaults cap the stack for a 16 GiB development host: PostgreSQL 2 GiB, pgAdmin 768 MiB, Redis 1 GiB, RedisInsight 768 MiB, Neo4j 2.5 GiB, MinIO 1.5 GiB, ElasticMQ 768 MiB, ElasticMQ UI 512 MiB, dashboard 64 MiB, and the one-shot MinIO initializer 256 MiB. These are ceilings, not reservations, so normal idle use is much lower. CPU limits are similarly conservative and configurable in `runtime.env`.

Redis application data is separately capped at 512 MiB with `allkeys-lru`, matching its intended cache/ephemeral-state role. The host deployment requires 5 GiB free disk and warns below 10 GiB. Docker logs rotate at 10 MiB x 3 files per container. Persistent database volumes are deliberately not given artificial filesystem quotas because a hard full-volume condition can corrupt or abruptly stop a database; capacity is controlled through host free-space gates, log caps, and count-based backup retention instead.
