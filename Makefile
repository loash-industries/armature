# =============================================================================
# Armature — Development Makefile
# =============================================================================

COMPOSE_DEV = docker compose -f docker-compose.dev.yml
COMPOSE     = docker compose
WORLD_DIR   = .world-contracts
WORLD_REPO  = https://github.com/evefrontier/world-contracts.git
WORLD_REF   = main

.PHONY: dev dev-up dev-down dev-reset dev-logs dev-ps \
        dev-deps db db-down \
        deploy-world deploy-armature \
        clean help

# ── Full-Stack Dev Environment ────────────────────────────────────────────────

## Start the full dev stack (sui-localnet + world + armature + ui + postgres)
dev: dev-deps docker/.env
	$(COMPOSE_DEV) up --build

## Start in detached mode
dev-up: dev-deps docker/.env
	$(COMPOSE_DEV) up --build -d

## Stop all dev services
dev-down:
	$(COMPOSE_DEV) down

## Wipe all volumes and redeploy from scratch
dev-reset:
	$(COMPOSE_DEV) down -v --remove-orphans
	@echo "Volumes wiped. Run 'make dev' to redeploy."

## Tail logs for all services
dev-logs:
	$(COMPOSE_DEV) logs -f

## Show running services
dev-ps:
	$(COMPOSE_DEV) ps

# ── Dependencies ──────────────────────────────────────────────────────────────

## Clone world-contracts and create docker/.env if needed
dev-deps: $(WORLD_DIR) docker/.env

$(WORLD_DIR):
	@echo "Cloning world-contracts@$(WORLD_REF)..."
	git clone --depth 1 --branch $(WORLD_REF) $(WORLD_REPO) $(WORLD_DIR)

## Update world-contracts to latest
dev-deps-update:
	cd $(WORLD_DIR) && git fetch origin && git reset --hard origin/$(WORLD_REF)

# ── Individual Services ───────────────────────────────────────────────────────

## Start only PostgreSQL (for local indexer development)
db:
	$(COMPOSE) up -d

## Stop PostgreSQL
db-down:
	$(COMPOSE) down

# ── Deploy Steps (for re-running individually) ───────────────────────────────

## Re-run world-contracts deployment only
deploy-world:
	$(COMPOSE_DEV) up world-deploy

## Re-run armature deployment only
deploy-armature:
	$(COMPOSE_DEV) up armature-deploy

# ── Setup ─────────────────────────────────────────────────────────────────────

## Create docker/.env from example if it doesn't exist
docker/.env:
	@if [ ! -f docker/.env ]; then \
		cp docker/.env.example docker/.env; \
		echo "Created docker/.env from docker/.env.example"; \
		echo "Edit docker/.env if you need custom values, then run 'make dev' again."; \
	fi

## Remove all Docker volumes and build artifacts
clean:
	$(COMPOSE_DEV) down -v --remove-orphans 2>/dev/null || true
	$(COMPOSE) down -v 2>/dev/null || true
	rm -f docker/.env
	rm -rf $(WORLD_DIR)
	@echo "Cleaned."

# ── Help ──────────────────────────────────────────────────────────────────────

## Show this help
help:
	@echo "Armature Development Targets:"
	@echo ""
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## /  /'
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@echo "Quick start:"
	@echo "  make dev        — start everything"
	@echo "  make dev-logs   — tail all logs"
	@echo "  make dev-reset  — wipe and restart"
