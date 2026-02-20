#!/bin/bash

###################################################################################
# Script para aguardar nodes ficarem prontos e completar setup
###################################################################################

set -e

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CLUSTER_NAME="agrosolutions-eks-cluster"
AWS_REGION="sa-east-1"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Aguardando Node Groups e Completando Setup${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${YELLOW}⏳ Aguardando stacks do CloudFormation completarem...${NC}"
echo ""

# Aguardar stack primary-nodes
echo -e "${YELLOW}Verificando primary-nodes...${NC}"
aws cloudformation wait stack-create-complete \
    --stack-name eksctl-agrosolutions-eks-cluster-nodegroup-primary-nodes \
    --region ${AWS_REGION} && \
    echo -e "${GREEN}✅ primary-nodes: CREATE_COMPLETE${NC}" || \
    echo -e "${RED}❌ primary-nodes: FAILED${NC}"

# Aguardar stack observability-nodes
echo -e "${YELLOW}Verificando observability-nodes...${NC}"
aws cloudformation wait stack-create-complete \
    --stack-name eksctl-agrosolutions-eks-cluster-nodegroup-observability-nodes \
    --region ${AWS_REGION} && \
    echo -e "${GREEN}✅ observability-nodes: CREATE_COMPLETE${NC}" || \
    echo -e "${RED}❌ observability-nodes: FAILED${NC}"

echo ""
echo -e "${YELLOW}⏳ Aguardando nodes registrarem no cluster...${NC}"
sleep 30

# Verificar nodes
kubectl get nodes
echo ""

# Aguardar todos os nodes ficarem Ready
echo -e "${YELLOW}⏳ Aguardando nodes ficarem Ready...${NC}"
kubectl wait --for=condition=Ready nodes --all --timeout=300s

echo ""
echo -e "${GREEN}✅ Todos os nodes estão Ready!${NC}"
echo ""

# Reinstalar Metrics Server agora que há nodes
echo -e "${YELLOW}📊 Instalando Metrics Server...${NC}"
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

echo ""
echo -e "${YELLOW}⏳ Aguardando Metrics Server ficar pronto...${NC}"
kubectl wait --namespace kube-system \
    --for=condition=ready pod \
    --selector=k8s-app=metrics-server \
    --timeout=120s

echo ""
echo -e "${GREEN}✅ Metrics Server pronto!${NC}"
echo ""

# Aguardar ALB Controller ficar pronto
echo -e "${YELLOW}⏳ Aguardando ALB Controller ficar pronto...${NC}"
kubectl wait --namespace kube-system \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/name=aws-load-balancer-controller \
    --timeout=180s

echo ""
echo -e "${GREEN}✅ ALB Controller pronto!${NC}"
echo ""

# Status final
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ Setup do cluster completado com sucesso!${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${YELLOW}📊 Status Final:${NC}"
kubectl get nodes -o wide
echo ""

echo -e "${YELLOW}🔗 Próximos Passos:${NC}"
echo ""
echo -e "1. ${BLUE}Verificar status completo:${NC}"
echo -e "   ./check-cluster-status.sh"
echo ""
echo -e "2. ${BLUE}Configurar GitHub Secrets:${NC}"
echo -e "   Siga: .github/SECRETS_SETUP.md"
echo ""
echo -e "3. ${BLUE}Deploy:${NC}"
echo -e "   kubectl apply -f ../k8s/production/"
echo ""
