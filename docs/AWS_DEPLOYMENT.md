# Guia de Deploy AWS - AgroSolutions Identity Service

## 📋 Pré-requisitos

- Conta AWS ativa
- AWS CLI instalado e configurado
- .NET 10 SDK instalado
- Permissões IAM para SQS, SNS, SES, Lambda

## 🔐 1. Configurar Credenciais AWS

### Opção 1: AWS CLI (Recomendado para desenvolvimento)

```bash
aws configure
```

Forneça:
- AWS Access Key ID
- AWS Secret Access Key
- Default region: `us-east-1`
- Default output format: `json`

### Opção 2: Variáveis de Ambiente

```bash
export AWS_ACCESS_KEY_ID=your_access_key
export AWS_SECRET_ACCESS_KEY=your_secret_key
export AWS_DEFAULT_REGION=us-east-1
```

### Opção 3: IAM Role (Recomendado para produção)

Para EC2, ECS, ou Lambda, use IAM roles anexadas ao recurso. Não é necessário configurar credenciais explícitas.

### Verificar configuração:

```bash
aws sts get-caller-identity
```

Deve retornar seu UserId, Account ID e ARN.

## 🏗️ 2. Criar Recursos AWS

### 2.1 Obter Account ID

```bash
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account ID: $ACCOUNT_ID"
```

### 2.2 Criar Filas SQS

```bash
# Identity Events Queue
aws sqs create-queue --queue-name agrosolutions-identity-events

# Email Queue
aws sqs create-queue --queue-name agrosolutions-email-queue

# Produtor Sync Queue
aws sqs create-queue --queue-name agrosolutions-produtor-sync-queue

# Status Changed Queue
aws sqs create-queue --queue-name agrosolutions-status-changed-queue
```

### 2.3 Criar Dead Letter Queues (DLQ)

```bash
aws sqs create-queue --queue-name agrosolutions-email-queue-dlq
aws sqs create-queue --queue-name agrosolutions-produtor-sync-queue-dlq
aws sqs create-queue --queue-name agrosolutions-status-changed-queue-dlq
```

### 2.4 Configurar Redrive Policy nas Filas

```bash
# Obter ARN da DLQ
DLQ_ARN=$(aws sqs get-queue-attributes \
  --queue-url https://sqs.us-east-1.amazonaws.com/$ACCOUNT_ID/agrosolutions-email-queue-dlq \
  --attribute-names QueueArn \
  --query 'Attributes.QueueArn' --output text)

# Configurar redrive policy na fila principal
aws sqs set-queue-attributes \
  --queue-url https://sqs.us-east-1.amazonaws.com/$ACCOUNT_ID/agrosolutions-email-queue \
  --attributes "{\"RedrivePolicy\":\"{\\\"deadLetterTargetArn\\\":\\\"$DLQ_ARN\\\",\\\"maxReceiveCount\\\":\\\"3\\\"}\"}"
```

Repita para as outras filas.

### 2.5 Criar Tópicos SNS

```bash
# User Events Topic
aws sns create-topic --name agrosolutions-user-events

# Email Notifications Topic
aws sns create-topic --name agrosolutions-email-notifications

# Property Events Topic
aws sns create-topic --name agrosolutions-property-events
```

### 2.6 Criar Subscriptions (SNS → SQS)

```bash
# User Events → Produtor Sync Queue
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:$ACCOUNT_ID:agrosolutions-user-events \
  --protocol sqs \
  --notification-endpoint arn:aws:sqs:us-east-1:$ACCOUNT_ID:agrosolutions-produtor-sync-queue

# Email Notifications → Email Queue
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:$ACCOUNT_ID:agrosolutions-email-notifications \
  --protocol sqs \
  --notification-endpoint arn:aws:sqs:us-east-1:$ACCOUNT_ID:agrosolutions-email-queue
```

### 2.7 Configurar SQS Policy para receber do SNS

