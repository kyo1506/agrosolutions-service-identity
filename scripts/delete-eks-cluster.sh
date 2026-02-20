#!/bin/bash

###################################################################################
# Script de Deleção do Cluster EKS - AgroSolutions Identity Service
###################################################################################
#
# Este script remove completamente o cluster EKS e todos os recursos associados.
# 
# ⚠️  ATENÇÃO: Esta operação é IRREVERSÍVEL!
#
###################################################################################

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Variáveis
CLUSTER_NAME="agrosolutions-eks-cluster"
AWS_REGION="sa-east-1"

echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}  ⚠️  DELEÇÃO DO CLUSTER EKS${NC}"
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Cluster: ${CLUSTER_NAME}${NC}"
echo -e "${YELLOW}Região: ${AWS_REGION}${NC}"
echo ""
echo -e "${RED}Esta ação irá:${NC}"
echo -e "  • Deletar todos os pods, services e deployments"
echo -e "  • Remover Load Balancers e volumes EBS"
echo -e "  • Destruir os node groups"
echo -e "  • Deletar o cluster EKS"
echo -e "  • Remover a VPC e recursos de rede"
echo ""
echo -e "${RED}⚠️  ESTA OPERAÇÃO É IRREVERSÍVEL!${NC}"
echo ""

read -p "Digite o nome do cluster para confirmar: " CONFIRM_NAME

if [ "$CONFIRM_NAME" != "$CLUSTER_NAME" ]; then
    echo -e "${RED}❌ Nome incorreto. Operação cancelada.${NC}"
    exit 1
fi

echo ""
read -p "Tem certeza absoluta? (digite 'DELETE' em maiúsculas): " FINAL_CONFIRM

if [ "$FINAL_CONFIRM" != "DELETE" ]; then
    echo -e "${RED}❌ Operação cancelada.${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}🗑️  Iniciando processo de deleção...${NC}"
echo ""

# Função para limpar Load Balancers (importante para evitar recursos órfãos)
cleanup_load_balancers() {
    echo -e "${YELLOW}🔍 Verificando Load Balancers...${NC}"
    
    # Deletar ingresses (que criam ALBs)
    kubectl delete ingress --all -n agrosolutions-identity 2>/dev/null || true
    
    # Aguardar alguns segundos para ALB ser removido
    echo -e "${YELLOW}⏳ Aguardando remoção de Load Balancers...${NC}"
    sleep 30
    
    echo -e "${GREEN}✅ Load Balancers removidos${NC}"
}

# Função para limpar PVCs (volumes EBS)
cleanup_volumes() {
    echo -e "${YELLOW}🔍 Verificando volumes persistentes...${NC}"
    
    # Deletar PVCs
    kubectl delete pvc --all -n agrosolutions-identity 2>/dev/null || true
    
    # Aguardar alguns segundos para volumes serem removidos
    echo -e "${YELLOW}⏳ Aguardando remoção de volumes...${NC}"
    sleep 15
    
    echo -e "${GREEN}✅ Volumes removidos${NC}"
}

# Limpar recursos que podem criar dependências externas
if kubectl cluster-info &> /dev/null; then
    echo -e "${YELLOW}📦 Limpando recursos do Kubernetes...${NC}"
    
    cleanup_load_balancers
    cleanup_volumes
    
    # Deletar namespace (isso remove todos os recursos dentro dele)
    kubectl delete namespace agrosolutions-identity --ignore-not-found=true --timeout=120s 2>/dev/null || true
    
    echo -e "${GREEN}✅ Recursos do Kubernetes removidos${NC}"
    echo ""
else
    echo -e "${YELLOW}⚠️  Cluster não acessível via kubectl, pulando limpeza de recursos${NC}"
fi

# Deletar cluster usando eksctl
echo -e "${YELLOW}🗑️  Deletando cluster EKS...${NC}"
echo -e "${BLUE}Isso pode levar de 10 a 15 minutos...${NC}"
echo ""

eksctl delete cluster \
    --name ${CLUSTER_NAME} \
    --region ${AWS_REGION} \
    --wait

echo ""
echo -e "${GREEN}✅ Cluster deletado com sucesso!${NC}"
echo ""

# Verificar recursos órfãos
echo -e "${YELLOW}🔍 Verificando recursos órfãos...${NC}"
echo ""

echo -e "${BLUE}Load Balancers órfãos:${NC}"
aws elbv2 describe-load-balancers \
    --region ${AWS_REGION} \
    --query "LoadBalancers[?contains(LoadBalancerName, 'k8s-agrosolu')].LoadBalancerArn" \
    --output text 2>/dev/null || echo "Nenhum encontrado"

echo ""
echo -e "${BLUE}Volumes EBS órfãos:${NC}"
aws ec2 describe-volumes \
    --region ${AWS_REGION} \
    --filters "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" \
    --query "Volumes[?State=='available'].VolumeId" \
    --output text 2>/dev/null || echo "Nenhum encontrado"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ Deleção concluída!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}📊 Próximos passos (se necessário):${NC}"
echo ""
echo -e "1. ${BLUE}Verificar recursos órfãos no console AWS${NC}"
echo -e "   https://console.aws.amazon.com/vpc/home?region=${AWS_REGION}"
echo ""
echo -e "2. ${BLUE}Deletar CloudWatch Log Groups (opcional):${NC}"
echo -e "   aws logs delete-log-group --log-group-name /aws/eks/${CLUSTER_NAME}/cluster --region ${AWS_REGION}"
echo ""
echo -e "3. ${BLUE}Remover contexto kubectl:${NC}"
echo -e "   kubectl config delete-context arn:aws:eks:${AWS_REGION}:*:cluster/${CLUSTER_NAME}"
echo ""
