# ──────────────────────────────────────────────────────────────────────────────
#  NexusPlatform · local-data-stack · Makefile
# ──────────────────────────────────────────────────────────────────────────────
#  The contract between a developer and this repository.
#
#    make up              bring up default (full) stack
#    make up P=minimal    bring up a profile subset
#    make down            tear down, keep volumes
#    make nuke            tear down + drop all volumes (destructive)
#    make ps              show container state
#    make logs S=kafka    tail logs for one service
#    make health          probe every service's healthcheck
#    make smoke           run end-to-end smoke test (produce→consume→query)
#    make validate        docker compose config (lint + render)
#    make fmt             format YAML/JSON
#    make urls            print the list of UIs
# ──────────────────────────────────────────────────────────────────────────────

SHELL        := /usr/bin/env bash
.DEFAULT_GOAL := help

COMPOSE_DIR  := compose
COMPOSE      := docker compose --project-directory $(COMPOSE_DIR) -f $(COMPOSE_DIR)/docker-compose.yml
P            ?= full
S            ?=

# ─── Core lifecycle ──────────────────────────────────────────────────────────

.PHONY: up
up: ## Bring up the stack. Override profile with P=minimal|streaming|analytics|observability|full
	$(COMPOSE) --profile $(P) up -d --remove-orphans
	@$(MAKE) --no-print-directory urls

.PHONY: down
down: ## Stop the stack, keep volumes
	$(COMPOSE) --profile full down --remove-orphans

.PHONY: nuke
nuke: ## DESTRUCTIVE: stop stack and wipe all named volumes
	$(COMPOSE) --profile full down --remove-orphans --volumes

.PHONY: restart
restart: down up ## Down then up

.PHONY: pull
pull: ## Pull latest pinned images
	$(COMPOSE) --profile full pull

# ─── Inspection ──────────────────────────────────────────────────────────────

.PHONY: ps
ps: ## List running services
	$(COMPOSE) ps

.PHONY: logs
logs: ## Tail logs. Use S=<service> to target one.
	@if [ -z "$(S)" ]; then $(COMPOSE) logs -f --tail=200; \
	else $(COMPOSE) logs -f --tail=200 $(S); fi

.PHONY: health
health: ## Print docker healthcheck state for every container
	@$(COMPOSE) ps --format json \
		| jq -r '.Name + "\t" + .State + "\t" + (.Health // "n/a")' \
		| column -t

.PHONY: urls
urls: ## Print local UI URLs
	@echo ""
	@echo "  NexusPlatform · local-data-stack"
	@echo "  ─────────────────────────────────"
	@echo "  Grafana           http://127.0.0.1:3000      (admin / admin)"
	@echo "  Prometheus        http://127.0.0.1:9090"
	@echo "  Jaeger            http://127.0.0.1:16686"
	@echo "  Seq               http://127.0.0.1:5341"
	@echo "  ClickHouse HTTP   http://127.0.0.1:8123      (nexus / nexus-dev)"
	@echo "  Schema Registry   http://127.0.0.1:8081"
	@echo "  Kafka (external)  127.0.0.1:9094"
	@echo "  OTLP gRPC         127.0.0.1:4317"
	@echo "  OTLP HTTP         127.0.0.1:4318"
	@echo ""

# ─── Quality gates ───────────────────────────────────────────────────────────

.PHONY: validate
validate: ## docker compose config (schema + render)
	$(COMPOSE) --profile full config -q
	@echo "OK: compose file is valid."

.PHONY: smoke
smoke: ## End-to-end smoke test (expects 'full' profile up)
	@bash scripts/smoke.sh

.PHONY: fmt
fmt: ## Format YAML/JSON with prettier (requires npx)
	npx --yes prettier --write "$(COMPOSE_DIR)/**/*.{yml,yaml,json}"

# ─── Meta ────────────────────────────────────────────────────────────────────

.PHONY: help
help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nTargets:\n"} /^[a-zA-Z0-9_-]+:.*##/ { printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo ""
