select ?= all

compile:
	dbt compile --profile mrt_dbt --profiles-dir env --select $(select)

docs:
	dbt docs generate --profile mrt_dbt --profiles-dir env
	dbt docs serve  --profile mrt_dbt --profiles-dir env --port 8001

test:
	dbt test --profile mrt_dbt --profiles-dir env

dev-debug:
	dbt run --profile mrt_dbt --profiles-dir env --debug

clean:
	dbt clean --profile mrt_dbt --profiles-dir env

deps:
	dbt deps --profile mrt_dbt --profiles-dir env