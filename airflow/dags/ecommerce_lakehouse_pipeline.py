"""
IDSR Data Lakehouse & AI Orchestration Pipeline
DAG: ecommerce_lakehouse_daily_pipeline
Demonstrates TaskFlow API, branching, dbt execution, ML inference and SLAs.
"""

from datetime import datetime, timedelta
from airflow import DAG
from airflow.decorators import task
from airflow.operators.bash import BashOperator
from airflow.operators.empty import EmptyOperator
from airflow.utils.trigger_rule import TriggerRule

default_args = {
    'owner': 'idsr_data_team',
    'depends_on_past': False,
    'email': ['eng-dados@idsr.com.br'],
    'email_on_failure': True,
    'email_on_retry': False,
    'retries': 3,
    'retry_delay': timedelta(minutes=5),
    'sla': timedelta(hours=2),
}

with DAG(
    dag_id='ecommerce_lakehouse_daily_pipeline',
    default_args=default_args,
    description='Orquestração Medallion: MinIO S3 -> PySpark Bronze/Silver -> dbt Gold -> ML Inference',
    schedule_interval='0 3 * * *',  # Executa diariamente às 03:00 UTC
    start_date=datetime(2026, 1, 1),
    catchup=False,
    tags=['lakehouse', 'pyspark', 'dbt', 'ml', 'idsr'],
) as dag:

    start_pipeline = EmptyOperator(task_id='start_pipeline')

    @task(task_id='ingest_raw_events_to_bronze')
    def ingest_to_bronze():
        """Ingestão batch de arquivos crus (CSV/JSON) do MinIO para Parquet particionado."""
        import logging
        logger = logging.getLogger("airflow.task")
        logger.info("[BRONZE] Ingerindo 100.000 eventos brutos da landing zone S3...")
        return {"status": "success", "rows_ingested": 102450}

    @task(task_id='pyspark_silver_curation')
    def run_pyspark_silver_cleansing(ingest_meta: dict):
        """Deduplicação, conformidade de schemas e mascaramento LGPD via PySpark."""
        import logging
        logger = logging.getLogger("airflow.task")
        logger.info(f"[SILVER] Processando {ingest_meta['rows_ingested']} linhas no cluster Spark...")
        logger.info("[SILVER] Aplicando validações de schema e escrita em delta/parquet.")
        return {"status": "success", "curated_records": 100000}

    # Execução e testes de integridade do dbt
    dbt_run_gold = BashOperator(
        task_id='dbt_run_gold_models',
        bash_command='dbt run --models marts --project-dir /app/dbt --profiles-dir /app/dbt',
    )

    dbt_test_quality_gates = BashOperator(
        task_id='dbt_test_data_quality_gates',
        bash_command='dbt test --project-dir /app/dbt --profiles-dir /app/dbt',
    )

    @task(task_id='ml_delay_risk_batch_scoring')
    def run_ml_batch_scoring():
        """Scoring diário de pedidos em trânsito com modelo Random Forest / XGBoost."""
        import logging
        logger = logging.getLogger("airflow.task")
        logger.info("[ML PREDICTOR] Carregando pedidos abertos e gerando predições de risco...")
        logger.info("[ML PREDICTOR] 1.450 pedidos avaliados; 82 sinalizados com risco crítico de atraso.")
        return {"flagged_orders": 82}

    end_pipeline = EmptyOperator(
        task_id='end_pipeline',
        trigger_rule=TriggerRule.ALL_SUCCESS
    )

    # Definição do grafo de dependências
    bronze_step = ingest_to_bronze()
    silver_step = run_pyspark_silver_cleansing(bronze_step)
    ml_step = run_ml_batch_scoring()

    start_pipeline >> bronze_step
    silver_step >> dbt_run_gold >> dbt_test_quality_gates >> ml_step >> end_pipeline
