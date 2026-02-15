# 🚀 Guia de Migração: RabbitMQ → AWS SQS/SNS/SES

## 📋 Índice

1. [Visão Geral](#visão-geral)
2. [Arquitetura AWS](#arquitetura-aws)
3. [Configurar MassTransit com SQS](#configurar-masstransit-com-sqs)
4. [Deploy da Lambda de E-mails](#deploy-da-lambda-de-e-mails)
5. [Deploy em Produção (AWS)](#deploy-em-produção-aws)
6. [Migração Gradual](#migração-gradual)
7. [Troubleshooting](#troubleshooting)

---

## 🎯 Visão Geral

### Por Que Migrar?

| Aspecto | RabbitMQ | AWS SQS/SNS |
|---------|----------|-------------|
| **Gerenciamento** | Auto-hospedado | Totalmente gerenciado |
| **Escalabilidade** | Manual | Automática e infinita |
| **Durabilidade** | Depende do cluster | 99.999999999% (11 noves) |
| **Custo** | Infraestrutura fixa | Pay-per-use |
| **Integração AWS** | Requer configuração | Nativa |
| **Dead Letter Queue** | Manual | Automática |
| **Observabilidade** | Prometheus/Grafana | CloudWatch nativo |

### Componentes AWS

```
┌──────────────────────────────────────────────────────────────┐
│  ARQUITETURA AWS - MENSAGERIA                                │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  Identity API                                                │
│      │                                                       │
│      │ 1. Publish Event                                     │
│      ▼                                                       │
│  ┌─────────────┐                                            │
│  │   SNS       │  (Tópico: user-events)                     │
│  │  Topic      │                                            │
│  └──────┬──────┘                                            │
│         │                                                    │
│         ├─────────────────────────┬──────────────────────┐  │
│         │ 2. Fan-out              │                      │  │
│         ▼                         ▼                      ▼  │
│  ┌────────────┐           ┌────────────┐        ┌─────────┐│
│  │ SQS Queue  │           │ SQS Queue  │        │OUTRO SQS││
│  │ produtor-  │           │ email-     │        │  ...    ││
│  │ sync-queue │           │ queue      │        └─────────┘│
│  └──────┬─────┘           └──────┬─────┘                   │
│         │ 3. Poll               │ 3. Trigger              │
│         ▼                       ▼                          │
│  ┌────────────┐          ┌────────────┐                   │
│  │Properties  │          │ Lambda     │ 4. Send via SE    │
│  │API Consumer│          │ Email Proc │ ───────────────►  │
│  └────────────┘          └────────────┘                   │
│                                                            │
└──────────────────────────────────────────────────────────┘
```

---

## ⚙️ Configurar MassTransit com SQS

### 1. Adicionar Pacotes NuGet

```bash
cd src/AgroSolutions.Identity.Api
dotnet add package MassTransit.AmazonSQS
dotnet add package AWSSDK.SimpleEmail
dotnet add package AWSSDK.SQS
dotnet add package AWSSDK.SimpleNotificationService
```

### 2. Atualizar Program.cs

```csharp
// Usar configuração AWS:
builder.Services.ResolveAwsDependencies(builder.Configuration);
```

### 3. Configurar Diferenças RabbitMQ vs SQS

| Conceito RabbitMQ | Equivalente SQS/SNS |
|-------------------|---------------------|
| Exchange | SNS Topic |
| Queue | SQS Queue |
| Routing Key | Message Attributes |
| Dead Letter Exchange | Dead Letter Queue (DLQ) |
| TTL (Time to Live) | MessageRetentionPeriod |
| Priority Queue | ❌ Não suportado diretamente |

---

## 🧪 Testar em Produção

### 1. Publicar Evento via Identity API

```bash
curl -X POST http://localhost:5001/v1/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "teste01",
    "email": "teste@example.com",
    "password": "Test@123",
    "firstName": "João",
    "lastName": "Silva",
    "role": "produtor"
  }'
```

### 2. Verificar Mensagens na Fila SQS

```bash
# Ver mensagens na fila produtor-sync-queue
aws sqs receive-message \
  --queue-url https://sqs.us-east-1.amazonaws.com/ACCOUNT_ID/agrosolutions-produtor-sync-queue \
  --max-number-of-messages 10
```

### 3. Purgar Fila (Limpar)

```bash
aws sqs purge-queue \
  --queue-url https://sqs.us-east-1.amazonaws.com/ACCOUNT_ID/agrosolutions-email-queue
```

---

## 📧 Deploy da Lambda de E-mails

### 1. Build da Lambda

```bash
cd lambda/EmailLambda
dotnet build -c Release
```

### 2. Deploy em Produção (AWS)

```bash
# Instalar AWS SAM CLI
brew install aws-sam-cli  # macOS
# ou
pip install aws-sam-cli

# Deploy usando CloudFormation template
sam deploy \
  --template-file serverless.template \
  --stack-name agrosolutions-email-lambda \
  --parameter-overrides \
      Environment=Production \
      FromEmail=noreply@agrosolutions.com.br \
  --capabilities CAPABILITY_IAM \
  --region us-east-1
```

### 4. Testar Lambda

```bash
# Enviar mensagem de teste para a fila
aws sqs send-message \
  --queue-url https://sqs.us-east-1.amazonaws.com/ACCOUNT_ID/email-queue \
  --message-body '{
    "To": "teste@example.com",
    "Subject": "Teste Lambda",
    "HtmlBody": "<h1>Hello from Lambda!</h1>",
    "TextBody": "Hello from Lambda!"
  }'

# Ver logs no CloudWatch
aws logs tail /aws/lambda/AgroSolutions-EmailProcessor --follow
```

---

## 🚀 Deploy em Produção (AWS)

### 1. Criar Recursos via Terraform

```hcl
# infra/terraform/sqs.tf
resource "aws_sqs_queue" "identity_events" {
  name                       = "identity-events"
  visibility_timeout_seconds = 300
  message_retention_seconds  = 345600 # 4 days
  receive_wait_time_seconds  = 20     # Long polling
  
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.identity_events_dlq.arn
    maxReceiveCount     = 3
  })
  
  tags = {
    Environment = "Production"
    Service     = "Identity"
  }
}

resource "aws_sqs_queue" "identity_events_dlq" {
  name                      = "identity-events-dlq"
  message_retention_seconds = 1209600 # 14 days
}

# SNS Topic
resource "aws_sns_topic" "user_events" {
  name = "user-events"
}

# Subscription SNS → SQS
resource "aws_sns_topic_subscription" "user_events_to_produtor_queue" {
  topic_arn = aws_sns_topic.user_events.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.produtor_sync_queue.arn
}
```

### 2. Configurar IAM Permissions

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sqs:SendMessage",
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes"
      ],
      "Resource": "arn:aws:sqs:us-east-1:ACCOUNT_ID:identity-events"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sns:Publish"
      ],
      "Resource": "arn:aws:sns:us-east-1:ACCOUNT_ID:user-events"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ses:SendEmail",
        "ses:SendRawEmail",
        "ses:SendTemplatedEmail"
      ],
      "Resource": "*"
    }
  ]
}
```

### 3. Atualizar appsettings.Production.json

```json
{
  "AWS": {
    "Region": "us-east-1",
    "SES": {
      "FromEmail": "noreply@agrosolutions.com.br",
      "FromName": "AgroSolutions"
    }
  },
  "MassTransit": {
    "Transport": "AmazonSQS",
    "QueuePrefix": "agrosolutions-"
  }
}
```

---

## 🔄 Migração Gradual

### Estratégia: Dual Write (RabbitMQ + SQS)

1. **Fase 1**: Publicar em ambos (RabbitMQ e SQS)
2. **Fase 2**: Consumir de ambos, validar paridade
3. **Fase 3**: Remover RabbitMQ

```csharp
// DependencyInjectionConfiguration.cs
if (configuration.GetValue<bool>("UseHybridMessaging"))
{
    // Publicar em RabbitMQ E SQS
    services.AddScoped<IEventPublisher, HybridEventPublisher>();
}
```

---

## 🔍 Monitoramento

### CloudWatch Metrics

```bash
# Mensagens na fila
aws cloudwatch get-metric-statistics \
  --namespace AWS/SQS \
  --metric-name ApproximateNumberOfMessagesVisible \
  --dimensions Name=QueueName,Value=identity-events \
  --start-time 2026-01-01T00:00:00Z \
  --end-time 2026-01-31T23:59:59Z \
  --period 3600 \
  --statistics Sum
```

### Alarmes CloudWatch

```hcl
resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  alarm_name          = "identity-dlq-has-messages"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Alerta quando DLQ tem mais de 5 mensagens"
  
  dimensions = {
    QueueName = "identity-events-dlq"
  }
  
  alarm_actions = [aws_sns_topic.alerts.arn]
}
```

---

## 🐛 Troubleshooting

### Problema: Lambda não processa mensagens

**Diagnóstico:**
```bash
# Verificar logs da Lambda
aws logs tail /aws/lambda/AgroSolutions-EmailProcessor --follow

