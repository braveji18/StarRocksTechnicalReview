-- Track A (Hive Metastore 변형)
-- 기존 레이크가 REST 카탈로그가 아니라 HMS 를 쓰는 경우 20-...sql 대신 사용한다.
-- 치환 변수: ${SR_CATALOG} ${HMS_URI} ${S3_*}
DROP CATALOG IF EXISTS ${SR_CATALOG};

CREATE EXTERNAL CATALOG ${SR_CATALOG} PROPERTIES (
    "type"                            = "iceberg",
    "iceberg.catalog.type"            = "hive",
    "hive.metastore.uris"             = "${HMS_URI}",
    "aws.s3.endpoint"                 = "${S3_ENDPOINT}",
    "aws.s3.region"                   = "${S3_REGION}",
    "aws.s3.enable_path_style_access" = "true",
    "aws.s3.access_key"               = "${S3_ACCESS_KEY}",
    "aws.s3.secret_key"               = "${S3_SECRET_KEY}"
);
