import logging
from datetime import datetime, timedelta

from airflow.decorators import dag, task
from airflow.models.variable import Variable
from airflow.operators.empty import EmptyOperator
from common.alert import slack_failure_alert, slack_success_alert
from cosmos import DbtTaskGroup, ExecutionConfig, ProjectConfig, RenderConfig
from cosmos.constants import DbtResourceType, TestBehavior
from kubernetes.client import models as k8s
from utils.BigQueryConn import BigQueryConn
from utils.dbt_profile import DEFAULT_DBT_ROOT_PATH, EXECUTE_PATH, dbt_profile_config


def convert_source_node(dag, task_group, node, **kwargs):
    return EmptyOperator(
        dag=dag,
        task_group=task_group,
        task_id=f"{node.name}",  # 소스 이름을 태스크 ID로 사용
    )


def get_resources(resource: dict):
    # KubernetesPodOperator에서 리소스 요청을 설정하는 예시
    memory = resource.get("memory", "100Mi")
    cpu = resource.get("cpu", "100m")
    return {
        "pod_override": k8s.V1Pod(
            spec=k8s.V1PodSpec(
                containers=[
                    k8s.V1Container(
                        name="base",  # 현재 사용 중인 컨테이너 이름과 일치시켜야 함
                        resources=k8s.V1ResourceRequirements(
                            requests={"memory": memory, "cpu": cpu},
                        ),
                    )
                ]
            )
        )
    }


@dag(
    schedule="0 6 * * *",
    catchup=False,
    default_args={
        "retries": 5,
        "retry_delay": timedelta(minutes=2),
    },
    start_date=datetime(2025, 6, 10),
    max_active_tasks=70,
    max_active_runs=1,
    on_failure_callback=slack_failure_alert,
    on_success_callback=slack_success_alert,
)
def MRT_DBT_DAG_06():
    start_task = EmptyOperator(task_id="start_task")

    @task
    def generate_struct_fields(**kwargs):
        # biz log에서 사용
        conn = BigQueryConn()
        query = conn.get_sql_of_file("sql/generate_struct_fields.sql", kwargs)
        logging.info(f"query: {query}")
        rows = conn.get_pandas(query).values.tolist()
        logging.info(f"rows: {rows}")
        struct_fields = ", ".join([f"{row[0]} STRING" for row in rows])
        logging.info(f"struct_fields: {struct_fields}")
        # 해당 struct_fields를 반환하여 dbt에서 사용할 수 있도록 합니다.
        # 예를 들어, 이 값을 dbt의 변수로 설정할 수 있습니다.
        Variable.set("struct_fields", struct_fields)
        return None

    dbt_task = DbtTaskGroup(
        group_id="dbt_task_group",
        project_config=ProjectConfig(dbt_project_path=DEFAULT_DBT_ROOT_PATH),
        profile_config=dbt_profile_config(),
        execution_config=ExecutionConfig(
            dbt_executable_path=EXECUTE_PATH,
        ),
        render_config=RenderConfig(
            exclude=["tag:BRAZE"],
            test_behavior=TestBehavior.AFTER_EACH,
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
                "before_32_days_kst": """{{ macros.datetime.strftime((data_interval_end.in_timezone('Asia/Seoul') - macros.timedelta(days=32)), '%Y-%m-%d') }}""",
                "before_one_year": """{{(execution_date + macros.timedelta(days=-365) + macros.timedelta(hours=9)).strftime("%Y-%m-%d")}}""",
                "struct_fields": "{{ var.value.struct_fields }}",
            },
            "executor_config": get_resources({"memory": "200Mi", "cpu": "200m"}),
        },
    )

    generate_struct_fields_task = generate_struct_fields()
    generate_struct_fields_task.operator.executor_config = get_resources(
        {"memory": "60Gi", "cpu": "4"}
    )  # 일부러 큰 노드를 할당
    start_task >> generate_struct_fields_task >> dbt_task


MRT_DBT_DAG_06()
