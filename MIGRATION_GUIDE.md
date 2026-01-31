# 🔄 Migração: Compose Individual → Unified

Guia rápido de migração dos três repositórios para o setup unificado.

---

## 📊 Comparação: Antes vs Depois

### Antes (3 Repositórios Separados)

```
Identity:     Properties:   Gateway:
├── postgres   ├── postgres  ├── (sem DB)
├── keycloak   ├── keycloak  ├── keycloak (referência)
├── rabbitmq   ├── rabbitmq  ├── rabbitmq (referência)
├── prometheus ├── prometheus├── prometheus
├── loki       ├── loki      ├── loki
├── tempo      ├── tempo     ├── tempo
├── grafana    ├── grafana   ├── grafana
└── otel       └── otel      └── otel

Total: ~24 containers
Conflitos: 21 portas duplicadas
```

### Depois (Unified Compose)

```
Unified:
├── postgres (3 databases)
├── keycloak
├── rabbitmq
├── prometheus
├── loki
├── tempo
├── grafana
├── otel-collector
├── identity-api
├── properties-api
└── api-gateway

Total: 11 containers ✅
Conflitos: 0 ❌
Economia: ~70% menos recursos
```

---

## 🚀 Passos de Migração

### 1. Parar Ambientes Individuais

```bash
# Identity Service
cd ~/Documents/Projects/agrosolutions-service-identity
docker-compose down -v

# Properties Service
cd ~/Documents/Projects/agrosolutions-service-properties
docker-compose down -v

# API Gateway
cd ~/Documents/Projects/agrosolutions-api-gateway
docker-compose down -v
```

⚠️ **ATENÇÃO**: O `-v` remove volumes! Faça backup dos dados antes se necessário:

```bash
# Backup PostgreSQL do Identity
docker exec keycloak-db pg_dumpall -U keycloak > backup_identity_keycloak.sql

# Backup Properties Database
docker exec properties-postgres pg_dump -U postgres properties > backup_properties.sql
```

### 2. Garantir Estrutura de Pastas

Verificar que os três repositórios estão no mesmo nível:

```bash
cd ~/Documents/Projects
ls -la

# Deve mostrar:
# agrosolutions-service-identity/
# agrosolutions-service-properties/
# agrosolutions-api-gateway/
```

### 3. Copiar Configurações Unificadas

```bash
# Se você está no repo Identity
cd ~/Documents/Projects/agrosolutions-service-identity

# Verificar arquivos criados
ls -la infra/
ls -la docker-compose.unified.yml
```

### 4. Ajustar Permissões

```bash
chmod +x infra/init-databases.sh
```

### 5. Subir Unified Compose

```bash
docker compose -f docker-compose.unified.yml up -d --build
```

### 6. Aguardar Health Checks

```bash
# Acompanhar inicialização (demora ~2-3 minutos)
docker compose -f docker-compose.unified.yml logs -f
```

Aguardar até ver:
- `postgres` → `database system is ready to accept connections`
- `keycloak` → `Keycloak 26.5.2 started`
- `rabbitmq` → `Server startup complete`
- `identity-api` → `Application started`
- `properties-api` → `Application started`
- `api-gateway` → `Application started`

### 7. Validar Setup

```bash
# Health checks
curl http://localhost:5001/health  # Identity
curl http://localhost:5002/health  # Properties
curl http://localhost:5000/health  # Gateway

# Verificar databases
docker exec -it agrosolutions-postgres psql -U postgres -l
```

---

## 🔧 Ajustes nos Repositórios Individuais

### Properties Service - appsettings.json

**Antes:**
```json
"ConnectionStrings": {
  "DefaultConnection": "Host=postgres;Database=properties;Username=postgres;Password=postgres"
}
```

**Depois:**
Não precisa mudar! O unified compose já usa `Host=postgres`.

### Identity Service - Outbox Database

**Antes:**
```json
"ConnectionStrings": {
  "OutboxDb": "Host=localhost;Database=outbox;Username=postgres;Password=postgres"
}
```

**Depois (já configurado no unified compose):**
```yaml
- ConnectionStrings__OutboxDb=Host=postgres;Database=outbox;Username=postgres;Password=postgres
```

### API Gateway - Downstream Services

**Antes (ocelot.json):**
```json
"DownstreamHostAndPorts": [
  { "Host": "localhost", "Port": 5001 }
]
```

**Depois:**
```json
"DownstreamHostAndPorts": [
  { "Host": "identity-api", "Port": 8080 }
]
```

⚠️ **Importante**: Usar nomes de container DNS, não `localhost`!

