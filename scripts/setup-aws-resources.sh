#!/bin/bash

# AgroSolutions Identity Service - AWS Resources Setup Script
# Este script cria todos os recursos AWS necessários: SQS, SNS, SES

set -e  # Exit on any error

echo "🚀 AgroSolutions Identity Service - AWS Setup"
echo "=============================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Verificar se AWS CLI está instalado
if ! command -v aws &> /dev/null; then
    echo -e "${RED}❌ AWS CLI não encontrado. Instale: https://aws.amazon.com/cli/${NC}"
    exit 1
fi

# Verificar credenciais AWS
echo "🔐 Verificando credenciais AWS..."
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}❌ Credenciais AWS inválidas. Execute: aws configure${NC}"
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=${AWS_DEFAULT_REGION:-us-east-1}

echo -e "${GREEN}✓ Credenciais válidas${NC}"
echo -e "  Account ID: ${YELLOW}$ACCOUNT_ID${NC}"
echo -e "  Region: ${YELLOW}$AWS_REGION${NC}"
echo ""

# Confirmar com usuário
read -p "Deseja continuar com a criação dos recursos AWS? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Operação cancelada."
    exit 0
fi

echo ""
echo "================================================"
echo "1️⃣  Criando Filas SQS..."
echo "================================================"

# Criar filas SQS principais
declare -a queues=(
    "agrosolutions-identity-events"
    "agrosolutions-email-queue"
    "agrosolutions-produtor-sync-queue"
    "agrosolutions-status-changed-queue"
)

for queue in "${queues[@]}"; do
    echo -n "  Criando fila: $queue... "
    if aws sqs create-queue --queue-name "$queue" --region "$AWS_REGION" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${YELLOW}(já existe)${NC}"
    fi
done

echo ""
echo "================================================"
echo "2️⃣  Criando Dead Letter Queues (DLQ)..."
echo "================================================"

declare -a dlqs=(
    "agrosolutions-identity-events-dlq"
    "agrosolutions-email-queue-dlq"
    "agrosolutions-produtor-sync-queue-dlq"
    "agrosolutions-status-changed-queue-dlq"
)

for dlq in "${dlqs[@]}"; do
    echo -n "  Criando DLQ: $dlq... "
    if aws sqs create-queue --queue-name "$dlq" --region "$AWS_REGION" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${YELLOW}(já existe)${NC}"
    fi
done

echo ""
echo "================================================"
echo "3️⃣  Configurando Redrive Policies (SQS → DLQ)..."
echo "================================================"

# Função para configurar redrive policy
configure_redrive() {
    local queue_name=$1
    local dlq_name=$2
    
    echo -n "  Configurando $queue_name → $dlq_name... "
    
    # Obter URL da fila
    local queue_url=$(aws sqs get-queue-url --queue-name "$queue_name" --region "$AWS_REGION" --query 'QueueUrl' --output text 2>/dev/null)
    
    # Obter ARN da DLQ
    local dlq_url=$(aws sqs get-queue-url --queue-name "$dlq_name" --region "$AWS_REGION" --query 'QueueUrl' --output text 2>/dev/null)
    local dlq_arn=$(aws sqs get-queue-attributes --queue-url "$dlq_url" --attribute-names QueueArn --region "$AWS_REGION" --query 'Attributes.QueueArn' --output text 2>/dev/null)
    
    # Configurar redrive policy
    local redrive_policy="{\"deadLetterTargetArn\":\"$dlq_arn\",\"maxReceiveCount\":\"3\"}"
    
    if aws sqs set-queue-attributes \
        --queue-url "$queue_url" \
        --attributes "{\"RedrivePolicy\":\"$(echo $redrive_policy | sed 's/"/\\"/g')\"}" \
        --region "$AWS_REGION" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${YELLOW}(falhou)${NC}"
    fi
}

configure_redrive "agrosolutions-email-queue" "agrosolutions-email-queue-dlq"
configure_redrive "agrosolutions-produtor-sync-queue" "agrosolutions-produtor-sync-queue-dlq"
configure_redrive "agrosolutions-status-changed-queue" "agrosolutions-status-changed-queue-dlq"
configure_redrive "agrosolutions-identity-events" "agrosolutions-identity-events-dlq"

echo ""
echo "================================================"
echo "4️⃣  Criando Tópicos SNS..."
echo "================================================"

declare -a topics=(
    "agrosolutions-user-events"
    "agrosolutions-email-notifications"
    "agrosolutions-property-events"
)

for topic in "${topics[@]}"; do
    echo -n "  Criando tópico: $topic... "
    if aws sns create-topic --name "$topic" --region "$AWS_REGION" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${YELLOW}(já existe)${NC}"
    fi
done

echo ""
echo "================================================"
echo "5️⃣  Criando Subscriptions (SNS → SQS)..."
echo "================================================"

# Função para criar subscription
create_subscription() {
    local topic_name=$1
    local queue_name=$2
    
    echo -n "  $topic_name → $queue_name... "
    
    local topic_arn="arn:aws:sns:$AWS_REGION:$ACCOUNT_ID:$topic_name"
    local queue_arn="arn:aws:sqs:$AWS_REGION:$ACCOUNT_ID:$queue_name"
    
    if aws sns subscribe \
        --topic-arn "$topic_arn" \
        --protocol sqs \
        --notification-endpoint "$queue_arn" \
        --region "$AWS_REGION" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${YELLOW}(já existe)${NC}"
    fi
}

