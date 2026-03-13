# Makefile
up:
	docker compose up

build:
	docker compose build

down:
	docker compose down

mig:
	docker compose exec api poetry run python manage.py makemigrations
	docker compose exec api poetry run python manage.py migrate

user:
	docker compose exec api poetry run python manage.py createsuperuser

airports:
	docker compose exec api poetry run python manage.py import_airports

stations:
	@read -p "JSON File Path (default: train_stations.json): " file_path; \
	docker compose exec api poetry run python manage.py import_stations $${file_path:-train_stations.json}

shell:
	docker compose exec api poetry run python manage.py shell

db:
	docker compose exec db psql -U mapuser -d mapfriends_db

test:
	docker compose exec api poetry run python manage.py test 2>&1 | tee .gemini/last_test_results.txt

# Poetry helpers
install:
	docker compose exec api poetry install

add:
	@read -p "Package name: " package; \
	docker compose exec api poetry add $$package

update:
	docker compose exec api poetry update
