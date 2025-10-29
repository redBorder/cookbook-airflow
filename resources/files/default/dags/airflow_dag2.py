from __future__ import annotations

import pendulum
import os
import uuid
import boto3
import logging
from airflow.models.dag import DAG
from airflow.operators.python import PythonOperator
from airflow.providers.amazon.aws.hooks.s3 import S3Hook

# --- Configuration ---
S3_BUCKET_NAME = "malware"
BASE_PREFIX = "mdata/analyzed/"
ENDPOINT_URL = "http://s3.service:9000"
LOCAL_TMP_DIR = "/usr/share/logstash/malware/"

# --- Logger ---
log = logging.getLogger(__name__)

# --- MinIO Client ---
def get_minio_client():
    """Retrieves and configures the MinIO S3 client."""
    hook = S3Hook(aws_conn_id="minio_conn")
    creds = hook.get_credentials()
    return boto3.client(
        "s3",
        endpoint_url=ENDPOINT_URL,
        aws_access_key_id=creds.access_key,
        aws_secret_access_key=creds.secret_key,
    )

# --- Download and Prepare Files for Logstash ---
def download_files_from_minio(**context):
    """
    Downloads files from the S3 path passed by the triggering DAG, 
    renames them with a UUID, and creates a corresponding .lock file for Logstash.
    """
    conf = context.get("dag_run").conf or {}
    # The 'date_path' comes from the XCom value pushed by the upstream DAG
    date_path = conf.get("date_path")

    if not date_path:
        log.warning("No 'date_path' received. Aborting DAG2 execution.")
        return

    prefix = f"{BASE_PREFIX}{date_path}"
    # Ensure the local directory exists
    os.makedirs(LOCAL_TMP_DIR, exist_ok=True)
    log.info("Downloading files from %s to %s", prefix, LOCAL_TMP_DIR)

    s3_client = get_minio_client()
    response = s3_client.list_objects_v2(Bucket=S3_BUCKET_NAME, Prefix=prefix)

    if "Contents" not in response or not response["Contents"]:
        log.info("No files found in %s", prefix)
        return

    for obj in response["Contents"]:
        key = obj["Key"]
        if key.endswith("/"):
            continue

        # Rename file to a unique identifier
        new_name = uuid.uuid4().hex
        dest_path = os.path.join(LOCAL_TMP_DIR, new_name)
        # Logstash often uses a .lock file mechanism for file integrity/atomicity
        lock_path = dest_path + ".lock"

        try:
            log.info("Downloading %s → %s", key, dest_path)
            # 1. Download the file
            s3_client.download_file(S3_BUCKET_NAME, key, dest_path)

            # 2. Create the .lock file
            with open(lock_path, "w") as lock_file:
                # The content of the lock file might vary, but here it stores the data file path
                lock_file.write(dest_path + "\n")

            # 3. Set permissions (r/w for owner and group, read for others)
            os.chmod(dest_path, 0o664)
            os.chmod(lock_path, 0o664)

            log.info("Ready for Logstash: %s and %s", dest_path, lock_path)

        except Exception as e:
            log.error("Error downloading or preparing %s: %s", key, e, exc_info=True)

# --- DAG Definition ---
with DAG(
    dag_id="analyze_files_logstash",
    start_date=pendulum.datetime(2025, 9, 3, tz="UTC"),
    schedule=None,  # triggered by dag1
    catchup=False,
    tags=["logstash", "s3", "minio", "analysis"],
) as dag:

    download_files_task = PythonOperator(
        task_id="download_files",
        python_callable=download_files_from_minio,
    )

    download_files_task