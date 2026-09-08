
TRINO_VERSION=481
STARROCKS_VERSION=3.3-latest
ICEBERG_REST_VERSION=1.10.1
MINIO_VERSION=RELEASE.2024-09-13T20-26-02Z


docker pull minio/minio:${MINIO_VERSION}
docker pull minio/mc:latest
docker pull apache/iceberg-rest-fixture:${ICEBERG_REST_VERSION}
docker pull trinodb/trino:${TRINO_VERSION}
docker pull starrocks/fe-ubuntu:${STARROCKS_VERSION}
docker pull starrocks/be-ubuntu:${STARROCKS_VERSION}
docker pull prom/prometheus:latest
docker pull prom/node-exporter:latest
docker pull grafana/grafana:latest


docker save -o minio_${MINIO_VERSION}.tar minio/minio:${MINIO_VERSION} 
docker save -o mc.tar minio/mc:latest  
docker save  -o iceberg_${ICEBERG_REST_VERSION}.tar   apache/iceberg-rest-fixture:${ICEBERG_REST_VERSION} 
docker save -o trino_${TRINO_VERSION}.tar trinodb/trino:${TRINO_VERSION}  
docker save   -o fe-ubuntu_${STARROCKS_VERSION}.tar starrocks/fe-ubuntu:${STARROCKS_VERSION} 
docker save   -o be-ubuntu_${STARROCKS_VERSION}.tar  starrocks/be-ubuntu:${STARROCKS_VERSION} 
docker save  -o prometheus_latest.tar prom/prometheus:latest   
docker save  -o node-exporter_latest.tar prom/node-exporter:latest 
docker save -o grafana_latest.tar  grafana/grafana:latest    
