.PHONY: help setup dev test lint format check db-reset docker-build docker-up docker-down

help:
	@printf '%s\n' 'Comandos:' '  setup        instala dependências e prepara o banco' '  dev          inicia o servidor nativo' '  test         executa os testes' '  lint         compila e roda Credo' '  format       formata o código' '  check        executa todas as validações' '  db-reset     recria o banco' '  docker-build constrói a imagem de produção' '  docker-up    inicia o ambiente local' '  docker-down  para e remove o ambiente local'

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
	mix format

check:
	mix precommit

db-reset:
	mix ecto.reset

docker-build:
	docker build -t dockd:local .

docker-up:
	docker compose up --build

docker-down:
	docker compose down -v --remove-orphans
