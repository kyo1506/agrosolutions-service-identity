.PHONY: help up down restart logs status health clean backup restore

# AgroSolutions - Unified Docker Compose Makefile
# Facilita gerenciamento dos três serviços na mesma máquina

COMPOSE_FILE := docker-compose.unified.yml
PROJECT_NAME := agrosolutions

help: ## Mostra esta mensagem de ajuda
	@echo "AgroSolutions - Comandos Disponíveis:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# =============================================================================
# COMANDOS PRINCIPAIS
# =============================================================================

up: ## Sobe todos os serviços (infraestrutura + microsserviços)
	@echo "🚀 Subindo AgroSolutions Stack..."
	docker compose -f $(COMPOSE_FILE) up -d
	@echo "✅ Stack iniciada! Aguarde health checks (~2 minutos)"
	@echo "   Monitore: make logs"

up-infra: ## Sobe apenas infraestrutura (Postgres, Keycloak, RabbitMQ, Observability)
	@echo "🏗️  Subindo infraestrutura..."
	docker compose -f $(COMPOSE_FILE) up -d postgres keycloak rabbitmq prometheus loki tempo grafana otel-collector

up-services: ## Sobe apenas microsserviços (Identity, Properties, Gateway)
	@echo "🚀 Subindo microsserviços..."
	docker compose -f $(COMPOSE_FILE) up -d identity-api properties-api api-gateway

down: ## Para e remove todos os containers (mantém volumes)
	@echo "🛑 Parando AgroSolutions Stack..."
	docker compose -f $(COMPOSE_FILE) down
	@echo "✅ Stack parada!"

down-volumes: ## Para e remove TUDO incluindo volumes (CUIDADO: apaga dados!)
	@echo "⚠️  Removendo TUDO (containers + volumes)..."
	@read -p "Tem certeza? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		docker compose -f $(COMPOSE_FILE) down -v; \
		echo "✅ Tudo removido!"; \
	else \
		echo "❌ Cancelado"; \
	fi

restart: ## Reinicia todos os serviços
	@echo "🔄 Reiniciando stack..."
	docker compose -f $(COMPOSE_FILE) restart
	@echo "✅ Stack reiniciada!"

restart-services: ## Reinicia apenas os microsserviços
	docker compose -f $(COMPOSE_FILE) restart identity-api properties-api api-gateway

# =============================================================================
# LOGS E MONITORAMENTO
# =============================================================================

logs: ## Mostra logs de todos os serviços (seguindo)
	docker compose -f $(COMPOSE_FILE) logs -f

logs-identity: ## Logs do Identity Service
	docker compose -f $(COMPOSE_FILE) logs -f identity-api

logs-properties: ## Logs do Properties Service
	docker compose -f $(COMPOSE_FILE) logs -f properties-api

logs-gateway: ## Logs do API Gateway
	docker compose -f $(COMPOSE_FILE) logs -f api-gateway

logs-infra: ## Logs da infraestrutura (Postgres, Keycloak, RabbitMQ)
	docker compose -f $(COMPOSE_FILE) logs -f postgres keycloak rabbitmq

logs-observability: ## Logs da stack de observabilidade
	docker compose -f $(COMPOSE_FILE) logs -f prometheus loki tempo grafana otel-collector

status: ## Mostra status de todos os containers
	@echo "📊 Status dos Containers:"
	@docker compose -f $(COMPOSE_FILE) ps

status-json: ## Status em formato JSON (útil para scripts)
	@docker compose -f $(COMPOSE_FILE) ps --format json

# =============================================================================
# HEALTH CHECKS
# =============================================================================

health: ## Verifica saúde de todos os serviços
	@echo "🏥 Health Checks:"
	@echo ""
	@echo "📌 Identity Service:"
	@curl -sf http://localhost:5001/health | jq . || echo "❌ Identity UNHEALTHY"
	@echo ""
	@echo "📌 Properties Service:"
	@curl -sf http://localhost:5002/health | jq . || echo "❌ Properties UNHEALTHY"
	@echo ""
	@echo "📌 API Gateway:"
	@curl -sf http://localhost:5000/health | jq . || echo "❌ Gateway UNHEALTHY"
	@echo ""
	@echo "📌 Keycloak:"
	@curl -sf http://localhost:8080/health/ready | jq . || echo "❌ Keycloak UNHEALTHY"
	@echo ""
	@echo "📌 RabbitMQ:"
	@curl -sf http://localhost:15672/api/healthchecks/node -u guest:guest | jq . || echo "❌ RabbitMQ UNHEALTHY"

health-infra: ## Health check apenas da infraestrutura
	@echo "🏥 Infraestrutura:"
	@docker exec agrosolutions-postgres pg_isready -U postgres && echo "✅ Postgres OK" || echo "❌ Postgres FAIL"
	@curl -sf http://localhost:8080/health/ready >/dev/null && echo "✅ Keycloak OK" || echo "❌ Keycloak FAIL"
	@docker exec agrosolutions-rabbitmq rabbitmq-diagnostics ping >/dev/null && echo "✅ RabbitMQ OK" || echo "❌ RabbitMQ FAIL"

