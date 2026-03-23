build:
	docker compose build --no-cache

run:
	docker compose up -d

restart:
	docker compose restart

clean-all:
	docker compose down  --rmi all --volumes --remove-orphans

clean-v:
	docker compose down  -v

rebuild:
	docker compose down --rmi all --volumes --remove-orphans
	docker compose up -d

