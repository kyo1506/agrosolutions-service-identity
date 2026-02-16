# Guia de Configuração Manual AWS - AgroSolutions Identity Service

## ⚙️ Configuração Inicial

**Região:** `sa-east-1` (São Paulo)  
**Account ID:** `405114419969`

---

## 📦 Passo 1: Criar Filas SQS

Execute os comandos abaixo para criar as filas SQS:

```bash
# Região
export AWS_REGION=sa-east-1

# 1.1 - Criar filas principais
aws sqs create-queue --queue-name agrosolutions-identity-events --region $AWS_REGION
aws sqs create-queue --queue-name agrosolutions-email-queue --region $AWS_REGION
aws sqs create-queue --queue-name agrosolutions-produtor-sync-queue --region $AWS_REGION
aws sqs create-queue --queue-name agrosolutions-status-changed-queue --region $AWS_REGION

# 1.2 - Criar Dead Letter Queues (DLQ)
aws sqs create-queue --queue-name agrosolutions-identity-events-dlq --region $AWS_REGION
aws sqs create-queue --queue-name agrosolutions-email-queue-dlq --region $AWS_REGION
aws sqs create-queue --queue-name agrosolutions-produtor-sync-queue-dlq --region $AWS_REGION
aws sqs create-queue --queue-name agrosolutions-status-changed-queue-dlq --region $AWS_REGION
```

### Verificar criação:
```bash
aws sqs list-queues --region sa-east-1 | grep agrosolutions
```

Você deve ver **8 filas** listadas.

---

## 💀 Passo 2: Configurar Redrive Policies (DLQ)

Configure cada fila para enviar mensagens com falha para sua respectiva DLQ:

```bash
# Obter ARNs das DLQs
DLQ_IDENTITY_EVENTS=$(aws sqs get-queue-attributes \
  --queue-url https://sqs.sa-east-1.amazonaws.com/405114419969/agrosolutions-identity-events-dlq \
  --attribute-names QueueArn \
  --region sa-east-1 \
  --query 'Attributes.QueueArn' \
  --output text)

DLQ_EMAIL=$(aws sqs get-queue-attributes \
  --queue-url https://sqs.sa-east-1.amazonaws.com/405114419969/agrosolutions-email-queue-dlq \
  --attribute-names QueueArn \
  --region sa-east-1 \
  --query 'Attributes.QueueArn' \
  --output text)

DLQ_PRODUTOR=$(aws sqs get-queue-attributes \
  --queue-url https://sqs.sa-east-1.amazonaws.com/405114419969/agrosolutions-produtor-sync-queue-dlq \
  --attribute-names QueueArn \
  --region sa-east-1 \
  --query 'Attributes.QueueArn' \
  --output text)

DLQ_STATUS=$(aws sqs get-queue-attributes \
  --queue-url https://sqs.sa-east-1.amazonaws.com/405114419969/agrosolutions-status-changed-queue-dlq \
  --attribute-names QueueArn \
  --region sa-east-1 \
  --query 'Attributes.QueueArn' \
  --output text)

# Configurar Redrive Policies
aws sqs set-queue-attributes \
  --queue-url https://sqs.sa-east-1.amazonaws.com/405114419969/agrosolutions-identity-events \
  --attributes "{\"RedrivePolicy\":\"{\\\"deadLetterTargetArn\\\":\\\"$DLQ_IDENTITY_EVENTS\\\",\\\"maxReceiveCount\\\":\\\"3\\\"}\"}" \
  --region sa-east-1

aws sqs set-queue-attributes \
  --queue-url https://sqs.sa-east-1.amazonaws.com/405114419969/agrosolutions-email-queue \
  --attributes "{\"RedrivePolicy\":\"{\\\"deadLetterTargetArn\\\":\\\"$DLQ_EMAIL\\\",\\\"maxReceiveCount\\\":\\\"3\\\"}\"}" \
  --region sa-east-1

aws sqs set-queue-attributes \
  --queue-url https://sqs.sa-east-1.amazonaws.com/405114419969/agrosolutions-produtor-sync-queue \
  --attributes "{\"RedrivePolicy\":\"{\\\"deadLetterTargetArn\\\":\\\"$DLQ_PRODUTOR\\\",\\\"maxReceiveCount\\\":\\\"3\\\"}\"}" \
  --region sa-east-1

aws sqs set-queue-attributes \
  --queue-url https://sqs.sa-east-1.amazonaws.com/405114419969/agrosolutions-status-changed-queue \
  --attributes "{\"RedrivePolicy\":\"{\\\"deadLetterTargetArn\\\":\\\"$DLQ_STATUS\\\",\\\"maxReceiveCount\\\":\\\"3\\\"}\"}" \
  --region sa-east-1
```