create_subscription "agrosolutions-user-events" "agrosolutions-produtor-sync-queue"
create_subscription "agrosolutions-email-notifications" "agrosolutions-email-queue"

echo ""
echo "================================================"
echo "6️⃣  Configurando SQS Policies (permitir SNS)..."
echo "================================================"

# Função para configurar policy
configure_sqs_policy() {
    local queue_name=$1
    local topic_name=$2
    
    echo -n "  Permitir $topic_name → $queue_name... "
    
    local queue_url=$(aws sqs get-queue-url --queue-name "$queue_name" --region "$AWS_REGION" --query 'QueueUrl' --output text 2>/dev/null)
    local queue_arn="arn:aws:sqs:$AWS_REGION:$ACCOUNT_ID:$queue_name"
    local topic_arn="arn:aws:sns:$AWS_REGION:$ACCOUNT_ID:$topic_name"
    
    local policy=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "sns.amazonaws.com"
      },
      "Action": "sqs:SendMessage",
      "Resource": "$queue_arn",
      "Condition": {
        "ArnEquals": {
          "aws:SourceArn": "$topic_arn"
        }
      }
    }
  ]
}
EOF
)
    
    if aws sqs set-queue-attributes \
        --queue-url "$queue_url" \
        --attributes "{\"Policy\":\"$(echo $policy | sed 's/"/\\"/g' | tr -d '\n')\"}" \
        --region "$AWS_REGION" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${YELLOW}(falhou)${NC}"
    fi
}

configure_sqs_policy "agrosolutions-produtor-sync-queue" "agrosolutions-user-events"
configure_sqs_policy "agrosolutions-email-queue" "agrosolutions-email-notifications"

echo ""
echo "================================================"
echo "7️⃣  Verificando Emails no SES..."
echo "================================================"

declare -a emails=(
    "noreply@agrosolutions.com.br"
    "admin@agrosolutions.com.br"
    "suporte@agrosolutions.com.br"
)

echo -e "${YELLOW}⚠️  Você precisará clicar nos links de verificação enviados para cada email.${NC}"
echo ""

for email in "${emails[@]}"; do
    echo -n "  Enviando verificação para: $email... "
    if aws ses verify-email-identity --email-address "$email" --region "$AWS_REGION" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${YELLOW}(já verificado ou erro)${NC}"
    fi
done

echo ""
echo -e "${YELLOW}📧 Verifique os emails e clique nos links de confirmação.${NC}"
echo ""

# Verificar status das verificações
echo "  Status das verificações:"
for email in "${emails[@]}"; do
    status=$(aws ses get-identity-verification-attributes \
        --identities "$email" \
        --region "$AWS_REGION" \
        --query "VerificationAttributes.\"$email\".VerificationStatus" \
        --output text 2>/dev/null || echo "Unknown")
    
    if [ "$status" = "Success" ]; then
        echo -e "    $email: ${GREEN}✓ Verificado${NC}"
    elif [ "$status" = "Pending" ]; then
        echo -e "    $email: ${YELLOW}⏳ Pendente${NC}"
    else
        echo -e "    $email: ${RED}✗ Não verificado${NC}"
    fi
done

echo ""
echo "================================================"
echo "8️⃣  Criando Configuration Set do SES..."
echo "================================================"

echo -n "  Criando configuration set: agrosolutions-production... "
if aws ses create-configuration-set \
    --configuration-set Name=agrosolutions-production \
    --region "$AWS_REGION" > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}(já existe)${NC}"
fi

echo ""
echo "================================================"
echo "✅ Setup Concluído!"
echo "================================================"
echo ""
echo -e "${GREEN}Recursos criados com sucesso:${NC}"
echo ""
echo "📦 SQS Queues:"
for queue in "${queues[@]}"; do
    echo "  - $queue"
done
echo ""
echo "💀 Dead Letter Queues:"
for dlq in "${dlqs[@]}"; do
    echo "  - $dlq"
done
echo ""
echo "📢 SNS Topics:"
for topic in "${topics[@]}"; do
    echo "  - arn:aws:sns:$AWS_REGION:$ACCOUNT_ID:$topic"
done
echo ""
echo "📧 SES Emails (verificar inbox):"
for email in "${emails[@]}"; do
    echo "  - $email"
done
echo ""
echo "================================================"
echo "🎯 Próximos Passos:"
echo "================================================"
echo ""
echo "1. Verificar emails do SES (clique nos links enviados)"
echo ""
echo "2. Atualizar appsettings.Production.json com o ACCOUNT_ID:"
echo -e "   ${YELLOW}sed -i 's/ACCOUNT_ID/$ACCOUNT_ID/g' src/AgroSolutions.Identity.Api/appsettings.Production.json${NC}"
echo ""
echo "3. Deploy da Lambda Function:"
echo "   cd lambda/EmailLambda"
echo "   dotnet lambda deploy-function AgroSolutions-EmailProcessor"
echo ""
echo "4. Criar Event Source Mapping (SQS → Lambda):"
echo "   aws lambda create-event-source-mapping \\"
echo "     --function-name AgroSolutions-EmailProcessor \\"
echo "     --event-source-arn arn:aws:sqs:$AWS_REGION:$ACCOUNT_ID:agrosolutions-email-queue \\"
echo "     --batch-size 10 \\"
echo "     --enabled"
echo ""
echo "5. Rodar a API:"
echo "   dotnet run --project src/AgroSolutions.Identity.Api --environment Production"
echo ""
echo -e "${GREEN}Para mais detalhes, consulte: docs/AWS_DEPLOYMENT.md${NC}"
echo ""
