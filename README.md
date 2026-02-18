# AgroSolutions Identity Service

Serviço de autenticação e gestão de usuários usando Keycloak com integração AWS (SQS, SNS, SES, Lambda).

## 🚀 Quick Start

### ⚠️ Importante

Este projeto **não possui desenvolvimento local**. Toda infraestrutura de mensageria e email utiliza **AWS real** em conta de produção.

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

# 3. Atualizar ACCOUNT_ID no appsettings.Production.json
sed -i "s/ACCOUNT_ID/$(aws sts get-caller-identity --query Account --output text)/g" \
  src/AgroSolutions.Identity.Api/appsettings.Production.json

# 4. Instalar dependências
dotnet restore

# 5. Build
dotnet build

# 6. Rodar API (conecta na AWS real)
dotnet run --project src/AgroSolutions.Identity.Api --environment Production
```

## 📚 Documentação

- **[AWS Deployment Guide](docs/AWS_DEPLOYMENT.md)** - Guia completo de setup e deploy na AWS (LEIA PRIMEIRO)
- [AWS Migration Guide](docs/AWS_MIGRATION_GUIDE.md) - Contexto da arquitetura e design decisions

## 🏗️ Arquitetura de Produção (AWS)

```
Identity API → SNS Topic (user-events) → Fan-out para:
                                        ├─ SQS: produtor-sync-queue → Properties API
                                        ├─ SQS: email-queue → Lambda → SES  
                                        └─ SQS: status-changed-queue → Outros Consumidores

SNS Topic (email-notifications) → SQS: email-queue → Lambda → SES
```

### Fluxo de Eventos

1. **Usuário criado/atualizado** → API publica em SNS `user-events`
2. **Fan-out automático** → SNS distribui para filas SQS
3. **Properties API** consome `produtor-sync-queue` para sincronizar produtores
4. **Email Lambda** processa `email-queue` e envia via SES
5. **Outros serviços** consomem `status-changed-queue` conforme necessário

## ⚙️ Configuração

### Arquivo appsettings.Production.json

```json
{
  "AWS": {
    "Region": "us-east-1",
    "SQS": {
      "Queues": {
        "IdentityEvents": "agrosolutions-identity-events",
        "EmailQueue": "agrosolutions-email-queue",
        "ProdutorSyncQueue": "agrosolutions-produtor-sync-queue",
        "StatusChangedQueue": "agrosolutions-status-changed-queue"
      }
    },
    "SNS": {
      "Topics": {
        "UserEvents": "arn:aws:sns:us-east-1:ACCOUNT_ID:agrosolutions-user-events",
        "EmailNotifications": "arn:aws:sns:us-east-1:ACCOUNT_ID:agrosolutions-email-notifications",
        "PropertyEvents": "arn:aws:sns:us-east-1:ACCOUNT_ID:agrosolutions-property-events"
      }
    },
    "SES": {
      "FromEmail": "noreply@agrosolutions.com.br",
      "FromName": "AgroSolutions",
      "ConfigurationSetName": "agrosolutions-production",
      "VerifiedEmails": [
        "noreply@agrosolutions.com.br",
        "admin@agrosolutions.com.br",
        "suporte@agrosolutions.com.br"
      ]
    }
  }
}
```

**IMPORTANTE**: Substitua `ACCOUNT_ID` pelo seu AWS Account ID real.

## ⚙️ Tecnologias

- **.NET 10** - Framework
- **Keycloak** - Identity Provider
- **Amazon SQS/SNS** - Message Broker e Topics
- **Amazon SES** - Email Service
- **AWS Lambda** - Serverless email processing (.NET 8)
- **MassTransit** - Messaging abstraction
- **PostgreSQL** - Outbox pattern database

## 🔐 Credenciais AWS

As credenciais AWS são configuradas via **variáveis de ambiente**:

```bash
export AWS_ACCESS_KEY_ID=your_access_key_id
export AWS_SECRET_ACCESS_KEY=your_secret_access_key
export AWS_DEFAULT_REGION=us-east-1
```

### Arquivo .env (Desenvolvimento)

Copie o arquivo de exemplo e configure suas credenciais:

```bash
cp .env.example .env
# Edite .env com suas credenciais AWS
```

**⚠️ IMPORTANTE**: Nunca commite o arquivo `.env` com credenciais reais. O arquivo `.env.example` serve apenas como template.

### IAM Role (Produção - Recomendado)

Para EC2, ECS, EKS ou Lambda, use IAM roles anexadas ao recurso. Não é necessário configurar variáveis de ambiente explícitas.

## ✅ Health Check

```bash
curl http://localhost:5001/health
```

## 🧪 Testes

```bash
dotnet test src/AgroSolutions.Identity.Test
```

## 💰 Custos AWS Estimados

Para 10k usuários e 1k emails/dia:

- SQS: ~$0.50/mês
- SNS: ~$0.20/mês
- SES: ~$3.00/mês
- Lambda: ~$1.00/mês
- CloudWatch: ~$5.00/mês

**Total**: ~$10/mês

**Free Tier** (primeiro ano): Praticamente gratuito se dentro dos limites.

## 🆘 Precisa de Ajuda?

1. **Configuração AWS**: Ver [AWS_DEPLOYMENT.md](docs/AWS_DEPLOYMENT.md)
2. **Troubleshooting**: Seção 11 do deployment guide
3. **Custos inesperados**: Configurar billing alerts e revisar CloudWatch logs retention

## 📋 Checklist de Deploy

### Setup Inicial (Manual - Uma vez)
- [ ] AWS CLI configurado (`aws sts get-caller-identity`)
- [ ] Filas SQS criadas (identity-events, email-queue, produtor-sync-queue, status-changed-queue)
- [ ] Tópicos SNS criados (user-events, email-notifications, property-events)
- [ ] Subscriptions SNS → SQS configuradas
- [ ] Emails SES verificados (noreply@, admin@, suporte@)
- [ ] **IAM Role para Lambda criada** (AgroSolutions-Lambda-EmailProcessor-Role)
- [ ] GitHub Secrets configurados (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, etc.)
- [ ] EKS Cluster criado e configurado

### Deploy Automático (via CI/CD)
- [ ] Push para branch `main` dispara pipeline
- [ ] Build e testes passam com sucesso
- [ ] Docker image enviada para ECR
- [ ] Aplicação deployada no EKS
- [ ] **Lambda deployada automaticamente** (se houver mudanças em `lambda/`)
- [ ] Event source mapping SQS → Lambda configurado automaticamente
- [ ] Health checks passando
- [ ] Monitoramento CloudWatch ativo

## 📝 License

MIT

