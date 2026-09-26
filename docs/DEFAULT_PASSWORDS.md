# DB access quick table

| # | Service | URL / endpoint | Username | Password |
|---:|---|---|---|---|
| 1 | PostgreSQL + pgvector | `dbs.home.arpa:5432` | `langgraph_user` | `change_me_postgres_2026` |
| 2 | pgAdmin | `https://pgadmin.dbs.home.arpa` | `admin@local.dev` | `change_me_pgadmin_2026` |
| 3 | Redis | `dbs.home.arpa:6379` | `default` | `change_me_redis_2026` |
| 4 | RedisInsight | `https://redis.dbs.home.arpa` | No app login | No app password |
| 5 | Neo4j Browser | `https://neo4j.dbs.home.arpa` | `neo4j` | `change_me_neo4j_2026` |
| 6 | Neo4j Bolt | `bolt://dbs.home.arpa:7687` | `neo4j` | `change_me_neo4j_2026` |
| 7 | MinIO S3 API | `http://dbs.home.arpa:9000` | `minioadmin` | `change_me_minio_2026` |
| 8 | MinIO Console | `https://minio.dbs.home.arpa` | `minioadmin` | `change_me_minio_2026` |
| 9 | ElasticMQ SQS API | `http://dbs.home.arpa:9324` | No authentication | No password |
| 10 | ElasticMQ UI | `https://sqs.dbs.home.arpa` | No app login | No app password |

`Dashboard`: [https://dbs.home.arpa](https://dbs.home.arpa)

> The `change_me_*` values above are documentation placeholders only. Hardened deployment intentionally refuses to start while any runtime password still uses one of these placeholders. Configure real values in `$HOME/.config/db.local/runtime.env` before deployment. The HTTPS UI certificates are issued by Caddy's private CA and may show a browser warning when that CA is not installed on the client.
