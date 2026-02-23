# AgroSolutions Identity Service

Serviço de autenticação e gestão de identidade usando Keycloak com integração AWS (SQS/SNS via MassTransit, SES, Lambda).

## 🚀 Quick Start

### ⚠️ Importante

Este projeto **não possui desenvolvimento local**. Toda infraestrutura de mensageria e email utiliza **AWS real** em conta de produção (região `sa-east-1`).

### Pré-requisitos

1. **Conta AWS** com credenciais configuradas
2. **.NET 10 SDK** instalado
3. **AWS CLI** configurado
4. **Recursos AWS** criados (SQS, SNS, SES, Lambda)

### Deploy

```bash
# 1. Configurar credenciais AWS
aws configure

# 2. Criar recursos AWS (seguir guia completo)
# Ver: docs/AWS_DEPLOYMENT.md

# 3. Instalar dependências
dotnet restore

# 4. Build
dotnet build

# 5. Rodar API (conecta na AWS real)
dotnet run --project src/AgroSolutions.Identity.Api --environment Production
```

## 📚 Documentação

- **[AWS Deployment Guide](docs/AWS_DEPLOYMENT.md)** - Guia completo de setup e deploy na AWS (LEIA PRIMEIRO)
- [AWS Migration Guide](docs/AWS_MIGRATION_GUIDE.md) - Contexto da arquitetura e design decisions

## 🏗️ Arquitetura de Produção (AWS)

```
Identity API → MassTransit → SNS Topic (agrosolutions-user-events) → Fan-out para:
                                        ├─ SQS: agrosolutions-identity-events → Consumidores
                                        └─ SQS: email-queue → Lambda (EmailProcessor) → SES

                         ┌──────────────────────────────────────┐
                         │         Outbox Pattern               │
                         │  Evento → PostgreSQL (pending)       │
                         │         ↓                            │
                         │  OutboxProcessorJob (10s polling)    │
                         │         ↓                            │
                         │  MassTransit → SNS → SQS             │
                         └──────────────────────────────────────┘
```

### Fluxo de Eventos

1. **Usuário criado/atualizado/deletado** → `ResilientEventPublisher` persiste no Outbox (PostgreSQL)
2. **Publicação imediata** → Circuit Breaker protege contra falhas em cascata; se aberto, o `OutboxProcessorJob` reprocessa
3. **MassTransit** publica no tópico SNS `agrosolutions-user-events`
4. **Fan-out SNS** → distribui para filas SQS inscritas
5. **Email Lambda** (`AgroSolutions-EmailProcessor`) consome a fila e envia via SES

## ⚙️ Configuração

### Arquivo appsettings.Production.json

```json
{
  "AWS": {
    "Region": "sa-east-1",
    "SQS": {
      "Queues": {
        "IdentityEvents": "agrosolutions-identity-events"
      }
    },
    "SNS": {
      "Topics": {
        "UserEvents": "arn:aws:sns:sa-east-1:316295889438:agrosolutions-user-events"
      }
    },
    "SES": {
      "FromEmail": "vinicius_pinheiro02@hotmail.com",
      "FromName": "AgroSolutions",
      "ConfigurationSetName": "agrosolutions-production"
    },
    "Lambda": {
      "EmailProcessorArn": "arn:aws:lambda:sa-east-1:316295889438:function:AgroSolutions-EmailProcessor"
    }
  },
  "ConnectionStrings": {
    "OutboxDb": "Host=<host>;Database=outbox;Username=postgres;Password=<password>"
  }
}
```

## ⚙️ Tecnologias

| Camada | Tecnologia | Versão | Finalidade |
|--------|-----------|--------|------------|
| Framework | **.NET** | 10.0 | Runtime da API |
| Identity Provider | **Keycloak** | 26.5.2 | Emissão de JWT, gestão de usuários |
| Messaging | **MassTransit + Amazon SQS/SNS** | 8.5.x | Publicação de eventos de domínio |
| Email | **Amazon SES** | SDK 4.x | Envio transacional de e-mails |
| Serverless | **AWS Lambda** | .NET 8 | Processamento assíncrono de emails |
| Banco de dados | **PostgreSQL** | 16 | Outbox Pattern (garantia de entrega) |
| ORM | **Entity Framework Core** | 10.x | Acesso ao banco Outbox |
| Resiliência | **Polly** | 8.x | Circuit Breaker, Retry, Timeout |
| Observabilidade | **OpenTelemetry** | 1.x | Traces, Métricas, Logs |
| API Docs | **Scalar** | - | Documentação interativa (substitui Swagger) |

