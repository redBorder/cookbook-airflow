from __future__ import annotations

import pendulum
import os
import boto3
import logging
from airflow.models.dag import DAG
from airflow.operators.python import PythonOperator
from airflow.providers.amazon.aws.hooks.s3 import S3Hook
from airflow.operators.trigger_dagrun import TriggerDagRunOperator

# --- Configuration ---
S3_BUCKET_NAME = "malware"
SOURCE_PREFIX = "mdata/input/"
DEST_PREFIX = "mdata/analyzed/"
ENDPOINT_URL = "http://s3.service:9000"

# --- Airflow Logger ---
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

# --- Move Files ---
def move_minio_files(**context):
    """
    Lists files in the source prefix, copies them to a time-based 
    destination prefix, and then deletes the originals.
    Pushes the date path to XCom if files are moved.
    """
    s3_client = get_minio_client()
    response = s3_client.list_objects_v2(Bucket=S3_BUCKET_NAME, Prefix=SOURCE_PREFIX)
    
    if "Contents" not in response:
        log.info("No files to move in prefix %s", SOURCE_PREFIX)
        return None

    now = pendulum.now("UTC")
    # Generates a path like 'YYYY/MM/DD/HH/'
    date_path = f"{now.year}/{now.month:02d}/{now.day:02d}/{now.hour:02d}/"
    moved = []

    for obj in response["Contents"]:
        key = obj["Key"]
        if key.endswith("/"):
            continue

        base_name = os.path.basename(key)
        dest_key = f"{DEST_PREFIX}{date_path}{base_name}"

        try:
            log.info("Moving %s → %s", key, dest_key)
            # 1. Copy the object
            s3_client.copy_object(
                Bucket=S3_BUCKET_NAME,
                CopySource={"Bucket": S3_BUCKET_NAME, "Key": key},
                Key=dest_key,
            )
            # 2. Delete the original object
            s3_client.delete_object(Bucket=S3_BUCKET_NAME, Key=key)
            moved.append(dest_key)
        except Exception as e:
            log.error("Error moving %s: %s", key, e, exc_info=True)

    if moved:
        log.info("Moved %d files to %s", len(moved), date_path)
        # Push the date_path to XCom for the next DAG
        context["ti"].xcom_push(key="date_path", value=date_path)
        return date_path
    else:
        log.warning("No files were moved.")
        return None

# --- DAG Definition ---
with DAG(
    dag_id="malware_move_minio_files",
    start_date=pendulum.datetime(2025, 9, 3, tz="UTC"),
    schedule="*/1 * * * *",  # every minute
    catchup=False,
    tags=["malware", "s3", "move"],
) as dag:

    move_files_task = PythonOperator(
        task_id="move_files",
        python_callable=move_minio_files,
    )

    trigger_dag2_task = TriggerDagRunOperator(
        task_id="trigger_logstash_analysis",
        trigger_dag_id="malware_analyze_files_logstash",
        # Pass the date_path (or None if no files moved) to the triggered DAG
        conf={"date_path": "{{ ti.xcom_pull(task_ids='move_files', key='date_path') }}"},
        wait_for_completion=False,
        trigger_rule="all_success",
    )

    move_files_task >> trigger_dag2_task