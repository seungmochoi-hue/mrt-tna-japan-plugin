import os
from pathlib import Path

from airflow.models import Variable
from cosmos import ProfileConfig
from cosmos.profiles import GoogleCloudServiceAccountDictProfileMapping

DEFAULT_DBT_ROOT_PATH = Path(__file__).parent.parent.parent / "mrt_dbt"
DBT_ROOT_PATH = Path(os.getenv("DBT_ROOT_PATH", DEFAULT_DBT_ROOT_PATH))
EXECUTE_PATH = Path("/opt/airflow/dbt_venv/bin/dbt")


def dbt_profile_config():
    # ENV : prod, dev
    target_name = Variable.get("ENV", "dev")
    return ProfileConfig(
        profile_name="mrt-dp-dbt",
        target_name=target_name,
        profile_mapping=dbt_profile_mapping(),
    )


def dbt_profile_mapping():
    # dataset : edw_dbt
    dataset = Variable.get("dataset", "temp")
    profile_mapping = GoogleCloudServiceAccountDictProfileMapping(
        conn_id="bigquery_default",
        profile_args={
            "project": "mrtdata",
            "dataset": dataset,
            "location": "asia-northeast3",
        },
    )
    return profile_mapping


if __name__ == "__main__":
    dbt_profile_config()