```bash
# Obter URLs das filas
PRODUTOR_QUEUE_URL=$(aws sqs get-queue-url --queue-name agrosolutions-produtor-sync-queue --query 'QueueUrl' --output text)
EMAIL_QUEUE_URL=$(aws sqs get-queue-url --queue-name agrosolutions-email-queue --query 'QueueUrl' --output text)

# Adicionar policy para permitir SNS enviar para SQS
aws sqs set-queue-attributes \
  --queue-url $PRODUTOR_QUEUE_URL \
  --attributes "{\"Policy\":\"{\\\"Version\\\":\\\"2012-10-17\\\",\\\"Statement\\\":[{\\\"Effect\\\":\\\"Allow\\\",\\\"Principal\\\":{\\\"Service\\\":\\\"sns.amazonaws.com\\\"},\\\"Action\\\":\\\"sqs:SendMessage\\\",\\\"Resource\\\":\\\"arn:aws:sqs:us-east-1:$ACCOUNT_ID:agrosolutions-produtor-sync-queue\\\"}]}\"}"

aws sqs set-queue-attributes \
  --queue-url $EMAIL_QUEUE_URL \
  --attributes "{\"Policy\":\"{\\\"Version\\\":\\\"2012-10-17\\\",\\\"Statement\\\":[{\\\"Effect\\\":\\\"Allow\\\",\\\"Principal\\\":{\\\"Service\\\":\\\"sns.amazonaws.com\\\"},\\\"Action\\\":\\\"sqs:SendMessage\\\",\\\"Resource\\\":\\\"arn:aws:sqs:us-east-1:$ACCOUNT_ID:agrosolutions-email-queue\\\"}]}\"}"
```

## 📧 3. Configurar Amazon SES

### 3.1 Verificar Emails

```bash
aws ses verify-email-identity --email-address noreply@agrosolutions.com.br
aws ses verify-email-identity --email-address admin@agrosolutions.com.br
aws ses verify-email-identity --email-address suporte@agrosolutions.com.br
```

Cada email receberá um link de verificação. Clique nos links para verificar.

### 3.2 Verificar Status

```bash
aws ses get-identity-verification-attributes \
  --identities noreply@agrosolutions.com.br admin@agrosolutions.com.br suporte@agrosolutions.com.br
```

### 3.3 (Opcional) Verificar Domínio

Para produção, é recomendado verificar o domínio inteiro:

```bash
aws ses verify-domain-identity --domain agrosolutions.com.br
```

Adicione os registros TXT retornados ao seu DNS.

### 3.4 Criar Configuration Set

```bash
aws ses create-configuration-set --configuration-set Name=agrosolutions-production
```

## ⚡ 4. Deploy da Lambda Function

### 4.1 Instalar AWS Lambda Tools

```bash
dotnet tool install -g Amazon.Lambda.Tools
```

### 4.2 Criar IAM Role para Lambda

Crie um arquivo `lambda-trust-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

Crie a role:

```bash
aws iam create-role \
  --role-name AgroSolutions-EmailLambda-Role \
  --assume-role-policy-document file://lambda-trust-policy.json
```

### 4.3 Adicionar Policies à Role

```bash
# CloudWatch Logs
aws iam attach-role-policy \
  --role-name AgroSolutions-EmailLambda-Role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

# SQS
aws iam attach-role-policy \
  --role-name AgroSolutions-EmailLambda-Role \
  --policy-arn arn:aws:iam::aws:policy/AmazonSQSFullAccess

# SES (criar policy customizada)
```

Crie `ses-send-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ses:SendEmail",
        "ses:SendRawEmail"
      ],
      "Resource": "*"
    }
  ]
}
```

```bash
aws iam create-policy \
  --policy-name AgroSolutions-SES-Send \
  --policy-document file://ses-send-policy.json

aws iam attach-role-policy \
  --role-name AgroSolutions-EmailLambda-Role \
  --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/AgroSolutions-SES-Send
```

### 4.4 Build e Deploy da Lambda

```bash
cd lambda/EmailLambda

# Build
dotnet lambda package -c Release -o bin/Release/function.zip