---

## 📝 Configurações que Mudaram

### Portas de Acesso

| Serviço | Antes (Individual) | Depois (Unified) |
|---------|-------------------|------------------|
| Identity API | 5001 | ✅ 5001 (mesma) |
| Properties API | 5001 | ⚠️ 5002 (mudou) |
| API Gateway | 5000 | ✅ 5000 (mesma) |
| PostgreSQL | 5432 (Identity), 5433 (Properties) | ✅ 5432 (unificado) |
| Keycloak | 8080 | ✅ 8080 (mesma) |
| RabbitMQ AMQP | 5672 | ✅ 5672 (mesma) |
| RabbitMQ UI | 15672 | ✅ 15672 (mesma) |
| Grafana | 3000 | ✅ 3000 (mesma) |
| Prometheus | 9090 | ✅ 9090 (mesma) |

### Nomes de Containers

| Antes | Depois |
|-------|--------|
| `keycloak` | `agrosolutions-keycloak` |
| `keycloak-db` | `agrosolutions-postgres` |
| `postgres` | `agrosolutions-postgres` |
| `rabbitmq` | `agrosolutions-rabbitmq` |
| `identity-api` | `identity-api` (mesmo) |
| `properties-api` | `properties-api` (mesmo) |
| `api-gateway` | `api-gateway` (mesmo) |

### Network Name

Todos agora usam: `agrosolutions-network` (antes cada um tinha sua própria).

---

## 🔄 Restore de Dados (Opcional)

Se você fez backup dos databases antes:

```bash
# Restore Keycloak
docker exec -i agrosolutions-postgres psql -U postgres keycloak < backup_identity_keycloak.sql

# Restore Properties
docker exec -i agrosolutions-postgres psql -U postgres properties < backup_properties.sql
```

---

## 🧹 Limpeza de Recursos Antigos

Após validar que tudo funciona:

```bash
# Remover volumes antigos
docker volume prune

# Remover imagens antigas
docker image prune -a

# Ver espaço recuperado
docker system df
```

---

## ⚡ Performance Tips

### 1. Ordenar Startup com depends_on

O unified compose já tem dependencies corretas:
```yaml
identity-api:
  depends_on:
    postgres:
      condition: service_healthy
    keycloak:
      condition: service_healthy
```

### 2. Ajustar Resource Limits (Opcional)

Se sua máquina tem recursos limitados:

```yaml
identity-api:
  deploy:
    resources:
      limits:
        cpus: '0.5'
        memory: 512M
```

### 3. Desabilitar Serviços Não Utilizados

Se não usar observability em dev:

```bash
# Subir apenas microsserviços + infra essencial
docker compose -f docker-compose.unified.yml up -d \
  postgres keycloak rabbitmq \
  identity-api properties-api api-gateway
```

---

## 🐛 Problemas Comuns na Migração

### 1. "Connection refused" no Identity

**Causa**: Identity tentando conectar em `localhost:8080` em vez de `keycloak:8080`.

**Solução**: Verificar variável de ambiente:
```bash
docker exec identity-api env | grep KeycloakConfiguration__BaseUrl
# Deve mostrar: http://keycloak:8080
```

### 2. Properties não sincroniza Produtores

**Causa**: Queue não foi criada ou consumer não está escutando.

**Solução**:
```bash
# Verificar queues no RabbitMQ
open http://localhost:15672/#/queues

# Restart Properties para reconectar
docker compose -f docker-compose.unified.yml restart properties-api
```

### 3. "Database not found" no Properties

**Causa**: Database `properties` não foi criado.

**Solução**:
```bash
# Verificar databases criados
docker exec agrosolutions-postgres psql -U postgres -l

# Se não existir, criar manualmente:
docker exec agrosolutions-postgres psql -U postgres -c "CREATE DATABASE properties;"
```

### 4. Grafana sem datasources

**Causa**: Arquivo `grafana-datasources.yml` não foi montado.

**Solução**:
```bash
# Recriar Grafana
docker compose -f docker-compose.unified.yml up -d --force-recreate grafana

# Verificar logs
docker compose -f docker-compose.unified.yml logs grafana | grep "datasource"
```

---

## 📚 Referências

- [SETUP_UNIFIED.md](./SETUP_UNIFIED.md) - Guia completo de uso
- [docker-compose.unified.yml](./docker-compose.unified.yml) - Compose centralizado
- [infra/](./infra/) - Configurações de infraestrutura

---

**Migração concluída!** 🎉

Agora você tem uma stack unificada, otimizada e sem conflitos.
