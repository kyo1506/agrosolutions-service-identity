# 🏗️ Arquitetura - AgroSolutions Identity Service

## 📐 Visão Geral da Arquitetura

### Acesso Público via Ocelot API Gateway

O **AgroSolutions Identity Service** faz parte de uma arquitetura de microsserviços e é acessado através do **Ocelot API Gateway**. O acesso direto ao serviço não é exposto publicamente.

```
┌─────────────────────────────────────────────────────────────┐
│                         INTERNET                            │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
                ┌──────────────────────┐
                │    AWS Route 53      │
                │ api.agrosolutions.com│
                └──────────┬───────────┘
                           │
                           ▼
                ┌──────────────────────┐
                │    AWS ALB/NLB       │
                │   Load Balancer      │
                └──────────┬───────────┘
                           │
                           ▼
         ┌─────────────────────────────────────────┐
         │   Ocelot API Gateway (Namespace)        │
         │   agrosolutions-gateway                 │
         │                                          │
         │   ✅ JWT Validation (Keycloak)          │
         │   ✅ Scope-Based Authorization          │
         │   ✅ Rate Limiting                       │
         │   ✅ CORS                                │
         │   ✅ Correlation ID                      │
         │   ✅ Circuit Breaker                     │
         │   ✅ Request/Response Logging            │
         └────┬────────────────────────────────┬────┘
              │                                │
              │                                │
   /identity/*                          /gestao/*
              │                          /ingestao/*
              │                          /telemetria/*
              ▼
┌──────────────────────────────────────┐
│  Identity Service (Namespace)        │
│  agrosolutions-identity              │
│                                      │
│  ┌────────────────────────────────┐ │
│  │  identity-api-service          │ │
│  │  ClusterIP: 80                 │ │
│  │                                │ │
│  │  - Login/Register              │ │
│  │  - User Management             │ │
│  │  - Profile Management          │ │
│  │  - Token Validation            │ │
│  └──────────┬─────────────────────┘ │
│             │                        │
│             ▼                        │
│  ┌────────────────────────────────┐ │
│  │  Keycloak 26.5.2               │ │
│  │  keycloak-service:8080         │ │
│  │                                │ │
│  │  - JWT Token Issuer            │ │
│  │  - User Repository             │ │
│  │  - Realm: agrosolutions        │ │
│  │  - Client: agrosolutions-api   │ │
│  └──────────┬─────────────────────┘ │
│             │                        │
│             ▼                        │
│  ┌────────────────────────────────┐ │
│  │  PostgreSQL 16-alpine          │ │
│  │  keycloak-db-service:5432      │ │
│  │                                │ │
│  │  - Keycloak Database           │ │
│  │  - Outbox Pattern Database     │ │
│  └────────────────────────────────┘ │
└──────────────────────────────────────┘
```

---

## 🔐 Fluxo de Autenticação

### 1. Login de Usuário

```
Cliente → Ocelot Gateway → Identity Service → Keycloak
         /identity/v1/login
                  ↓
         Retorna JWT Token
```

**URL Pública**: `POST https://api.agrosolutions.com/identity/v1/login`

**Configuração no Ocelot** (`ocelot.json`):
```json
{
  "DownstreamPathTemplate": "/v1/{everything}",
  "DownstreamScheme": "http",
  "DownstreamHostAndPorts": [{
    "Host": "identity-api-service.agrosolutions-identity",
    "Port": 80
  }],
  "UpstreamPathTemplate": "/identity/v1/{everything}",
  "UpstreamHttpMethod": ["GET", "POST", "PUT", "DELETE"]
}
```

### 2. Requisição Autenticada

```
Cliente (com JWT) → Ocelot Gateway
                    ↓ (valida JWT)
                    ↓ (valida scopes)
                    ↓
                    Identity Service
```

**Scopes Disponíveis**:
- `users:read` - Leitura de usuários
- `users:manage` - Gerenciamento completo de usuários
- `profiles:manage` - Gerenciamento do próprio perfil

---

## 🌐 Endpoints Públicos

Todos os endpoints são acessados via Ocelot Gateway:

### Endpoints Anônimos (sem autenticação)

| Método | URL Pública | Descrição |
|--------|-------------|-----------|
| POST | `https://api.agrosolutions.com/identity/v1/login` | Login de usuário |
| POST | `https://api.agrosolutions.com/identity/v1/register` | Registro de novo usuário |
| GET | `https://api.agrosolutions.com/identity/v1/health` | Health check |

### Endpoints Autenticados (requerem JWT)

| Método | URL Pública | Scope Requerido | Descrição |
|--------|-------------|-----------------|-----------|
| GET | `https://api.agrosolutions.com/identity/v1/users` | `users:read` | Listar usuários |
| GET | `https://api.agrosolutions.com/identity/v1/users/{id}` | `users:read` | Obter usuário por ID |
| POST | `https://api.agrosolutions.com/identity/v1/users` | `users:manage` | Criar usuário |
| PUT | `https://api.agrosolutions.com/identity/v1/users/{id}` | `users:manage` | Atualizar usuário |
| DELETE | `https://api.agrosolutions.com/identity/v1/users/{id}` | `users:manage` | Deletar usuário |
| GET | `https://api.agrosolutions.com/identity/v1/profile` | `profiles:manage` | Obter perfil próprio |
| PUT | `https://api.agrosolutions.com/identity/v1/profile` | `profiles:manage` | Atualizar perfil próprio |