---

## 📢 Passo 3: Criar Tópicos SNS

```bash
aws sns create-topic --name agrosolutions-user-events --region sa-east-1
aws sns create-topic --name agrosolutions-email-notifications --region sa-east-1
aws sns create-topic --name agrosolutions-property-events --region sa-east-1
```

### Verificar criação:
```bash
aws sns list-topics --region sa-east-1 | grep agrosolutions
```

Você deve ver **3 tópicos** listados.

---

## 🔗 Passo 4: Criar Subscriptions (SNS → SQS)

```bash
# 4.1 - agrosolutions-user-events → agrosolutions-produtor-sync-queue
aws sns subscribe \
  --topic-arn arn:aws:sns:sa-east-1:405114419969:agrosolutions-user-events \
  --protocol sqs \
  --notification-endpoint arn:aws:sqs:sa-east-1:405114419969:agrosolutions-produtor-sync-queue \
  --region sa-east-1

# 4.2 - agrosolutions-email-notifications → agrosolutions-email-queue
aws sns subscribe \
  --topic-arn arn:aws:sns:sa-east-1:405114419969:agrosolutions-email-notifications \
  --protocol sqs \
  --notification-endpoint arn:aws:sqs:sa-east-1:405114419969:agrosolutions-email-queue \
  --region sa-east-1
```

---

## 🔐 Passo 5: Configurar Policies SQS (Permitir SNS)

Crie as policies para permitir que os tópicos SNS enviem mensagens para as filas SQS:

```bash
# 5.1 - Policy para agrosolutions-produtor-sync-queue
aws sqs set-queue-attributes \
  --queue-url https://sqs.sa-east-1.amazonaws.com/405114419969/agrosolutions-produtor-sync-queue \
  --attributes '{
    "Policy": "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"sns.amazonaws.com\"},\"Action\":\"sqs:SendMessage\",\"Resource\":\"arn:aws:sqs:sa-east-1:405114419969:agrosolutions-produtor-sync-queue\",\"Condition\":{\"ArnEquals\":{\"aws:SourceArn\":\"arn:aws:sns:sa-east-1:405114419969:agrosolutions-user-events\"}}}]}"
  }' \
  --region sa-east-1

# 5.2 - Policy para agrosolutions-email-queue
aws sqs set-queue-attributes \
  --queue-url https://sqs.sa-east-1.amazonaws.com/405114419969/agrosolutions-email-queue \
  --attributes '{
    "Policy": "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"sns.amazonaws.com\"},\"Action\":\"sqs:SendMessage\",\"Resource\":\"arn:aws:sqs:sa-east-1:405114419969:agrosolutions-email-queue\",\"Condition\":{\"ArnEquals\":{\"aws:SourceArn\":\"arn:aws:sns:sa-east-1:405114419969:agrosolutions-email-notifications\"}}}]}"
  }' \
  --region sa-east-1
```

---

## 📧 Passo 6: Verificar Emails no SES

### ⚠️ ATENÇÃO: Escolha a Opção Correta

Os endereços `noreply@agrosolutions.com.br`, `admin@agrosolutions.com.br` e `suporte@agrosolutions.com.br` são **placeholders**. Se esses domínios não existem ou você não tem acesso às caixas de entrada, **NUNCA receberá os links de verificação**.

### 🎯 Escolha UMA das 3 opções abaixo:

---

### **Opção A: Emails Reais para Testes (Recomendado para Dev/Staging)**

Use emails que você realmente controla (Gmail, Outlook, etc.):

```bash
# Exemplo: usar seu email real
aws ses verify-email-identity --email-address seu-email@gmail.com --region sa-east-1
aws ses verify-email-identity --email-address outro-email@outlook.com --region sa-east-1
```

