window.CLOUD_SERVICES_CONFIG = Object.freeze({
  hostname: "aws.home.arpa",
  services: Object.freeze({
    postgres: true,
    redis: true,
    neo4j: true,
    minio: true,
    elasticmq: true,
    cognito: true
  }),
  ports: Object.freeze({
    postgres: 5432,
    pgadmin: 5050,
    redis: 6379,
    redisinsight: 5540,
    neo4jHttp: 7474,
    neo4jBolt: 7687,
    minioApi: 9000,
    minioConsole: 9001,
    elasticmqApi: 9324,
    elasticmqUi: 9325,
    cognito: 9229,
    cognitoUi: 9230
  })
});
