"""
Big Query Connection Class
"""

import logging

import pandas as pd
from airflow.providers.google.cloud.hooks.bigquery import BigQueryHook
from common.consts import BIGQUERY_CONN_ID, DEV_DBT_TEST_AUDIT


class BigQueryConn:
    """
    Class to manage BigQuery connection
    """

    def __init__(self, gcp_conn_id=BIGQUERY_CONN_ID, project_id="mrtdata"):
        self.hook = BigQueryHook(gcp_conn_id=gcp_conn_id)
        self.project_id = project_id
        self.client = self.hook.get_client(project_id=project_id)

    def get_pandas(self, query):
        rows = self.client.query(query).result()
        if rows.total_rows == 0:
            logging.info("No rows found for the query.")
            return pd.DataFrame()
        logging.info(f"Total rows found: {rows.total_rows}")
        df = rows.to_dataframe()
        if df.empty:
            logging.info("DataFrame is empty.")
            return pd.DataFrame()
        logging.info(f"DataFrame shape: {df.shape}")
        return df

    def get_table_list(self, dataset_id=DEV_DBT_TEST_AUDIT) -> list:
        """
        Get the tables in the dataset
        """

        tables = self.client.list_tables(f"{self.project_id}.{dataset_id}")
        table_ids = []
        for table in tables:
            table_id = f"{self.project_id}.{dataset_id}.{table.table_id}"
            logging.info(f" - {table_id}")
            table_ids.append(table_id)
        return table_ids

    def clean_schema_table(self, table_ids: list):
        """
        :return:
        """
        for table_id in table_ids:
            self.client.delete_table(table_id, not_found_ok=True)
            logging.info(f"❌ Deleted: {table_id}")

    def get_table_data(self, table_id: str, limit=3):
        """
        Get the data from the table
        """

        table = self.client.get_table(f"{table_id}")
        rows = self.client.list_rows(table, max_results=limit).to_dataframe()
        if rows.empty:
            return pd.DataFrame()
        return rows

    def get_sql_of_file(self, filePath, kwargs):
        from pathlib import Path

        query = None
        with open(f"{Path(__file__).parent.parent}/{filePath}", "r") as file:
            task = kwargs["task"]
            query = task.render_template(file.read(), kwargs)

        return query
