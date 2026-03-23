import hashlib
import json
import logging
import re
from functools import lru_cache
from pathlib import Path

import pendulum
from airflow.hooks.base import BaseHook
from common.consts import SLACK_CONN_ID, SLACK_DBT_ALERT_CHANNEL

try:
    import yaml
except ImportError:  # pragma: no cover - Airflow runtime should include PyYAML, but keep fallback safe.
    yaml = None

REPO_ROOT = Path(__file__).resolve().parents[2]
DBT_PROJECT_ROOT = REPO_ROOT / "mrt_dbt"
DBT_MODELS_ROOT = DBT_PROJECT_ROOT / "models"
DBT_MANIFEST_PATH = DBT_PROJECT_ROOT / "target" / "manifest.json"
GENERIC_TEST_PREFIXES = (
    "accepted_values_",
    "relationships_",
    "not_null_",
    "unique_",
)

connection = BaseHook.get_connection(SLACK_CONN_ID)


def send_alert(context, msg, attachments):
    from airflow.providers.slack.operators.slack import SlackAPIPostOperator

    try:
        alert = SlackAPIPostOperator(
            task_id="dbt-test_alert",
            channel=SLACK_DBT_ALERT_CHANNEL,
            slack_conn_id=SLACK_CONN_ID,
            text=msg,
            attachments=attachments,
        )
        return alert.execute(context=context)
    except Exception as e:
        logging.info(SLACK_DBT_ALERT_CHANNEL, str(e))


def __make_message(context):
    from common.AlertGroup import AlertGroup

    owner = context.get("ti").task.owner
    alert_group = AlertGroup.get(owner)[1]
    return "\n".join(
        (
            f"*Dag*: {context.get('task_instance').dag_id}",
            f"*Owner*: <{alert_group}>",
            f"*Task*: {context.get('task_instance').task_id}",
            f"*Basis Time*: {context.get('logical_date')}",
            f"*Execution Time*: {pendulum.now(tz='Asia/Seoul').format('YYYY-MM-DD HH:mm:ss')}",
            f"*Log Url *: {context.get('task_instance').log_url}",
        )
    )


def slack_failure_alert(context):
    slack_msg = [{"color": "#FA897B", "text": __make_message(context)}]
    return send_alert(context=context, msg=None, attachments=slack_msg)


def slack_success_alert(context):
    slack_msg = [{"color": "#56C596", "text": __make_message(context)}]
    return send_alert(context=context, msg=None, attachments=slack_msg)


def _normalize_schema_name(schema):
    if not schema:
        return "unknown"
    return re.sub(r"_dev$", "", schema)


@lru_cache(maxsize=1)
def _load_model_schema_map():
    model_schema_map = {}
    if not DBT_MODELS_ROOT.exists():
        return model_schema_map

    for sql_path in DBT_MODELS_ROOT.rglob("*.sql"):
        sql = sql_path.read_text(encoding="utf-8")
        schema_match = re.search(r"schema\s*=\s*['\"]([^'\"]+)['\"]", sql)

        if schema_match:
            schema_name = schema_match.group(1)
        elif "models/marts/" in str(sql_path):
            schema_name = "mart"
        elif "models/staging/" in str(sql_path):
            schema_name = "stg"
        else:
            schema_name = "unknown"

        model_schema_map[sql_path.stem] = _normalize_schema_name(schema_name)

    return model_schema_map


def _parse_yaml_test_config(test_config):
    if isinstance(test_config, str):
        return test_config, {}

    if not isinstance(test_config, dict) or not test_config:
        return None, {}

    test_name, kwargs = next(iter(test_config.items()))
    return test_name, kwargs or {}


@lru_cache(maxsize=1)
def _load_yaml_test_metadata():
    if yaml is None or not DBT_MODELS_ROOT.exists():
        return {}

    test_metadata = {}
    model_schema_map = _load_model_schema_map()

    # manifest가 없을 때도 해시형 unique_combination 테스트는 YAML만으로 역매핑 가능함.
    for yaml_path in list(DBT_MODELS_ROOT.rglob("*.yml")) + list(DBT_MODELS_ROOT.rglob("*.yaml")):
        try:
            documents = yaml.safe_load_all(yaml_path.read_text(encoding="utf-8"))
        except Exception as exc:  # pragma: no cover - formatting fallback should not break alerts.
            logging.warning("Failed to load YAML test metadata from %s: %s", yaml_path, exc)
            continue

        for document in documents:
            document = document or {}
            for model in document.get("models", []):
                model_name = model.get("name")
                if not model_name:
                    continue

                for test_config in model.get("data_tests", []) or []:
                    test_name, kwargs = _parse_yaml_test_config(test_config)
                    if test_name not in {"dbt_utils.unique_combination_of_columns", "unique_combination_of_columns"}:
                        continue

                    combination_of_columns = kwargs.get("combination_of_columns") or []
                    if not combination_of_columns:
                        continue

                    generated_name = (
                        f"dbt_utils_unique_combination_of_columns_{model_name}_{'__'.join(combination_of_columns)}"
                    )
                    table_name = f"dbt_utils_unique_combination_o_{hashlib.md5(generated_name.encode()).hexdigest()}"
                    test_metadata[table_name] = {
                        "schema": model_schema_map.get(model_name, "unknown"),
                        "table": model_name,
                        "error": "unique_combination_of_columns",
                        "detail": ", ".join(combination_of_columns),
                    }

    return test_metadata


