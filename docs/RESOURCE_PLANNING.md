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
