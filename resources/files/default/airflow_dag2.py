from __future__ import annotations

import pendulum
import os
import time
import tempfile
from datetime import datetime, timedelta
from airflow.models.dag import DAG
from airflow.operators.python import PythonOperator
# from airflow.operators.dagrun_operator import TriggerDagRunOperator
from airflow.providers.amazon.aws.hooks.s3 import S3Hook
import boto3

# --- Configuración ---
S3_BUCKET_NAME = "malware"
SOURCE_PREFIX = "analyzed/"
PROCESSED_PREFIX = "processed/"
ENDPOINT_URL = "http://s3.service:9000"
LOCAL_TMP_DIR = "/usr/share/logstash/malware"  # Logstash monitoriza este path
LOCK_MAX_AGE_MINUTES = 30  # Tiempo máximo permitido antes de borrar .lock antiguos


# --- Cliente MinIO ---
def get_minio_client():
    hook = S3Hook(aws_conn_id="minio_conn")
    return boto3.client(
        "s3",
        endpoint_url=ENDPOINT_URL,
        aws_access_key_id=hook.get_credentials().access_key,
        aws_secret_access_key=hook.get_credentials().secret_key,
    )


# --- Descargar archivo de forma segura ---
def descargar_archivo_desde_minio():
    """
    Descarga un archivo de MinIO y lo guarda en /usr/share/logstash/malware/
    usando una operación atómica (.tmp -> .lock) para evitar lecturas incompletas.
    """
    os.makedirs(LOCAL_TMP_DIR, exist_ok=True)
    s3_client = get_minio_client()

    response = s3_client.list_objects_v2(Bucket=S3_BUCKET_NAME, Prefix=SOURCE_PREFIX)
    if "Contents" not in response:
        print("📭 No hay archivos nuevos en analyzed/.")
        return None

    key = response["Contents"][0]["Key"]
    base_name = os.path.basename(key)
    if not base_name.endswith(".lock"):
        base_name += ".lock"

    final_lock_path = os.path.join(LOCAL_TMP_DIR, base_name)
    fd, tmp_path = tempfile.mkstemp(prefix=base_name + ".", dir=LOCAL_TMP_DIR)
    os.close(fd)

    try:
        # Descargar primero a un archivo temporal
        s3_client.download_file(S3_BUCKET_NAME, key, tmp_path)

        # Forzar flush a disco
        with open(tmp_path, "rb") as f:
            f.flush()
            os.fsync(f.fileno())

        os.chmod(tmp_path, 0o600)
        os.replace(tmp_path, final_lock_path)
        print(f"📥 Archivo descargado de MinIO: {key} → {final_lock_path}")

        return {"key": key, "local_path": final_lock_path}
    finally:
        if os.path.exists(tmp_path):
            try:
                os.remove(tmp_path)
            except Exception:
                pass


# --- Esperar a que Logstash procese el archivo ---
def esperar_procesamiento_logstash(ti, timeout=120, poll_interval=2):
    """
    Espera hasta que Logstash procese el archivo .lock.
    Detecta si desaparece o si es renombrado (.done, .processed, .ok).
    """
    data = ti.xcom_pull(task_ids="descargar_archivo")
    if not data:
        print("⚠️ No hay archivo descargado.")
        return False

    local_path = data["local_path"]
    base = os.path.basename(local_path)
    dirname = os.path.dirname(local_path)

    print(f"⏳ Esperando que Logstash procese {base} (timeout {timeout}s)...")
    start = time.time()

    while time.time() - start < timeout:
        if not os.path.exists(local_path):
            print(f"✅ {base} ya no existe: procesado por Logstash.")
            return True

        for suffix in (".processed", ".done", ".ok"):
            candidate = os.path.join(dirname, base + suffix)
            if os.path.exists(candidate):
                print(f"✅ Detectado archivo de señal: {candidate}")
                try:
                    os.remove(candidate)
                except Exception:
                    pass
                try:
                    if os.path.exists(local_path):
                        os.remove(local_path)
                except Exception:
                    pass
                return True

        time.sleep(poll_interval)

    print(f"⚠️ Timeout: Logstash no procesó {base} en {timeout} segundos.")
    return False


# --- Mover archivo procesado en MinIO ---
def mover_archivo_procesado(ti):
    """Mueve el archivo original en MinIO de analyzed/ a processed/"""
    data = ti.xcom_pull(task_ids="descargar_archivo")
    if not data:
        print("⚠️ No hay archivo para mover.")
        return

    s3_client = get_minio_client()
    key = data["key"]
    dest_key = PROCESSED_PREFIX + os.path.basename(key)

    s3_client.copy_object(
        Bucket=S3_BUCKET_NAME,
        CopySource={"Bucket": S3_BUCKET_NAME, "Key": key},
        Key=dest_key,
    )
    s3_client.delete_object(Bucket=S3_BUCKET_NAME, Key=key)
    print(f"📦 Archivo procesado movido a {dest_key}")


# --- Limpieza de .lock antiguos ---
def limpiar_archivos_lock_antiguos():
    """
    Borra archivos .lock de más de LOCK_MAX_AGE_MINUTES minutos en LOCAL_TMP_DIR.
    Esto evita acumulación si Logstash deja archivos sin procesar.
    """
    if not os.path.exists(LOCAL_TMP_DIR):
        print("ℹ️ Directorio local no existe, nada que limpiar.")
        return

    now = datetime.now()
    threshold = now - timedelta(minutes=LOCK_MAX_AGE_MINUTES)
    count_removed = 0

    for f in os.listdir(LOCAL_TMP_DIR):
        if not f.endswith(".lock"):
            continue
        full_path = os.path.join(LOCAL_TMP_DIR, f)
        try:
            mtime = datetime.fromtimestamp(os.path.getmtime(full_path))
            if mtime < threshold:
                os.remove(full_path)
                count_removed += 1
                print(f"🧹 Borrado {f} (modificado hace más de {LOCK_MAX_AGE_MINUTES} minutos)")
        except Exception as e:
            print(f"⚠️ No se pudo borrar {f}: {e}")

    if count_removed == 0:
        print("✅ No se encontraron archivos antiguos para limpiar.")
    else:
        print(f"🧽 Limpieza completa: {count_removed} archivos eliminados.")


# --- DAG ---
with DAG(
    dag_id="analizar_archivos_logstash",
    start_date=pendulum.datetime(2025, 9, 3, tz="UTC"),
    schedule=None,  # Se lanza desde dag_1
    catchup=False,
    tags=["logstash", "s3", "minio", "análisis", "seguro"],
) as dag:

    limpiar_lock_files = PythonOperator(
        task_id="limpiar_archivos_lock_antiguos",
        python_callable=limpiar_archivos_lock_antiguos,
    )

    descargar_archivo = PythonOperator(
        task_id="descargar_archivo",
        python_callable=descargar_archivo_desde_minio,
    )

    esperar_logstash = PythonOperator(
        task_id="esperar_procesamiento",
        python_callable=esperar_procesamiento_logstash,
    )

    mover_archivo = PythonOperator(
        task_id="mover_archivo",
        python_callable=mover_archivo_procesado,
    )

    limpiar_lock_files >> descargar_archivo >> esperar_logstash >> mover_archivo