@lru_cache(maxsize=1)
def _load_manifest_test_metadata():
    if not DBT_MANIFEST_PATH.exists():
        return {}

    try:
        manifest = json.loads(DBT_MANIFEST_PATH.read_text(encoding="utf-8"))
    except Exception as exc:  # pragma: no cover - formatting fallback should not break alerts.
        logging.warning("Failed to load manifest test metadata from %s: %s", DBT_MANIFEST_PATH, exc)
        return {}

    nodes = manifest.get("nodes", {})
    test_metadata = {}
    model_schema_map = _load_model_schema_map()

    for node in nodes.values():
        if node.get("resource_type") != "test" or not node.get("alias"):
            continue

        # singular test는 attached_node가 비어 있을 수 있어 depends_on의 model을 fallback으로 사용함.
        attached_node = node.get("attached_node") or next(
            (dependency for dependency in node.get("depends_on", {}).get("nodes", []) if dependency.startswith("model.")),
            "",
        )
        model_node = nodes.get(attached_node, {})
        model_name = model_node.get("name") or "unknown"
        schema_name = model_schema_map.get(model_name) or _normalize_schema_name(model_node.get("schema"))

        metadata = node.get("test_metadata") or {}
        error_name = metadata.get("name") or node.get("name") or node["alias"]
        detail = node.get("column_name") or ""

        if error_name == "unique_combination_of_columns":
            combination_of_columns = metadata.get("kwargs", {}).get("combination_of_columns") or []
            detail = ", ".join(combination_of_columns)

        test_metadata[node["alias"]] = {
            "schema": schema_name or "unknown",
            "table": model_name,
            "error": error_name,
            "detail": detail,
        }

    return test_metadata


@lru_cache(maxsize=1)
def _load_test_metadata():
    # 정확한 manifest 메타를 우선 사용하고, 없으면 YAML/테이블명 규칙으로 보완함.
    metadata = {}
    metadata.update(_load_yaml_test_metadata())
    metadata.update(_load_manifest_test_metadata())
    return metadata


@lru_cache(maxsize=1)
def _sorted_model_names():
    return sorted(_load_model_schema_map(), key=len, reverse=True)


def _build_failure_metadata_from_generic_name(table_name):
    for test_prefix in GENERIC_TEST_PREFIXES:
        if not table_name.startswith(test_prefix):
            continue

        remainder = table_name[len(test_prefix):]
        # 모델명에도 underscore가 많아 가장 긴 model name부터 매칭해야 컬럼 suffix를 안정적으로 분리할 수 있음.
        for model_name in _sorted_model_names():
            if remainder != model_name and not remainder.startswith(f"{model_name}_"):
                continue

            detail = remainder[len(model_name):].lstrip("_")
            if test_prefix == "accepted_values_":
                detail = detail.split("__", 1)[0]

            return {
                "schema": _load_model_schema_map().get(model_name, "unknown"),
                "table": model_name,
                "error": test_prefix.rstrip("_"),
                "detail": detail,
            }

    return None


def _format_failure_line(table_id):
    table_name = table_id.split(".")[-1]
    failure_metadata = _load_test_metadata().get(table_name) or _build_failure_metadata_from_generic_name(table_name)

    if failure_metadata is None:
        failure_metadata = {
            "schema": "unknown",
            "table": "unknown",
            "error": table_name,
            "detail": "",
        }

    detail_suffix = f" ({failure_metadata['detail']})" if failure_metadata["detail"] else ""
    return (
        f"- schema: `{failure_metadata['schema']}`"
        f" | table: `{failure_metadata['table']}`"
        f" | error: `{failure_metadata['error']}`{detail_suffix}"
    )


def dbt_fail_alert(table_ids):
    summary_lines = [_format_failure_line(table_id) for table_id in sorted(table_ids)]
    slack_table = {"text": "*dbt test 실패 요약*\n" + "\n".join(summary_lines)}
    slack_msg = [{"color": "#56C596", "text": slack_table["text"]}]
    return send_alert(context="context", msg=None, attachments=slack_msg)