# Deploy
dotnet lambda deploy-function \
  --function-name AgroSolutions-EmailProcessor \
  --function-role AgroSolutions-EmailLambda-Role \
  --function-handler EmailLambda::AgroSolutions.EmailLambda.Function::FunctionHandler \
  --function-memory-size 512 \
  --function-timeout 300 \
  --environment-variables FROM_EMAIL=noreply@agrosolutions.com.br,FROM_NAME=AgroSolutions
```

### 4.5 Configurar Event Source Mapping (SQS → Lambda)

```bash
aws lambda create-event-source-mapping \
  --function-name AgroSolutions-EmailProcessor \
  --event-source-arn arn:aws:sqs:us-east-1:$ACCOUNT_ID:agrosolutions-email-queue \
  --batch-size 10 \
  --enabled
```

## 🔧 5. Atualizar Configuração da API

### 5.1 Editar appsettings.Production.json

Substitua `ACCOUNT_ID` pelo seu Account ID real em todos os ARNs:

```bash
cd /home/kyo1506/Documents/Projects/agrosolutions-service-identity/src/AgroSolutions.Identity.Api

# Opção 1: Manual
nano appsettings.Production.json

# Opção 2: Usando sed
sed -i "s/ACCOUNT_ID/$ACCOUNT_ID/g" appsettings.Production.json
```

### 5.2 Verificar configuração final

```bash
cat appsettings.Production.json
```

## 🚀 6. Executar a API

### Desenvolvimento Local (conectando na AWS real)

```bash
dotnet run --project src/AgroSolutions.Identity.Api/AgroSolutions.Identity.Api.csproj --environment Production
```

### Produção (Docker)

```bash
docker build -t agrosolutions-identity:latest .

docker run -d \
  -p 5001:8080 \
  -e ASPNETCORE_ENVIRONMENT=Production \
  -e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
  -e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
  -e AWS_DEFAULT_REGION=us-east-1 \
  --name identity-api \
  agrosolutions-identity:latest
```

### Produção (EC2 com IAM Role - Recomendado)

No EC2, anexe uma IAM role com as mesmas permissões da Lambda. Não precisará de credenciais explícitas:

```bash
dotnet publish -c Release -o /app

cd /app
dotnet AgroSolutions.Identity.Api.dll --environment Production
```

## ✅ 7. Testes de Integração

### 7.1 Verificar Health Check

```bash
curl http://localhost:5001/health
```

### 7.2 Testar Publicação de Evento

Use Postman ou curl para criar um usuário na API. Isso deve:

1. Publicar evento no SNS topic `user-events`
2. Fan-out para `produtor-sync-queue`
3. Publicar email no SNS `email-notifications`
4. Enfileirar na `email-queue`
5. Lambda processar e enviar email via SES

### 7.3 Monitorar CloudWatch Logs

```bash
aws logs tail /aws/lambda/AgroSolutions-EmailProcessor --follow
```

### 7.4 Verificar Filas

```bash
# Email Queue
aws sqs get-queue-attributes \
  --queue-url https://sqs.us-east-1.amazonaws.com/$ACCOUNT_ID/agrosolutions-email-queue \
  --attribute-names ApproximateNumberOfMessages

# Produtor Sync Queue
aws sqs get-queue-attributes \
  --queue-url https://sqs.us-east-1.amazonaws.com/$ACCOUNT_ID/agrosolutions-produtor-sync-queue \
  --attribute-names ApproximateNumberOfMessages
```

### 7.5 Verificar DLQ

```bash
aws sqs get-queue-attributes \
  --queue-url https://sqs.us-east-1.amazonaws.com/$ACCOUNT_ID/agrosolutions-email-queue-dlq \
  --attribute-names ApproximateNumberOfMessages
```

Se houver mensagens na DLQ, investigue os erros.

## 📊 8. Monitoramento

### 8.1 CloudWatch Metrics

- **SQS**: NumberOfMessagesSent, NumberOfMessagesReceived, ApproximateAgeOfOldestMessage
- **SNS**: NumberOfMessagesPublished, NumberOfNotificationsDelivered
- **Lambda**: Invocations, Errors, Duration, Throttles
- **SES**: Send, Delivery, Bounce, Complaint

### 8.2 Criar Alarmes

```bash
# Lambda Errors
aws cloudwatch put-metric-alarm \
  --alarm-name EmailLambda-Errors \
  --alarm-description "Alert on Lambda errors" \
  --metric-name Errors \
  --namespace AWS/Lambda \
  --statistic Sum \
  --period 300 \
  --threshold 5 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=FunctionName,Value=AgroSolutions-EmailProcessor \
  --evaluation-periods 1

