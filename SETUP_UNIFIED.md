# 🚀 AgroSolutions - Setup Unificado

Guia completo para rodar as **três soluções na mesma máquina** usando Docker Compose centralizado.

---

## 📋 Visão Geral

Este setup unificado elimina **redundâncias** e **conflitos de porta** entre os três repositórios:

- **Identity Service** (porta 5001) - Autenticação e gestão de usuários
- **Properties Service** (porta 5002) - Gestão de propriedades rurais
- **API Gateway** (porta 5000) - Ponto de entrada unificado

### Infraestrutura Compartilhada

| Serviço | Porta | Função | Antes | Depois |
|---------|-------|--------|-------|--------|
| **PostgreSQL** | 5432 | Database (3 databases) | 3 instâncias | ✅ 1 instância |
| **Keycloak** | 8080 | Identity Provider | 3 configs | ✅ 1 compartilhado |
| **RabbitMQ** | 5672, 15672 | Message Broker | 3 instâncias | ✅ 1 instância |
| **Prometheus** | 9090 | Métricas | 3 instâncias | ✅ 1 instância |
| **Loki** | 3100 | Logs | 3 instâncias | ✅ 1 instância |
| **Tempo** | 3200 | Traces | 3 instâncias | ✅ 1 instância |
| **Grafana** | 3000 | Dashboard | 3 instâncias | ✅ 1 unificado |
| **OTEL Collector** | 4317, 4318 | Telemetry Gateway | 3 instâncias | ✅ 1 instância |

**Economia de recursos**: ~70% menos containers, sem conflitos de porta!

---

## 🏗️ Estrutura do Projeto

```
/home/kyo1506/Documents/Projects/
├── agrosolutions-service-identity/
│   ├── docker-compose.unified.yml    # ← Docker Compose CENTRALIZADO
│   ├── infra/                        # ← Configurações de infraestrutura
│   │   ├── init-databases.sh         # Script para criar múltiplos DBs
│   │   ├── prometheus.yml            # Config do Prometheus
│   │   ├── otel-collector-config.yml # Config do OTEL Collector
│   │   ├── tempo-config.yml          # Config do Tempo
│   │   ├── grafana-datasources.yml   # Datasources do Grafana
│   │   ├── grafana-dashboards.yml    # Provisionamento de dashboards
│   │   └── rabbitmq-definitions.json # Queues pré-configuradas
│   ├── src/
│   ├── Dockerfile
│   └── ...
├── agrosolutions-service-properties/
│   ├── src/
│   ├── Dockerfile
│   └── ...
└── agrosolutions-api-gateway/
    ├── src/
    ├── Dockerfile
    └── ...
```

---

## 🔧 Pré-requisitos

- **Docker** 24.0+ com BuildKit habilitado
- **Docker Compose** 2.20+
- **Git**
- **8GB RAM** disponível (mínimo)
- **20GB disco** disponível

### Verificar Instalação

```bash
docker --version
docker compose version
docker info | grep "BuildKit"
```

---

## 📥 Setup Inicial

### 1. Clonar os Três Repositórios

```bash
cd ~/Documents/Projects

# Identity Service (já clonado)
cd agrosolutions-service-identity

# Properties Service
cd ..
git clone https://github.com/kyo1506/agrosolutions-service-properties.git

# API Gateway
git clone https://github.com/kyo1506/agrosolutions-api-gateway.git

# Voltar para Identity (onde está o compose unificado)
cd agrosolutions-service-identity
```

### 2. Dar Permissão ao Script de Init

```bash
chmod +x infra/init-databases.sh
```

### 3. Validar Estrutura de Pastas

```bash
ls -la ../agrosolutions-service-identity
ls -la ../agrosolutions-service-properties
ls -la ../agrosolutions-api-gateway
```

**Todos devem existir e ter um `Dockerfile` válido.**

---

## 🚀 Subir o Ambiente Completo

### Comando Único

```bash
docker compose -f docker-compose.unified.yml up -d
```

### Subir com Build Forçado

```bash
docker compose -f docker-compose.unified.yml up -d --build
```

### Acompanhar Logs em Tempo Real

```bash
# Todos os serviços
docker compose -f docker-compose.unified.yml logs -f

# Apenas microsserviços
docker compose -f docker-compose.unified.yml logs -f identity-api properties-api api-gateway

# Apenas infraestrutura
docker compose -f docker-compose.unified.yml logs -f postgres keycloak rabbitmq
```

---

## ✅ Validação do Setup

### 1. Verificar Status dos Containers

```bash
docker compose -f docker-compose.unified.yml ps
```

**Esperado**: Todos com status `healthy` ou `running`.

### 2. Health Checks

