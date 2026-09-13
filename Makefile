.PHONY: setup dev test lint format db-reset docker-build docker-up

setup:
	mix setup

dev:
	mix phx.server

test:
	mix test

lint:
	mix compile --warnings-as-errors
	mix credo --strict

format:
	mix format --check-formatted

db-reset:
	mix ecto.reset

docker-build:
	docker build -t dockd:local .

docker-up:
	docker compose up --build
