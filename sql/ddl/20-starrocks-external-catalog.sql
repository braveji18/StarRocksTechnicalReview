-- Track A: StarRocks 가 Trino 와 동일한 Iceberg 테이블을 바라보게 한다 (docs/02 §3.2)
-- 치환 변수: ${SR_CATALOG} ${ICEBERG_REST_URI} ${WAREHOUSE} ${S3_*}
DROP CATALOG IF EXISTS ${SR_CATALOG};

CREATE EXTERNAL CATALOG ${SR_CATALOG} PROPERTIES (
    "type"                            = "iceberg",
    "iceberg.catalog.type"            = "rest",
    "iceberg.catalog.uri"             = "${ICEBERG_REST_URI}",
    "iceberg.catalog.warehouse"       = "${WAREHOUSE}",
    "aws.s3.endpoint"                 = "${S3_ENDPOINT}",
    "aws.s3.region"                   = "${S3_REGION}",
    "aws.s3.enable_path_style_access" = "true",
    "aws.s3.access_key"               = "${S3_ACCESS_KEY}",
    "aws.s3.secret_key"               = "${S3_SECRET_KEY}"
);
