from datetime import datetime, timedelta

from airflow.decorators import dag, task
from airflow.utils.task_group import TaskGroup
from cosmos import DbtRunLocalOperator
from utils.dbt_profile import DEFAULT_DBT_ROOT_PATH, EXECUTE_PATH, dbt_profile_config


@dag(
    schedule=None,
    catchup=False,
    default_args={
        "retries": 5,
        "retry_delay": timedelta(minutes=10),
    },
    start_date=datetime(2025, 6, 10),
    max_active_tasks=50,
    max_active_runs=5,
    params={
        "start_date": "2025-09-01",
        "end_date": "2025-09-03",
        "model": "DW_BIZ_LOG",
    },
)
def BIZ_LOG_BACKFILL():
    """
    DW_BIZ_LOG 모델 백필 DAG
    - 입력 파라미터 : 시작, 종료 날짜 ( YYYY-MM-DD ) 포함,
    - model : dbt 모델명 ( default : DW_BIZ_LOG )

    BIZ_LOG는 UTC기반, start_date -1일, end_date -1일로 백필 수행

    eg) params : start_date = 2025-09-01, end_date = 2025-09-03
        {'start_date': '2025-08-31', 'end_date': '2025-09-01', 'model': 'DW_BIZ_LOG'}
        {'start_date': '2025-09-01', 'end_date': '2025-09-02', 'model': 'DW_BIZ_LOG'}

    """

    @task
    def generate_date_list(start_date: str, end_date: str, model: str):
        start = datetime.strptime(start_date, "%Y-%m-%d").date()
        end = datetime.strptime(end_date, "%Y-%m-%d").date()

        dates = []
        while start < end:
            current_start_date = (start - timedelta(days=1)).strftime("%Y-%m-%d")
            current_end_date = start.strftime("%Y-%m-%d")
            dates.append(
                {
                    "start_date": current_start_date,
                    "end_date": current_end_date,
                    "model": model,
                }
            )
            start += timedelta(days=1)
        return dates

    with TaskGroup(group_id="biz_log_backfill") as backfill_group:
        DbtRunLocalOperator.partial(
            task_id="dbt_run_task",
            project_dir=DEFAULT_DBT_ROOT_PATH,
            profile_config=dbt_profile_config(),
            dbt_executable_path=EXECUTE_PATH,
            dbt_cmd_flags=["--debug"],
        ).expand_kwargs(
            generate_date_list(
                start_date="{{ params.start_date }}",
                end_date="{{ params.end_date }}",
                model="{{ params.model }}",
            ).map(
                lambda item: {
                    "task_id": f"{item['model']}_{item['start_date']}",
                    "select": [item["model"]],
                    "vars": {
                        "today_utc": item["end_date"],
                        "logical_start_date_kst": item["end_date"],
                        "logical_start_date_utc": item["start_date"],
                        "logical_end_date_utc": item["end_date"],
                        "struct_fields": "{{ var.value.struct_fields }}",
                    },
                }
            )
        )

    return backfill_group


BIZ_LOG_BACKFILL()