# DLQ Messages
aws cloudwatch put-metric-alarm \
  --alarm-name EmailQueue-DLQ \
  --alarm-description "Alert on DLQ messages" \
  --metric-name ApproximateNumberOfMessagesVisible \
  --namespace AWS/SQS \
  --statistic Average \
  --period 300 \
  --threshold 1 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=QueueName,Value=agrosolutions-email-queue-dlq \
  --evaluation-periods 1
```

## 💰 9. Estimativa de Custos

### Uso Moderado (10k usuários, 1k emails/dia)

- **SQS**: $0.40/milhão de requests → ~$0.50/mês
- **SNS**: $0.50/milhão de publicações → ~$0.20/mês
- **SES**: $0.10/1000 emails → ~$3.00/mês
- **Lambda**: $0.20/milhão de requests + $0.0000166667/GB-segundo → ~$1.00/mês
- **CloudWatch**: Logs e métricas → ~$5.00/mês

**Total estimado**: ~$10/mês

### Free Tier (Primeiro Ano)

- SQS: 1 milhão de requests/mês grátis
- SNS: 1 milhão de publicações/mês grátis
- SES: 62.000 emails/mês grátis (via EC2)
- Lambda: 1 milhão de requests/mês + 400.000 GB-segundo grátis

**Total primeiro ano**: ~$0-5/mês (dependendo do uso de CloudWatch)

## 🔒 10. Melhores Práticas de Segurança

1. **IAM Roles**: Sempre prefira IAM roles a credenciais hardcoded
2. **Least Privilege**: Dê apenas as permissões necessárias
3. **Encryption at Rest**: Habilite KMS encryption nas filas SQS
4. **VPC**: Execute a API dentro de VPC com security groups apropriados
5. **Secrets Manager**: Armazene segredos (Keycloak credentials) no AWS Secrets Manager
6. **SES Sandbox**: Por padrão, SES está em sandbox (só envia para emails verificados). Solicite saída do sandbox para produção.

## 🆘 11. Troubleshooting

### API não se conecta ao AWS

**Erro**: `Unable to get IAM security credentials`

**Solução**: Verifique credenciais AWS com `aws sts get-caller-identity`

### Lambda não recebe mensagens

**Erro**: Event source mapping desabilitado

**Solução**:
```bash
aws lambda list-event-source-mappings --function-name AgroSolutions-EmailProcessor
aws lambda update-event-source-mapping --uuid <UUID> --enabled
```

### Emails não são enviados

**Erro**: `Email address is not verified`

**Solução**: Verifique os emails no SES ou solicite saída do sandbox

### Mensagens indo para DLQ

**Erro**: Falhas repetidas no processamento

**Solução**: 
1. Verifique CloudWatch Logs da Lambda
2. Reveja IAM permissions da Lambda
3. Teste manualmente invocando a Lambda

### Custos inesperados

**Problema**: Conta AWS acima do esperado

**Solução**:
1. Configure Cost Explorer
2. Habilite billing alerts
3. Revise logs do CloudWatch (maior custo comum)
4. Configure log retention (padrão: infinito)

```bash
aws logs put-retention-policy \
  --log-group-name /aws/lambda/AgroSolutions-EmailProcessor \
  --retention-in-days 30
```

---

## 📚 Recursos Adicionais

- [AWS SDK for .NET](https://aws.amazon.com/sdk-for-net/)
- [MassTransit Amazon SQS](https://masstransit.io/documentation/transports/amazon-sqs)
- [AWS SES Developer Guide](https://docs.aws.amazon.com/ses/)
- [AWS Lambda .NET Guide](https://docs.aws.amazon.com/lambda/latest/dg/lambda-csharp.html)
