from enum import Enum

from airflow.exceptions import AirflowException


class AlertGroup(Enum):
    """
    dbt Enum for alert groups
    그릅/이름, ID/TAG
    """

    ALL = ("ALL", "!here")
    DP_TEAM = ("DP", "!dataplatform")
    SEUNGOH = ("SEUNGOH", "@U03BMMC7DHQ")

    @classmethod
    def get(cls, owner: str):
        try:
            return cls[owner.upper()].value
        except:
            return cls["ALL"].value


if __name__ == "__main__":
    alert_group = AlertGroup.get("ALLdd")[1]
    print(f"<{alert_group}>")