## 🔐 Credenciais AWS

As credenciais AWS são configuradas via **variáveis de ambiente** ou **IAM Role** (recomendado em produção):

```bash
export AWS_ACCESS_KEY_ID=your_access_key_id
export AWS_SECRET_ACCESS_KEY=your_secret_access_key
export AWS_DEFAULT_REGION=sa-east-1
```

### Arquivo .env (Desenvolvimento)

```bash
cp .env.example .env
# Edite .env com suas credenciais AWS
```

**⚠️ IMPORTANTE**: Nunca commite o arquivo `.env` com credenciais reais.

### IAM Role (Produção - Recomendado)

Em EKS, use a IAM Role anexada ao node group ou via IRSA (IAM Roles for Service Accounts). Não é necessário configurar variáveis de ambiente explícitas.

## 🌐 Endpoints da API

### Autenticação e Usuários (`AuthController`)

| Método | Rota | Auth | Scope | Descrição |
|--------|------|------|-------|-----------|
| `POST` | `/v1/login` | Não | - | Login com username/email e senha |
| `POST` | `/v1/register` | Não | - | Registro de novo usuário |
| `GET` | `/v1/users` | Sim | `users:manage` | Listar todos os usuários |
| `GET` | `/v1/users/{id}` | Sim | `users:read` | Buscar usuário por ID |
| `PUT` | `/v1/users/{id}` | Sim | `users:manage` | Atualizar usuário (admin) |
| `DELETE` | `/v1/users/{id}` | Sim | `users:manage` | Desabilitar usuário (soft delete) |
| `GET` | `/v1/profile` | Sim | `profiles:manage` | Obter perfil do usuário autenticado |
| `PUT` | `/v1/profile` | Sim | `profiles:manage` | Atualizar perfil próprio |

### Validação Inter-Serviços (`ValidationController`)

| Método | Rota | Auth | Descrição |
|--------|------|------|-----------|
| `POST` | `/v1/validate-token` | Bearer Token | Valida JWT e retorna dados do usuário |
| `POST` | `/v1/validate-permission` | Bearer Token | Verifica se usuário tem permissão em recurso:ação |

> Os endpoints de validação são usados internamente pelos demais microserviços da plataforma.

## ✅ Health Check

```bash
curl http://localhost:5001/health
```

## 🧪 Testes

```bash
dotnet test src/AgroSolutions.Identity.Test
```

## 💰 Custos AWS Estimados

Para 10k usuários e 1k emails/dia (região `sa-east-1`):

- SQS: ~$0.50/mês
- SNS: ~$0.20/mês
- SES: ~$3.00/mês
- Lambda: ~$1.00/mês
- CloudWatch/Logs: ~$5.00/mês

**Total**: ~$10/mês

**Free Tier** (primeiro ano): Praticamente gratuito se dentro dos limites.

## 🆘 Precisa de Ajuda?

1. **Configuração AWS**: Ver [AWS_DEPLOYMENT.md](docs/AWS_DEPLOYMENT.md)
2. **Troubleshooting**: Seção de troubleshooting do deployment guide
3. **Custos inesperados**: Configurar billing alerts e revisar CloudWatch logs retention

## 📋 Checklist de Deploy

### Setup Inicial (Manual - Uma vez)
- [ ] AWS CLI configurado (`aws sts get-caller-identity`)
- [ ] Fila SQS criada: `agrosolutions-identity-events`
- [ ] Tópico SNS criado: `agrosolutions-user-events`
- [ ] Subscription SNS → SQS configurada
- [ ] Email verificado no SES
- [ ] **IAM Role para Lambda criada** (`AgroSolutions-Lambda-EmailProcessor-Role`)
- [ ] GitHub Secrets configurados (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` ou OIDC Role)
- [ ] EKS Cluster criado e configurado

### Deploy Automático (via CI/CD)
- [ ] Push para branch `main` dispara pipeline
- [ ] Build e testes passam com sucesso
- [ ] Docker image enviada para ECR (`sa-east-1`)
- [ ] Kubernetes secrets criados (Keycloak, JWT, Database)
- [ ] Aplicação deployada no EKS (`agrosolutions-identity` namespace)
- [ ] **Lambda deployada automaticamente** (se houver mudanças em `lambda/`)
- [ ] Event source mapping SQS → Lambda configurado automaticamente
- [ ] Health checks passando
- [ ] HPA aplicado (auto scaling)

## 📝 License

MIT

