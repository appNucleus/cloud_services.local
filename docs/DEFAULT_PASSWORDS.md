# Local service access quick table

| # | Service | URL / endpoint | Username | Password |
|---:|---|---|---|---|
| 1 | PostgreSQL + pgvector | `aws.home.arpa:5432` | `langgraph_user` | `change_me_postgres_2026` |
| 2 | pgAdmin | `https://aws.home.arpa:5050` | `admin@local.dev` | `change_me_pgadmin_2026` |
| 3 | Redis | `redis://aws.home.arpa:6379/0` | `default` | `change_me_redis_2026` |
| 4 | RedisInsight | `https://aws.home.arpa:5540` | No app login | No app password |
| 5 | Neo4j Browser | `https://aws.home.arpa:7474` | `neo4j` | `change_me_neo4j_2026` |
| 6 | Neo4j Bolt | `bolt://aws.home.arpa:7687` | `neo4j` | `change_me_neo4j_2026` |
| 7 | MinIO S3 API | `http://aws.home.arpa:9000` | `minioadmin` | `change_me_minio_2026` |
| 8 | MinIO Console | `https://aws.home.arpa:9001` | `minioadmin` | `change_me_minio_2026` |
| 9 | ElasticMQ SQS API | `http://aws.home.arpa:9324` | No authentication | No password |
| 10 | ElasticMQ UI | `https://aws.home.arpa:9325` | No app login | No app password |
| 11 | Cognito Local User Pools API | `http://aws.home.arpa:9229` | Managed in user pools | Managed in user pools |

Dashboard: `https://aws.home.arpa`

The `change_me_*` values are local-development placeholders. Deployment currently warns about enabled-service placeholders for backward compatibility; use custom values for serious use. PostgreSQL and Neo4j credentials can be initialized into persistent volumes, so changing only `runtime.env` later does not necessarily change existing database credentials.