✅ Você receberá os emails de verificação da AWS no seu Gmail/Outlook  
✅ Clique nos links para verificar  
✅ Use esses emails como remetente em testes

**Atualizar appsettings.Production.json:**
```json
"SES": {
  "FromEmail": "seu-email@gmail.com",
  "VerifiedEmails": [
    "seu-email@gmail.com",
    "outro-email@outlook.com"
  ]
}
```

---

### **Opção B: Verificar Domínio Completo (Recomendado para Produção)**

Se você é **dono do domínio** `agrosolutions.com.br` e tem acesso ao DNS:

```bash
# Solicitar verificação de domínio
aws ses verify-domain-identity --domain agrosolutions.com.br --region sa-east-1
```

**Saída esperada:**
```
{
  "VerificationToken": "abc123xyz..."
}
```

**Adicionar registro DNS TXT:**
- **Nome:** `_amazonses.agrosolutions.com.br`
- **Tipo:** `TXT`
- **Valor:** `<VerificationToken retornado>`

**Verificar status:**
```bash
aws ses get-identity-verification-attributes \
  --identities agrosolutions.com.br \
  --region sa-east-1
```

✅ Depois de verificado, pode enviar de **qualquer** email @agrosolutions.com.br  
✅ Não precisa verificar emails individuais  

---

### **Opção C: Usar Emails Fictícios (Apenas para desenvolvimento local sem envio real)**

Se você **NÃO vai realmente enviar emails** (apenas testes locais):

```bash
# Criar os emails fictícios (vão ficar Pending permanentemente)
aws ses verify-email-identity --email-address noreply@agrosolutions.com.br --region sa-east-1
aws ses verify-email-identity --email-address admin@agrosolutions.com.br --region sa-east-1
aws ses verify-email-identity --email-address suporte@agrosolutions.com.br --region sa-east-1
```

⚠️ **Status ficará "Pending" para sempre**  
⚠️ **Não poderá enviar emails reais**  
⚠️ Útil apenas para testes sem envio real

---

### Verificar status dos emails:
```bash
aws ses get-identity-verification-attributes \
  --identities noreply@agrosolutions.com.br admin@agrosolutions.com.br suporte@agrosolutions.com.br \
  --region sa-east-1
```

O status deve ser **"Success"** para enviar emails (apenas Opções A e B).

---

## ⚙️ Passo 7: Criar Configuration Set no SES

```bash
aws ses create-configuration-set \
  --configuration-set Name=agrosolutions-production \
  --region sa-east-1
```

---

## ✅ Passo 8: Verificação Final

Execute este comando para verificar todos os recursos:

```bash
echo "=== SQS QUEUES ===" && \
aws sqs list-queues --region sa-east-1 | grep agrosolutions | wc -l && \
echo "" && \
echo "=== SNS TOPICS ===" && \
aws sns list-topics --region sa-east-1 | grep agrosolutions | wc -l && \
echo "" && \
echo "=== SES IDENTITIES ===" && \
aws ses list-identities --region sa-east-1 | grep agrosolutions
```

**Resultado esperado:**
- **8 filas SQS** (4 principais + 4 DLQs)
- **3 tópicos SNS**
- **3 identidades SES** (pendentes até você clicar nos links)

---

## 🚀 Passo 9: Deploy da Lambda Function (Opcional - Para Emails)

### 9.1 - Instalar AWS Lambda Tools para .NET

Primeiro, instale a ferramenta de deploy da AWS Lambda:

```bash
# Instalar Amazon Lambda Tools (ferramenta global)
dotnet tool install -g Amazon.Lambda.Tools

# Verificar instalação
dotnet lambda --version
```

### 9.2 - Deploy da Lambda Function

```bash
cd lambda/EmailLambda

# Deploy da função Lambda
dotnet lambda deploy-function AgroSolutions-EmailProcessor \
  --region sa-east-1 \
  --function-role lambda-execution-role \
  --environment-variables "FROM_EMAIL=vinicius_pinheiro02@hotmail.com;FROM_NAME=AgroSolutions"
```

**Nota:** Se você não tiver uma IAM Role criada, o comando irá te guiar para criar uma automaticamente.

