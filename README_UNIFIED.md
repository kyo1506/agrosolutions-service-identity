# 🚀 AgroSolutions - Setup Unificado

## 🎯 Quick Start

```bash
# Clone os três repositórios (se ainda não tiver)
cd ~/Documents/Projects
git clone https://github.com/kyo1506/agrosolutions-service-properties.git
git clone https://github.com/kyo1506/agrosolutions-api-gateway.git

# Voltar para Identity (onde está o compose unificado)
cd agrosolutions-service-identity

# Dar permissão ao script de init
chmod +x infra/init-databases.sh

# Subir TUDO com um comando
make up

# Ou manualmente:
docker compose -f docker-compose.unified.yml up -d

# Acompanhar logs
make logs
```

**Pronto!** Em ~2 minutos todos os serviços estarão rodando. 🎉

---

## 📋 O Que É Este Setup?

Este repositório contém o **Docker Compose Unificado** que roda **3 microsserviços** na mesma máquina:

| Serviço | Porta | Função |
|---------|-------|--------|
| **Identity Service** | 5001 | Autenticação, gestão de usuários |
| **Properties Service** | 5002 | Gestão de propriedades rurais |
| **API Gateway** | 5000 | Ponto de entrada unificado |

### Infraestrutura Compartilhada

| Serviço | Porta | Função |
|---------|-------|--------|
| **PostgreSQL** | 5432 | 3 databases: `keycloak`, `properties`, `outbox` |
| **Keycloak** | 8080 | Identity Provider (OAuth2/OIDC) |
| **RabbitMQ** | 5672 | Message Broker (UI: 15672) |
| **Prometheus** | 9090 | Métricas |
| **Loki** | 3100 | Logs |
| **Tempo** | 3200 | Traces |
| **Grafana** | 3000 | Dashboard unificado |
| **OTEL Collector** | 4317 | Telemetry Gateway |

---

## 🏗️ Estrutura de Arquivos

```
agrosolutions-service-identity/
├── docker-compose.unified.yml    ← Compose PRINCIPAL (roda os 3 serviços)
├── Makefile                      ← Comandos facilitados
├── SETUP_UNIFIED.md              ← Guia completo (650 linhas)
├── MIGRATION_GUIDE.md            ← Como migrar do setup antigo
├── ANALYSIS.md                   ← Análise técnica das redundâncias
├── README_UNIFIED.md             ← Este arquivo
├── infra/                        ← Configurações de infraestrutura
│   ├── init-databases.sh         ← Cria 3 databases no Postgres
│   ├── prometheus.yml            ← Scrape de métricas
│   ├── otel-collector-config.yml ← Gateway de telemetria
│   ├── tempo-config.yml          ← Distributed tracing
│   ├── grafana-datasources.yml   ← Datasources pré-configurados
│   ├── grafana-dashboards.yml    ← Provisionamento
│   └── rabbitmq-definitions.json ← Queues pré-criadas
└── src/                          ← Código do Identity Service
```

---

## 📊 Por Que Unified?

### Antes (3 Composes Separados)

❌ **24 containers** (8 por repositório)  
❌ **21 conflitos de porta** (impossível rodar junto)  
❌ **5.17GB RAM** desperdiçados  
❌ **Observabilidade fragmentada** (3 Grafanas, 3 Prometheus)  
❌ **Mensageria isolada** (eventos não fluem entre services)  
❌ **Backup complexo** (2 PostgreSQL, 3 RabbitMQ)  

### Depois (1 Compose Unificado)

✅ **11 containers** (economia de 54%)  
✅ **0 conflitos de porta**  
✅ **2.56GB RAM** (economia de 51%)  
✅ **Observabilidade unificada** (1 Grafana com todos os services)  
✅ **Mensageria funcional** (Identity → Properties via RabbitMQ)  
✅ **Backup simples** (1 Postgres, 1 RabbitMQ)  

**[Ver análise completa →](./ANALYSIS.md)**

---

## 🚀 Comandos do Makefile

### Principais

```bash
make help              # Mostra todos os comandos disponíveis
make up                # Sobe tudo (infra + microsserviços)
make down              # Para tudo (mantém volumes)
make restart           # Reinicia tudo
make logs              # Logs de todos os serviços
make health            # Health check de todos os serviços
```

### Logs Específicos

```bash
make logs-identity     # Logs do Identity Service
make logs-properties   # Logs do Properties Service
make logs-gateway      # Logs do API Gateway
make logs-infra        # Logs da infraestrutura
```

### Build

```bash
make build             # Build de todas as imagens
make rebuild           # Para → Build → Sobe
make build-identity    # Build apenas Identity
```

### Database

```bash
make db-shell          # Acessa shell do PostgreSQL
make db-list           # Lista databases
make backup            # Backup completo
make restore FILE=...  # Restaura backup
```

### Desenvolvimento

```bash
make dev-identity      # Sobe apenas Identity + infra necessária
make shell-identity    # Acessa shell do container Identity
make env-identity      # Mostra env vars do Identity
```

### Observability

```bash
make open-grafana      # Abre Grafana no browser
make open-prometheus   # Abre Prometheus
make open-rabbitmq     # Abre RabbitMQ Management
make open-keycloak     # Abre Keycloak Admin
```

### Testes

```bash
make test-integration  # Testa fluxo completo (criar usuário → sincronizar)
make test-health       # Health check de tudo
```

### Limpeza

```bash
make clean             # Remove containers e volumes órfãos
make clean-all         # Remove TUDO (cuidado!)
```

**[Ver todos os comandos →](./Makefile)**

---

## ✅ Validando o Setup

### 1. Verificar Containers

```bash
make status

# Esperado: todos com status "Up (healthy)"
```