# =============================================================================
# BUILD E DEPLOY
# =============================================================================

build: ## Build de todas as imagens (sem cache)
	@echo "🔨 Building todas as imagens..."
	docker compose -f $(COMPOSE_FILE) build --no-cache

build-identity: ## Build apenas Identity Service
	docker compose -f $(COMPOSE_FILE) build --no-cache identity-api

build-properties: ## Build apenas Properties Service
	docker compose -f $(COMPOSE_FILE) build --no-cache properties-api

build-gateway: ## Build apenas API Gateway
	docker compose -f $(COMPOSE_FILE) build --no-cache api-gateway

rebuild: down build up ## Rebuild completo: para → build → sobe

# =============================================================================
# DATABASE
# =============================================================================

db-shell: ## Acessa shell do PostgreSQL
	docker exec -it agrosolutions-postgres psql -U postgres

db-list: ## Lista todos os databases
	@docker exec agrosolutions-postgres psql -U postgres -c "\l"

db-connect-keycloak: ## Conecta no database do Keycloak
	docker exec -it agrosolutions-postgres psql -U postgres -d keycloak

db-connect-properties: ## Conecta no database do Properties
	docker exec -it agrosolutions-postgres psql -U postgres -d properties

db-connect-outbox: ## Conecta no database do Outbox (Identity)
	docker exec -it agrosolutions-postgres psql -U postgres -d outbox

# =============================================================================
# BACKUP E RESTORE
# =============================================================================

backup: ## Backup completo de todos os databases
	@echo "💾 Criando backup..."
	@mkdir -p backups
	@docker exec agrosolutions-postgres pg_dumpall -U postgres | gzip > backups/backup_$$(date +%Y%m%d_%H%M%S).sql.gz
	@echo "✅ Backup salvo em: backups/backup_$$(date +%Y%m%d_%H%M%S).sql.gz"

backup-keycloak: ## Backup apenas do Keycloak
	@mkdir -p backups
	@docker exec agrosolutions-postgres pg_dump -U postgres keycloak | gzip > backups/keycloak_$$(date +%Y%m%d_%H%M%S).sql.gz

backup-properties: ## Backup apenas do Properties
	@mkdir -p backups
	@docker exec agrosolutions-postgres pg_dump -U postgres properties | gzip > backups/properties_$$(date +%Y%m%d_%H%M%S).sql.gz

restore: ## Restaura backup (use: make restore FILE=backups/backup_xxx.sql.gz)
	@if [ -z "$(FILE)" ]; then \
		echo "❌ Erro: especifique o arquivo com FILE="; \
		echo "   Exemplo: make restore FILE=backups/backup_20240131.sql.gz"; \
		exit 1; \
	fi
	@echo "⚠️  Restaurando backup: $(FILE)"
	@gunzip < $(FILE) | docker exec -i agrosolutions-postgres psql -U postgres
	@echo "✅ Restore concluído!"

# =============================================================================
# OBSERVABILITY
# =============================================================================

open-grafana: ## Abre Grafana no browser
	@open http://localhost:3000 || xdg-open http://localhost:3000

open-prometheus: ## Abre Prometheus no browser
	@open http://localhost:9090 || xdg-open http://localhost:9090

open-rabbitmq: ## Abre RabbitMQ Management no browser
	@open http://localhost:15672 || xdg-open http://localhost:15672

open-keycloak: ## Abre Keycloak Admin Console no browser
	@open http://localhost:8080 || xdg-open http://localhost:8080

open-identity: ## Abre Identity API docs no browser
	@open http://localhost:5001/scalar/v1 || xdg-open http://localhost:5001/scalar/v1

open-properties: ## Abre Properties API docs no browser
	@open http://localhost:5002/scalar/v1 || xdg-open http://localhost:5002/scalar/v1

open-gateway: ## Abre Gateway swagger no browser
	@open http://localhost:5000/swagger || xdg-open http://localhost:5000/swagger

# =============================================================================
# LIMPEZA
# =============================================================================

clean: ## Remove containers, volumes órfãos e networks não utilizadas
	@echo "🧹 Limpando recursos..."
	docker compose -f $(COMPOSE_FILE) down
	docker volume prune -f
	docker network prune -f
	@echo "✅ Limpeza concluída!"

clean-all: ## Limpeza COMPLETA (containers, volumes, imagens, build cache)
	@echo "⚠️  LIMPEZA COMPLETA - Removerá TUDO!"
	@read -p "Tem certeza? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		docker compose -f $(COMPOSE_FILE) down -v --rmi all; \
		docker system prune -a -f --volumes; \
		echo "✅ Limpeza completa realizada!"; \
	else \
		echo "❌ Cancelado"; \
	fi

# =============================================================================
# TESTES
# =============================================================================

