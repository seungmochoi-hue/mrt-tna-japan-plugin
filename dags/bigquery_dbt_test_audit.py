from datetime import datetime

from airflow.decorators import dag, task
from common.alert import dbt_fail_alert
from common.consts import DEV_DBT_TEST_AUDIT, PROD_DBT_TEST_AUDIT
from utils.BigQueryConn import BigQueryConn


@dag(
    dag_id="BIGQUERY_DBT_TEST_AUDIT",
    schedule_interval="30 9 * * 1-5",
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=["audit", "clean"],
)
def bigquery_dbt_test_audit():
    """
    매주 평일 오전 9시 30분에 실행되는 DAG입니다.
    BigQuery dbt 테스트 실패 결과 알림 및 정리를 수행하는 DAG 입니다.
    """

    @task
    def audit_logs_alert():
        """
        BigQuery dbt 테스트 실패 결과를 알림하는 Task 입니다.
        """
        conn = BigQueryConn()
        table_ids = conn.get_table_list(dataset_id=PROD_DBT_TEST_AUDIT)
        failed_table_ids = []
        if table_ids:
            for table_id in table_ids:
                # 슬랙에는 요약만 보내므로 실패 존재 여부만 확인할 최소 row만 조회함.
                fail_dbt_result = conn.get_table_data(table_id, limit=1)

                if not fail_dbt_result.empty:
                    failed_table_ids.append(table_id)

        if failed_table_ids:
            dbt_fail_alert(failed_table_ids)

    @task
    def clean_bigquery_audit_logs():
        conn = BigQueryConn()
        for dataset_id in [DEV_DBT_TEST_AUDIT, PROD_DBT_TEST_AUDIT]:
            table_ids = conn.get_table_list(dataset_id=dataset_id)
            if table_ids:
                conn.clean_schema_table(table_ids)

    audit_logs_alert() >> clean_bigquery_audit_logs()


bigquery_dbt_test_audit()