### 2. Health Checks

```bash
make health

# Ou manualmente:
curl http://localhost:5001/health  # Identity
curl http://localhost:5002/health  # Properties
curl http://localhost:5000/health  # Gateway
```

### 3. Verificar Databases

```bash
make db-list

# Esperado: 3 databases
# - keycloak
# - properties
# - outbox
```

### 4. Verificar Queues no RabbitMQ

Abrir: http://localhost:15672 (user: guest, pass: guest)

**Esperado**:
- `identity-events` (quorum queue)
- `identity-events-dlq`
- `produtor-sync-queue`
- `status-changed-queue`

---

## 🧪 Testando Integração Completa

### Via Makefile (Automático)

```bash
make test-integration
```

### Manual

```bash
# 1. Criar usuário no Identity
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

# 2. Verificar evento no RabbitMQ
# Abrir: http://localhost:15672/#/queues/%2F/produtor-sync-queue
# Deve ter 1 mensagem

# 3. Verificar sincronização no Properties
curl http://localhost:5002/v1/produtores
# Deve listar o produtor criado

# 4. Acessar via Gateway
curl http://localhost:5000/gestao/v1/produtores \
  -H "Authorization: Bearer <TOKEN>"
```

---

## 📊 Acessar Dashboards

| Dashboard | URL | Credenciais |
|-----------|-----|-------------|
| **Grafana** | http://localhost:3000 | admin / admin |
| **Prometheus** | http://localhost:9090 | N/A |
| **RabbitMQ** | http://localhost:15672 | guest / guest |
| **Keycloak** | http://localhost:8080 | admin / admin |
| **Identity API Docs** | http://localhost:5001/scalar/v1 | N/A |
| **Properties API Docs** | http://localhost:5002/scalar/v1 | N/A |
| **Gateway Swagger** | http://localhost:5000/swagger | N/A |

---

## 🔧 Troubleshooting

### Problema: Containers não sobem

```bash
# Verificar portas em uso
sudo lsof -i :5000,5001,5002,8080,5672,3000,9090

# Limpar recursos antigos
make clean-all

# Verificar logs
make logs
```

### Problema: Database não inicializa

```bash
# Remover volume do postgres
docker volume rm agrosolutions-service-identity_postgres_data

# Dar permissão ao script
chmod +x infra/init-databases.sh

# Recriar
make up
```

### Problema: RabbitMQ sem queues

```bash
# Recriar RabbitMQ com definitions
docker compose -f docker-compose.unified.yml up -d --force-recreate rabbitmq

# Verificar logs
make logs-infra | grep rabbitmq
```

### Problema: Identity não sincroniza com Properties

```bash
# Verificar se RabbitMQ está rodando
curl http://localhost:15672/api/healthchecks/node -u guest:guest

# Verificar se queue existe
# Abrir: http://localhost:15672/#/queues

# Restart dos services
make restart-services
```

**[Ver guia completo de troubleshooting →](./SETUP_UNIFIED.md#-troubleshooting)**

---

## 📚 Documentação Completa

- **[SETUP_UNIFIED.md](./SETUP_UNIFIED.md)** - Guia completo (650 linhas)
  - Estrutura do projeto
  - Pré-requisitos
  - Setup passo-a-passo
  - Validação
  - Testes de integração
  - Observabilidade
  - Troubleshooting avançado
  - Ajustes para produção

- **[MIGRATION_GUIDE.md](./MIGRATION_GUIDE.md)** - Migração do setup antigo (450 linhas)
  - Comparação antes/depois
  - Passos de migração
  - Ajustes necessários
  - Restore de dados
  - Problemas comuns

- **[ANALYSIS.md](./ANALYSIS.md)** - Análise técnica (800 linhas)
  - Redundâncias identificadas
  - Economia de recursos
  - Conflitos de porta resolvidos
  - Arquitetura unificada
  - Benefícios
  - Métricas de sucesso

- **[Makefile](./Makefile)** - 50+ comandos facilitados
  - Gerenciamento
  - Logs e monitoramento
  - Health checks
  - Build e deploy
  - Database
  - Backup/restore
  - Observability
  - Limpeza
  - Testes
  - Desenvolvimento

---

## 🎯 Próximos Passos

1. ✅ **Configurar Keycloak Realm**
   - Importar realm `agrosolutions`
   - Criar roles (produtor, administrador, tecnico)
   - Configurar scopes no JWT

2. ✅ **Criar Dashboards no Grafana**
   - Métricas de negócio (requests/min, latência)
   - Infraestrutura (CPU, RAM, Disk)
   - Mensageria (queue depth, message rate)
   - Service dependency graph

3. ✅ **Configurar Alertas**
   - High error rate (>5%)
   - Queue backlog (>1000 messages)
   - Circuit breaker open
   - Database connections high

4. ✅ **Backup Automatizado**
   - Cron job diário
   - Retention de 7 dias
   - Upload para S3/Azure Blob

5. ✅ **Deploy em Kubernetes**
   - Helm charts
   - Horizontal Pod Autoscaling
   - Persistent Volume Claims

---

## 🤝 Repositórios Relacionados

- [Identity Service](https://github.com/kyo1506/agrosolutions-service-identity) - Autenticação e usuários
- [Properties Service](https://github.com/kyo1506/agrosolutions-service-properties) - Gestão de propriedades
- [API Gateway](https://github.com/kyo1506/agrosolutions-api-gateway) - Ponto de entrada

---

## 📄 Licença

Projeto desenvolvido para o Hackathon AgroSolutions - Agricultura 4.0

---

**AgroSolutions** - Transformando a agricultura através da tecnologia 🌱

[⬆ Voltar ao topo](#-agrosolutions---setup-unificado)