test-integration: ## Testa integração completa (cria usuário, verifica sincronização)
	@echo "🧪 Testando integração Identity → Properties..."
	@echo ""
	@echo "1️⃣  Criando usuário no Identity..."
	@curl -X POST http://localhost:5001/v1/register \
		-H "Content-Type: application/json" \
		-d '{"username":"teste_$(shell date +%s)","email":"teste@example.com","password":"Test@123","firstName":"Teste","lastName":"Integração","role":"produtor"}' \
		| jq .
	@echo ""
	@echo "2️⃣  Aguardando 5s para sincronização..."
	@sleep 5
	@echo ""
	@echo "3️⃣  Verificando produtores no Properties..."
	@curl -s http://localhost:5002/v1/produtores | jq .
	@echo ""
	@echo "✅ Teste concluído!"

test-health: health ## Alias para health

# =============================================================================
# DESENVOLVIMENTO
# =============================================================================

dev-identity: ## Sobe apenas Identity + infra necessária
	docker compose -f $(COMPOSE_FILE) up -d postgres keycloak rabbitmq otel-collector identity-api

dev-properties: ## Sobe apenas Properties + infra necessária
	docker compose -f $(COMPOSE_FILE) up -d postgres keycloak rabbitmq otel-collector properties-api

dev-gateway: ## Sobe apenas Gateway + infra necessária
	docker compose -f $(COMPOSE_FILE) up -d keycloak identity-api properties-api api-gateway

shell-identity: ## Acessa shell do container Identity
	docker exec -it identity-api sh

shell-properties: ## Acessa shell do container Properties
	docker exec -it properties-api sh

shell-gateway: ## Acessa shell do container Gateway
	docker exec -it api-gateway sh

env-identity: ## Mostra variáveis de ambiente do Identity
	@docker exec identity-api env | sort

env-properties: ## Mostra variáveis de ambiente do Properties
	@docker exec properties-api env | sort

env-gateway: ## Mostra variáveis de ambiente do Gateway
	@docker exec api-gateway env | sort

# =============================================================================
# MONITORAMENTO AVANÇADO
# =============================================================================

metrics: ## Mostra métricas de uso de recursos
	@echo "📈 Uso de Recursos:"
	@docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" \
		$$(docker compose -f $(COMPOSE_FILE) ps -q)

network-inspect: ## Inspeciona a network compartilhada
	@docker network inspect agrosolutions-network | jq .

volumes-list: ## Lista todos os volumes criados
	@docker volume ls | grep $(PROJECT_NAME)

volumes-size: ## Mostra tamanho dos volumes
	@echo "💾 Tamanho dos Volumes:"
	@docker system df -v | grep $(PROJECT_NAME)

# =============================================================================
# CI/CD
# =============================================================================

ci-validate: ## Valida configuração do docker-compose (CI)
	docker compose -f $(COMPOSE_FILE) config --quiet

ci-build: ## Build para CI (com cache)
	docker compose -f $(COMPOSE_FILE) build

ci-test: up test-health test-integration ## Pipeline completo de CI

# =============================================================================
# UTILITÁRIOS
# =============================================================================

version: ## Mostra versões de todos os componentes
	@echo "📦 Versões:"
	@echo "Docker:        $$(docker --version)"
	@echo "Docker Compose: $$(docker compose version)"
	@docker compose -f $(COMPOSE_FILE) images

update-images: ## Atualiza todas as imagens base
	@echo "⬇️  Atualizando imagens..."
	docker compose -f $(COMPOSE_FILE) pull
	@echo "✅ Imagens atualizadas!"

port-check: ## Verifica se todas as portas necessárias estão livres
	@echo "🔍 Verificando portas..."
	@for port in 5000 5001 5002 5432 8080 5672 15672 9090 3000 3100 3200 4317 4318; do \
		if lsof -Pi :$$port -sTCP:LISTEN -t >/dev/null 2>&1; then \
			echo "❌ Porta $$port em uso!"; \
		else \
			echo "✅ Porta $$port livre"; \
		fi; \
	done

prerequisites: ## Verifica pré-requisitos do sistema
	@echo "✅ Verificando pré-requisitos..."
	@command -v docker >/dev/null 2>&1 && echo "✅ Docker instalado" || echo "❌ Docker não encontrado"
	@command -v docker compose >/dev/null 2>&1 && echo "✅ Docker Compose instalado" || echo "❌ Docker Compose não encontrado"
	@command -v jq >/dev/null 2>&1 && echo "✅ jq instalado" || echo "⚠️  jq não encontrado (opcional)"
	@command -v curl >/dev/null 2>&1 && echo "✅ curl instalado" || echo "❌ curl não encontrado"
	@echo ""
	@echo "📊 Docker Info:"
	@docker info | grep -E "Server Version|Total Memory|CPUs"

# =============================================================================
# DEFAULT
# =============================================================================

.DEFAULT_GOAL := help
