from datetime import datetime, timedelta

from airflow.decorators import dag, task
from airflow.operators.bash import BashOperator


@dag(
    "dbt_vars_dag",
    default_args={
        "depends_on_past": False,
        "retries": 0,
        "retry_delay": timedelta(seconds=5),
    },
    description="dbt 파라미터 테스트 DAG",
    schedule="0 4 * * *",
    start_date=datetime.today() - timedelta(days=5),
    tags=["DEBUG", "TEST", "VARS"],
)
def sample_dag():
    """
    기준일 : 6월 5일
        - 실행시간 : 6월 5일 04:00:00

    data_interval_start_kst : 2025-06-04 04:00:00+09:00
    data_interval_end_kst : 2025-06-05 04:00:00+09:00
    start_date_kst : 2025-06-03
    end_date_kst: 2025-06-04
    logical_start_date_kst : 2025-06-04
    logical_end_date_kst : 2025-06-05
    today_kst : 2025-06-05

    data_interval_start_utc : 2025-06-03 19:00:00+00:00
    data_interval_end_utc : 2025-06-04 19:00:00+00:00
    start_date_utc : 2025-06-02
    end_date_utc : 2025-06-03
    logical_start_date_utc : 2025-06-03
    logical_end_date_utc : 2025-06-04
    today_utc : 2025-06-04
    before_hour_687 : 2025-05-07

    """

    bash = BashOperator(
        task_id="bash-operator",
        bash_command="""
            echo "data_interval_start_kst : {{ data_interval_start.in_timezone('Asia/Seoul') }} "
            echo "data_interval_end_kst : {{ data_interval_end.in_timezone('Asia/Seoul') }} "
            echo "data_interval_start_utc : {{ data_interval_start.in_timezone('UTC') }}"
            echo "data_interval_end_utc : {{ data_interval_end.in_timezone('UTC') }}"
            
            echo "start_date_kst : {{ macros.datetime.strftime((data_interval_start.in_timezone('Asia/Seoul') - macros.timedelta(days=1)), '%Y-%m-%d') }}"
            echo "end_date_kst: {{ macros.datetime.strftime((data_interval_end.in_timezone('Asia/Seoul') - macros.timedelta(days=1)), '%Y-%m-%d') }}"
            echo "start_date_utc : {{ macros.datetime.strftime((data_interval_start.in_timezone('UTC') - macros.timedelta(days=1)), '%Y-%m-%d') }}"
            echo "end_date_utc : {{ macros.datetime.strftime((data_interval_end.in_timezone('UTC') - macros.timedelta(days=1)), '%Y-%m-%d') }}"
            echo "logical_start_date_kst : {{ macros.datetime.strftime((data_interval_start.in_timezone('Asia/Seoul')), '%Y-%m-%d') }}"
            echo "logical_end_date_kst : {{ macros.datetime.strftime((data_interval_end.in_timezone('Asia/Seoul')), '%Y-%m-%d') }}"
            echo "logical_start_date_utc : {{ macros.datetime.strftime((data_interval_start.in_timezone('UTC')), '%Y-%m-%d') }}"
            echo "logical_end_date_utc : {{ macros.datetime.strftime((data_interval_end.in_timezone('UTC')), '%Y-%m-%d') }}"
            echo "today_kst : {{ macros.datetime.strftime(data_interval_end.in_timezone('Asia/Seoul'), '%Y-%m-%d') }}"
            echo "today_utc : {{ macros.datetime.strftime(data_interval_end.in_timezone('UTC'), '%Y-%m-%d') }}"
            
            echo "before_hour_687 : {{ (data_interval_end.in_timezone('UTC') + macros.timedelta(hours=-687)).strftime("%Y-%m-%d") }}"

        """,
    )

    bash


sample_dag()

if __name__ == "__main__":
    sample_dag().test()