```bash
# Identity Service
curl http://localhost:5001/health

# Properties Service
curl http://localhost:5002/health

# API Gateway
curl http://localhost:5000/health

# Keycloak
curl http://localhost:8080/health/ready

# RabbitMQ Management UI
open http://localhost:15672  # user: guest, pass: guest

# Grafana
open http://localhost:3000   # user: admin, pass: admin
```

### 3. Verificar Databases

```bash
docker exec -it agrosolutions-postgres psql -U postgres -l
```

**Esperado**: 3 databases criados: `keycloak`, `properties`, `outbox`.

### 4. Verificar Queues no RabbitMQ

Acesse: http://localhost:15672/#/queues

**Esperado**:
- `identity-events` (quorum queue)
- `identity-events-dlq` (dead-letter queue)
- `produtor-sync-queue` (quorum queue)
- `status-changed-queue` (quorum queue)

---

## 🌐 Endpoints Disponíveis

### Microsserviços

| Serviço | Endpoint Base | Documentação API |
|---------|---------------|------------------|
| **Identity API** | http://localhost:5001 | http://localhost:5001/scalar/v1 |
| **Properties API** | http://localhost:5002 | http://localhost:5002/scalar/v1 |
| **API Gateway** | http://localhost:5000 | http://localhost:5000/swagger |

### Infraestrutura

| Serviço | URL | Credenciais |
|---------|-----|-------------|
| **Keycloak Admin** | http://localhost:8080 | admin / admin |
| **RabbitMQ Management** | http://localhost:15672 | guest / guest |
| **Grafana** | http://localhost:3000 | admin / admin |
| **Prometheus** | http://localhost:9090 | N/A |
| **Loki** | http://localhost:3100 | N/A |
| **Tempo** | http://localhost:3200 | N/A |

---

## 🧪 Testando a Integração Completa

### 1. Criar Usuário no Identity

```bash
curl -X POST http://localhost:5001/v1/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "produtor01",
    "email": "produtor@example.com",
    "password": "Test@123",
    "firstName": "João",
    "lastName": "Silva",
    "role": "produtor"
  }'
```

### 2. Verificar Evento Publicado

Acesse RabbitMQ UI: http://localhost:15672/#/queues/%2F/produtor-sync-queue

**Esperado**: 1 mensagem na fila `produtor-sync-queue`.

### 3. Verificar Sincronização no Properties

```bash
curl http://localhost:5002/v1/produtores
```

**Esperado**: Produtor `produtor01` aparece na lista (sincronizado via RabbitMQ).

### 4. Acessar via Gateway

```bash
# Login via Gateway
curl -X POST http://localhost:5000/identity/v1/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "produtor@example.com",
    "password": "Test@123"
  }'

# Usar token retornado para acessar Properties
curl http://localhost:5000/gestao/v1/produtores \
  -H "Authorization: Bearer <TOKEN>"
```

---

## 📊 Observability Dashboard

### Grafana - Dashboard Unificado

1. Acesse: http://localhost:3000
2. Login: `admin` / `admin`
3. Navegue: **Explore** → Selecione datasource:
   - **Prometheus**: Métricas de todos os serviços
   - **Loki**: Logs agregados
   - **Tempo**: Traces distribuídos

### Queries Úteis

**Prometheus (Métricas)**
```promql
# Request rate por serviço
rate(http_requests_received_total[5m])

# Latência P95
histogram_quantile(0.95, http_request_duration_seconds_bucket)

# Circuit breaker aberto
events_failed_total{reason="BrokenCircuitException"}
```

**Loki (Logs)**
```logql
# Logs de erro de todos os serviços
{service=~"identity-api|properties-api|api-gateway"} |= "error" | json

# Requests com CorrelationId específico
{service="identity-api"} | json | CorrelationId="abc123"
```

**Tempo (Traces)**
- Buscar por `service.name = "identity-api"`
- Filtrar por duração: `duration > 500ms`
- Ver dependency graph: **Service Graph**

---

## 🛠️ Comandos Úteis

### Gerenciamento

```bash
# Parar tudo
docker compose -f docker-compose.unified.yml stop

# Reiniciar serviço específico
docker compose -f docker-compose.unified.yml restart identity-api

# Rebuild sem cache
docker compose -f docker-compose.unified.yml build --no-cache identity-api

# Remover tudo (CUIDADO: apaga volumes)
docker compose -f docker-compose.unified.yml down -v

# Ver uso de recursos
docker stats
```

### Debug

```bash
# Acessar container
docker exec -it identity-api sh

# Logs de um serviço com timestamp
docker compose -f docker-compose.unified.yml logs -f -t identity-api

# Inspecionar network
docker network inspect agrosolutions-network

# Ver variáveis de ambiente
docker exec identity-api env
```

### Database

```bash
# Acessar PostgreSQL
docker exec -it agrosolutions-postgres psql -U postgres

# Conectar em database específico
docker exec -it agrosolutions-postgres psql -U postgres -d properties

# Backup de database
docker exec agrosolutions-postgres pg_dump -U postgres properties > backup_properties.sql

# Restore
docker exec -i agrosolutions-postgres psql -U postgres properties < backup_properties.sql
```