### Configurar Event Source Mapping (Lambda → SQS):
```bash
aws lambda create-event-source-mapping \
  --function-name AgroSolutions-EmailProcessor \
  --event-source-arn arn:aws:sqs:sa-east-1:405114419969:agrosolutions-email-queue \
  --batch-size 10 \
  --enabled \
  --region sa-east-1
```

---

## 🧹 Limpeza Completa (Se necessário)

Para remover TODOS os recursos:

```bash
# Remover Subscriptions
aws sns list-subscriptions --region sa-east-1 --query "Subscriptions[?contains(TopicArn, 'agrosolutions')].SubscriptionArn" --output text | tr '\t' '\n' | xargs -I {} aws sns unsubscribe --subscription-arn {} --region sa-east-1

# Remover Tópicos SNS
aws sns delete-topic --topic-arn arn:aws:sns:sa-east-1:405114419969:agrosolutions-user-events --region sa-east-1
aws sns delete-topic --topic-arn arn:aws:sns:sa-east-1:405114419969:agrosolutions-email-notifications --region sa-east-1
aws sns delete-topic --topic-arn arn:aws:sns:sa-east-1:405114419969:agrosolutions-property-events --region sa-east-1

# Remover Filas SQS
for queue in identity-events email-queue produtor-sync-queue status-changed-queue identity-events-dlq email-queue-dlq produtor-sync-queue-dlq status-changed-queue-dlq; do
  aws sqs delete-queue --queue-url https://sqs.sa-east-1.amazonaws.com/405114419969/agrosolutions-$queue --region sa-east-1 2>/dev/null
done

# Remover Identidades SES
aws ses delete-identity --identity noreply@agrosolutions.com.br --region sa-east-1
aws ses delete-identity --identity admin@agrosolutions.com.br --region sa-east-1
aws ses delete-identity --identity suporte@agrosolutions.com.br --region sa-east-1

# Remover Configuration Set
aws ses delete-configuration-set --configuration-set-name agrosolutions-production --region sa-east-1
```

---

## 📝 Notas Importantes

1. **Região:** Todos os comandos usam `sa-east-1` (São Paulo)
2. **SES Sandbox:** Por padrão, o SES está em modo sandbox. Para enviar emails para qualquer endereço, você precisa solicitar saída do sandbox no console AWS
3. **Custos:** Recursos SQS e SNS têm custo mínimo. SES tem 62.000 emails grátis/mês com EC2
4. **Lambda:** A função Lambda é opcional. A API pode publicar diretamente no SNS
5. **⚠️ Emails Fictícios:** Os emails `@agrosolutions.com.br` usados no projeto são placeholders. Para testes reais, use emails que você controla ou verifique o domínio completo (ver Passo 6)

---

## 🔍 Troubleshooting

### Erro: "Queue already exists"
```bash
aws sqs delete-queue --queue-url <URL> --region sa-east-1
# Aguarde 60 segundos e tente criar novamente
```

### Erro: "Topic already exists"  
Se o tópico já existe, você pode listar o ARN:
```bash
aws sns list-topics --region sa-east-1 | grep agrosolutions
```

### Verificar se mensagens estão sendo entregues:
```bash
# Ver mensagens na fila
aws sqs receive-message --queue-url https://sqs.sa-east-1.amazonaws.com/405114419969/agrosolutions-email-queue --region sa-east-1
```

### Emails SES ficam "Pending" para sempre:
**Causa:** Os endereços de email não existem ou você não tem acesso à caixa de entrada.

**Solução:** 
- **Para testes:** Use emails reais que você controla (Gmail, Outlook)
- **Para produção:** Verifique o domínio completo via DNS (ver Passo 6, Opção B)

```bash
# Remover emails pendentes
aws ses delete-identity --identity email@exemplo.com --region sa-east-1

# Adicionar email real
aws ses verify-email-identity --email-address seu-email-real@gmail.com --region sa-east-1
```

### Como enviar email de teste:
```bash
aws ses send-email \
  --from seu-email-verificado@gmail.com \
  --destination "ToAddresses=destinatario@exemplo.com" \
  --message "Subject={Data=Teste},Body={Text={Data=Mensagem de teste}}" \
  --region sa-east-1
```

**Nota:** No modo Sandbox, você só pode enviar para emails verificados.
