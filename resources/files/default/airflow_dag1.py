from __future__ import annotations

import pendulum
from airflow.models.dag import DAG
from airflow.operators.python import PythonOperator
from airflow.providers.amazon.aws.hooks.s3 import S3Hook
from airflow.operators.dagrun_operator import TriggerDagRunOperator
import boto3

S3_BUCKET_NAME = "malware"
SOURCE_PREFIX = "input/"
DEST_PREFIX = "analyzed/"
ENDPOINT_URL = "http://s3.service:9000"

def get_minio_client():
    hook = S3Hook(aws_conn_id="minio_conn")
    return boto3.client(
        "s3",
        endpoint_url=ENDPOINT_URL,
        aws_access_key_id=hook.get_credentials().access_key,
        aws_secret_access_key=hook.get_credentials().secret_key,
    )

def mover_todos_los_archivos_minio():
    s3_client = get_minio_client()
    response = s3_client.list_objects_v2(Bucket=S3_BUCKET_NAME, Prefix=SOURCE_PREFIX)
    if "Contents" not in response:
        print("📭 No hay archivos para mover.")
        return

    for obj in response["Contents"]:
        key = obj["Key"]
        if not key.endswith("/"):
            dest_key = DEST_PREFIX + key.split("/")[-1]
            s3_client.copy_object(
                Bucket=S3_BUCKET_NAME,
                CopySource={"Bucket": S3_BUCKET_NAME, "Key": key},
                Key=dest_key,
            )
            s3_client.delete_object(Bucket=S3_BUCKET_NAME, Key=key)
            print(f"✅ Movido {key} → {dest_key}")

with DAG(
    dag_id="mover_archivos_minio",
    start_date=pendulum.datetime(2025, 9, 3, tz="UTC"),
    schedule="*/1 * * * *",  # cada minuto
    catchup=False,
    tags=["s3", "minio", "mover"],
) as dag:

    mover_archivos = PythonOperator(
        task_id="mover_archivos",
        python_callable=mover_todos_los_archivos_minio,
    )

    trigger_dag2 = TriggerDagRunOperator(
        task_id="lanzar_analisis_logstash",
        trigger_dag_id="analizar_archivos_logstash",
    )

    mover_archivos >> trigger_dag2
