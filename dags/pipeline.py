import pendulum
from airflow import DAG
from airflow.providers.standard.operators.bash import BashOperator
from airflow.providers.common.sql.operators.sql import SQLExecuteQueryOperator
from datetime import timedelta

default_args = {
    'owner': 'airflow',
    'depends_on_past': False,
    'email_on_failure': True,
    'email': ['alverogaviota@gmail.com'],
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}   

with DAG(
    'Stock_Market_ELT_Pipeline',
    default_args=default_args,
    description='Batch ELT pipeline for Stock Market',
    template_searchpath=["/opt/airflow/sql"],
    start_date=pendulum.datetime(2026, 1, 1, tz="Asia/Jakarta"),
    schedule='30 8 * * *',
    catchup=False,
) as dag:

    # Ingestion Task
    ingest_task = BashOperator( 
        task_id='run_ingestion',
        bash_command='python "/opt/airflow/src/01_ingestion.py"',
    )

    # Transformation Task
    transform_task = SQLExecuteQueryOperator(
        task_id='run_transformation',
        conn_id='warehouse_db',
        sql='02_transform.sql',
    )

    # Aggregation Task
    aggregate_task = SQLExecuteQueryOperator(
        task_id='run_aggregation',
        conn_id='warehouse_db',
        sql='03_aggregate.sql',
    )

    ingest_task >> transform_task >> aggregate_task