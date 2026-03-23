from datetime import datetime, timedelta

from airflow.decorators import dag
from airflow.operators.empty import EmptyOperator
from common.alert import slack_failure_alert, slack_success_alert
from cosmos import DbtTaskGroup, ExecutionConfig, ProjectConfig, RenderConfig
from cosmos.constants import DbtResourceType, TestBehavior
from utils.dbt_profile import DEFAULT_DBT_ROOT_PATH, EXECUTE_PATH, dbt_profile_config


def convert_source_node(dag, task_group, node, **kwargs):
    return EmptyOperator(
        dag=dag,
        task_group=task_group,
        task_id=f"{node.name}",  # 소스 이름을 태스크 ID로 사용
    )


@dag(
    schedule="0 10 * * *",
    catchup=False,
    default_args={
        "retries": 3,
        "retry_delay": timedelta(minutes=10),
    },
    start_date=datetime(2025, 6, 10),
    max_active_tasks=30,
    max_active_runs=1,
    on_failure_callback=slack_failure_alert,
    on_success_callback=slack_success_alert,
)
def MRT_DBT_DAG_10():
    start_task = EmptyOperator(task_id="start_task")

    dbt_task = DbtTaskGroup(
        group_id="dbt_task_group",
        project_config=ProjectConfig(dbt_project_path=DEFAULT_DBT_ROOT_PATH),
        profile_config=dbt_profile_config(),
        execution_config=ExecutionConfig(
            dbt_executable_path=EXECUTE_PATH,
        ),
        render_config=RenderConfig(
            select=["tag:BRAZE"],
            node_converters={
                DbtResourceType("source"): convert_source_node,
            },
        ),
        operator_args={
            "dbt_cmd_global_flags": ["--debug"],
            "vars": {
                "start_date_kst": """{{ macros.datetime.strftime((data_interval_start.in_timezone('Asia/Seoul') - macros.timedelta(days=1)), '%Y-%m-%d') }}""",
                "end_date_kst": """{{ macros.datetime.strftime((data_interval_end.in_timezone('Asia/Seoul') - macros.timedelta(days=1)), '%Y-%m-%d') }}""",
                "logical_start_date_kst": """{{ macros.datetime.strftime((data_interval_start.in_timezone('Asia/Seoul')), '%Y-%m-%d') }}""",
                "logical_end_date_kst": """{{ macros.datetime.strftime((data_interval_end.in_timezone('Asia/Seoul')), '%Y-%m-%d') }}""",
                "start_date_utc": """{{ macros.datetime.strftime((data_interval_start.in_timezone('UTC') - macros.timedelta(days=1)), '%Y-%m-%d') }}""",
                "end_date_utc": """{{ macros.datetime.strftime((data_interval_end.in_timezone('UTC') - macros.timedelta(days=1)), '%Y-%m-%d') }}""",
                "logical_start_date_utc": """{{ macros.datetime.strftime((data_interval_start.in_timezone('UTC')), '%Y-%m-%d') }}""",
                "logical_end_date_utc": """{{ macros.datetime.strftime((data_interval_end.in_timezone('UTC')), '%Y-%m-%d') }}""",
                "today_kst": """{{ macros.datetime.strftime(data_interval_end.in_timezone('Asia/Seoul'), '%Y-%m-%d') }}""",
                "today_utc": """{{ macros.datetime.strftime(data_interval_end.in_timezone('UTC'), '%Y-%m-%d') }}""",
                "before_7_days_kst": """{{ macros.datetime.strftime((data_interval_end.in_timezone('Asia/Seoul') - macros.timedelta(days=7)), '%Y-%m-%d') }}""",
                "before_8_days_kst": """{{ macros.datetime.strftime((data_interval_end.in_timezone('Asia/Seoul') - macros.timedelta(days=8)), '%Y-%m-%d') }}""",
                "before_30_days_kst": """{{ macros.datetime.strftime((data_interval_end.in_timezone('Asia/Seoul') - macros.timedelta(days=30)), '%Y-%m-%d') }}""",
                "before_one_year": """{{(execution_date + macros.timedelta(days=-365) + macros.timedelta(hours=9)).strftime("%Y-%m-%d")}}""",
                "struct_fields": "{{ var.value.struct_fields }}",
            },
        },
    )

    start_task >> dbt_task


MRT_DBT_DAG_10()
