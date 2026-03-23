from datetime import datetime

from airflow import DAG
from airflow.models import Variable
from cosmos.operators import DbtDocsS3Operator
from utils.dbt_profile import DEFAULT_DBT_ROOT_PATH, EXECUTE_PATH, dbt_profile_config


def dbt_docs_path():
    target_name = Variable.get("ENV", "dev")

    if target_name == "dev":
        return "logs/dp-dbt/docs"
    elif target_name == "prod":
        return "eks/airflow-dp-dbt/logs/docs"
    else:
        raise ValueError(
            f"Unknown target name: {target_name}. Expected 'dev' or 'prod'."
        )


def dbt_bucket_name():
    target_name = Variable.get("ENV", "dev")

    if target_name == "dev":
        return "mrt-test-dp-airflow"
    elif target_name == "prod":
        return "mrt-dw"
    else:
        raise ValueError(
            f"Unknown target name: {target_name}. Expected 'dev' or 'prod'."
        )


with DAG(
    dag_id="dbt_docs",
    schedule="0 10 * * *",
    start_date=datetime(2023, 1, 1),
    catchup=False,
    default_args={"retries": 0},
) as dag:

    docs_static = DbtDocsS3Operator(
        task_id="generate_dbt_docs_static",
        project_dir=DEFAULT_DBT_ROOT_PATH,
        profile_config=dbt_profile_config(),
        dbt_executable_path=EXECUTE_PATH,
        connection_id="log_conn",
        bucket_name=dbt_bucket_name(),
        folder_dir=dbt_docs_path(),
        dbt_cmd_flags=["--static"],
    )

    docs = DbtDocsS3Operator(
        task_id="generate_dbt_docs",
        project_dir=DEFAULT_DBT_ROOT_PATH,
        profile_config=dbt_profile_config(),
        dbt_executable_path=EXECUTE_PATH,
        connection_id="log_conn",
        bucket_name=dbt_bucket_name(),
        folder_dir=dbt_docs_path(),
    )

    [docs, docs_static]