---

## 🔒 Segurança em Camadas

### Camada 1: Ocelot API Gateway
- ✅ Validação de JWT (assinatura, expiração, issuer, audience)
- ✅ Verificação de scopes no token
- ✅ Rate limiting por rota
- ✅ CORS policies
- ✅ Circuit breaker
- ✅ Request/Response logging com Correlation ID

### Camada 2: Identity Service
- ✅ Validação adicional de JWT (defense in depth)
- ✅ Business logic validation
- ✅ Notifier pattern para validações de domínio
- ✅ Logging estruturado com OpenTelemetry

### Camada 3: Keycloak
- ✅ Gestão de usuários
- ✅ Emissão de tokens JWT
- ✅ Refresh tokens
- ✅ Role-based access control (RBAC)

---

## 🚀 Deployment

### Kubernetes Services

**Identity Service** (ClusterIP - acesso interno apenas):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: identity-api-service
  namespace: agrosolutions-identity
spec:
  type: ClusterIP
  selector:
    app: identity-api
  ports:
    - name: http
      port: 80
      targetPort: 80
```

**Keycloak Service** (ClusterIP - acesso interno apenas):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: keycloak-service
  namespace: agrosolutions-identity
spec:
  type: ClusterIP
  selector:
    app: keycloak
  ports:
    - name: http
      port: 8080
      targetPort: 8080
```

### Ingress (Opcional - apenas para Keycloak Admin)

O arquivo `k8s/production/ingress-aws.yaml` é **OPCIONAL** e serve apenas para acesso direto ao **Keycloak Admin Console** em `keycloak-admin.agrosolutions.com` (para debug/administração).

**⚠️ Importante**: 
- A Identity API **NÃO** é exposta diretamente via Ingress
- Todo acesso público à Identity API **DEVE** passar pelo Ocelot Gateway

---

## 🔗 Comunicação entre Namespaces

### Ocelot Gateway → Identity Service

**FQDN (Fully Qualified Domain Name)**:
```
identity-api-service.agrosolutions-identity.svc.cluster.local:80
```

**Short Name** (quando em configuração do Ocelot):
```
identity-api-service.agrosolutions-identity:80
```

### Identity Service → Keycloak

**JWT Authority Configuration** (`appsettings.Production.json`):
```json
{
  "Jwt": {
    "Authority": "http://keycloak-service.agrosolutions-identity:8080/realms/agrosolutions",
    "Audience": "agrosolutions-api"
  }
}
```

### Ocelot Gateway → Keycloak (JWT Validation)

**JWT Authority Configuration** (Ocelot `appsettings.json`):
```json
{
  "Jwt": {
    "Authority": "http://keycloak-service.agrosolutions-identity:8080/realms/agrosolutions",
    "Audience": "agrosolutions-api"
  }
}
```

---

## 📊 Observabilidade

### Stack Completo (LGTM)

- **Loki**: Agregação de logs
- **Grafana**: Dashboards e visualizações
- **Tempo**: Distributed tracing
- **Prometheus**: Métricas

### Acesso (Grafana)

**URL Pública**: `https://grafana.agrosolutions.com`

**Dashboards Pré-Configurados**:
- Identity Service Overview
- Keycloak Metrics
- API Gateway Metrics (Ocelot)
- Database Performance

---

## 🧪 Testes e Desenvolvimento

### Acesso Local via Port-Forward

Para **desenvolvimento/debug** local, você pode acessar os serviços diretamente:

```bash
# Identity API (bypassa o Gateway - apenas para debug)
kubectl port-forward svc/identity-api-service 8080:80 -n agrosolutions-identity
curl http://localhost:8080/v1/health

# Keycloak Admin Console
kubectl port-forward svc/keycloak-service 8081:8080 -n agrosolutions-identity
# Acesse: http://localhost:8081
```

### Testes de Integração

**Recomendação**: Todos os testes de integração devem simular o fluxo completo passando pelo Gateway:

```bash
# 1. Login
TOKEN=$(curl -X POST https://api.agrosolutions.com/identity/v1/login \
  -H "Content-Type: application/json" \
  -d '{"username":"user@example.com","password":"password"}' \
  | jq -r '.data.accessToken')

# 2. Usar token em requisições autenticadas
curl https://api.agrosolutions.com/identity/v1/users \
  -H "Authorization: Bearer $TOKEN"
```

---

## 📚 Referências

### Projetos Relacionados
- [AgroSolutions API Gateway](../agrosolutions-api-gateway) - Ocelot Gateway principal
- [AgroSolutions Gestão Service](https://github.com/agrosolutions/gestao-service) - Gestão de fazendas
- [AgroSolutions Ingestão Service](https://github.com/agrosolutions/ingestao-service) - Ingestão de telemetria
- [AgroSolutions Telemetria Service](https://github.com/agrosolutions/telemetria-service) - Processamento de telemetria

### Documentação
- [Ocelot Documentation](https://ocelot.readthedocs.io/)
- [Keycloak Documentation](https://www.keycloak.org/documentation)
- [Kubernetes Service DNS](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)
- [JWT Best Practices](https://datatracker.ietf.org/doc/html/rfc8725)

---

**Última atualização:** 2026-02-18  
**Versão:** 1.0.0