---

## 🚨 Troubleshooting

### Problema: Containers não sobem

**Causa**: Conflito de porta ou falta de recursos.

**Solução**:
```bash
# Verificar portas em uso
sudo lsof -i :5000,5001,5002,8080,5672,3000,9090

# Aumentar Docker memory limit
docker info | grep "Total Memory"
# Ajustar em Docker Desktop: Settings > Resources > Memory (aumentar para 8GB)

# Limpar containers antigos
docker system prune -a --volumes
```

### Problema: Database não inicializa

**Causa**: Script de init sem permissão ou volume corrompido.

**Solução**:
```bash
# Remover volume do postgres
docker volume rm agrosolutions-service-identity_postgres_data

# Dar permissão ao script
chmod +x infra/init-databases.sh

# Recriar
docker compose -f docker-compose.unified.yml up -d postgres
```

### Problema: Keycloak não aceita conexões

**Causa**: Demora na inicialização (até 90s).

**Solução**:
```bash
# Aguardar health check
docker compose -f docker-compose.unified.yml ps keycloak

# Ver logs de inicialização
docker compose -f docker-compose.unified.yml logs -f keycloak

# Aguardar até ver: "Keycloak 26.5.2 started"
```

### Problema: RabbitMQ sem queues

**Causa**: Definitions JSON não carregado.

**Solução**:
```bash
# Recriar RabbitMQ com definitions
docker compose -f docker-compose.unified.yml up -d --force-recreate rabbitmq

# Verificar logs
docker compose -f docker-compose.unified.yml logs rabbitmq | grep "definitions"
```

### Problema: OTEL Collector não recebe traces

**Causa**: Endpoint incorreto ou firewall bloqueando porta 4317.

**Solução**:
```bash
# Verificar health do collector
curl http://localhost:13133/

# Testar envio de trace
curl -X POST http://localhost:4318/v1/traces \
  -H "Content-Type: application/json" \
  -d '{"resourceSpans":[]}'

# Ver logs do collector
docker compose -f docker-compose.unified.yml logs -f otel-collector
```

---

## 🔒 Produção - Ajustes Necessários

⚠️ **Este setup é para DESENVOLVIMENTO**. Para produção:

### 1. Secrets Management

Substituir variáveis hardcoded por secrets:

```yaml
# Em vez de:
- POSTGRES_PASSWORD=postgres

# Usar:
secrets:
  - postgres_password
environment:
  - POSTGRES_PASSWORD_FILE=/run/secrets/postgres_password
```

### 2. TLS/SSL

Habilitar HTTPS em todos os endpoints:

```yaml
# Adicionar certificados
volumes:
  - ./certs/server.crt:/etc/ssl/certs/server.crt:ro
  - ./certs/server.key:/etc/ssl/private/server.key:ro
```

### 3. Resource Limits

Definir limites de CPU/memória:

```yaml
identity-api:
  deploy:
    resources:
      limits:
        cpus: '1'
        memory: 512M
      reservations:
        cpus: '0.5'
        memory: 256M
```

### 4. Health Checks Robustos

Aumentar timeouts e retries:

```yaml
healthcheck:
  interval: 60s
  timeout: 10s
  retries: 5
  start_period: 120s
```

### 5. Logs Externos

Configurar log drivers para enviar logs para sistema externo:

```yaml
logging:
  driver: syslog
  options:
    syslog-address: "tcp://log-server:514"
```

---

## 📚 Próximos Passos

1. ✅ Configurar realm no Keycloak (importar JSON de config)
2. ✅ Criar dashboards customizados no Grafana
3. ✅ Configurar alertas no Prometheus
4. ✅ Implementar backup automático dos databases
5. ✅ Deploy em Kubernetes (arquivos k8s/ separados)

---

## 📄 Arquivos de Referência

- [docker-compose.unified.yml](./docker-compose.unified.yml) - Compose centralizado
- [infra/prometheus.yml](./infra/prometheus.yml) - Configuração do Prometheus
- [infra/otel-collector-config.yml](./infra/otel-collector-config.yml) - OTEL Collector
- [infra/tempo-config.yml](./infra/tempo-config.yml) - Tempo tracing
- [infra/grafana-datasources.yml](./infra/grafana-datasources.yml) - Datasources Grafana
- [infra/rabbitmq-definitions.json](./infra/rabbitmq-definitions.json) - Queues RabbitMQ

---

## 🤝 Suporte

**Encontrou um problema?**
1. Verificar logs: `docker compose -f docker-compose.unified.yml logs -f`
2. Consultar [Troubleshooting](#-troubleshooting)
3. Abrir issue no repositório

---

**AgroSolutions** - Agricultura 4.0 🌱