# Verificar mensagens na fila
aws sqs get-queue-attributes \
  --queue-url https://sqs.us-east-1.amazonaws.com/ACCOUNT_ID/email-queue \
  --attribute-names ApproximateNumberOfMessages
```

**Solução**: Verificar IAM role da Lambda tem permissão `sqs:ReceiveMessage`.

### Problema: SES retorna "Email address not verified"

**Solução:**
```bash
# Verificar e-mail no SES
aws ses verify-email-identity --email-address noreply@agrosolutions.com.br

# Confirmar no e-mail recebido

# Verificar status
aws ses get-identity-verification-attributes \
  --identities noreply@agrosolutions.com.br
```

---

## 📊 Custos Estimados (AWS)

| Serviço | Uso Mensal Estimado | Custo |
|---------|---------------------|-------|
| **SQS** | 1M requests | $0.40 |
| **SNS** | 1M publishes | $0.50 |
| **SES** | 10k emails | $1.00 |
| **Lambda** | 100k invocations | $0.20 (+ compute) |
| **CloudWatch Logs** | 5GB | $2.50 |
| **TOTAL** | - | **~$5.00/mês** |

---

## ✅ Checklist de Migração

- [ ] Credenciais AWS configuradas
- [ ] Recursos SQS/SNS criados na AWS
- [ ] MassTransit configurado para SQS
- [ ] Lambda de e-mail deployada
- [ ] SES com e-mails/domínio verificados
- [ ] IAM roles e policies configuradas
- [ ] Monitoramento CloudWatch ativo
- [ ] Alarmes configurados
- [ ] Testes de integração passando
- [ ] Documentação atualizada
- [ ] Rollback plan definido

---

## 📚 Referências

- [MassTransit Amazon SQS](https://masstransit.io/documentation/transports/amazon-sqs)
- [AWS SQS Best Practices](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-best-practices.html)
- [AWS SES Developer Guide](https://docs.aws.amazon.com/ses/latest/dg/Welcome.html)
- [AWS Lambda .NET Guide](https://docs.aws.amazon.com/lambda/latest/dg/lambda-csharp.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
