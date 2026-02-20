#!/bin/bash

###################################################################################
# Script para corrigir ALB Controller e Service Accounts IRSA
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
echo -e "${BLUE}  Corrigindo ALB Controller e Service Accounts IRSA${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Associar OIDC provider (necessário para IRSA)
echo -e "${YELLOW}🔗 Associando IAM OIDC provider ao cluster...${NC}"
eksctl utils associate-iam-oidc-provider \
  --cluster=${CLUSTER_NAME} \
  --region=${AWS_REGION} \
  --approve

echo -e "${GREEN}✅ OIDC provider associado${NC}"
echo ""

# Deletar ALB Controller existente
echo -e "${YELLOW}🗑️  Deletando ALB Controller existente...${NC}"
helm uninstall aws-load-balancer-controller -n kube-system 2>/dev/null || echo "  Helm release não encontrado"
kubectl delete deployment aws-load-balancer-controller -n kube-system 2>/dev/null || echo "  Deployment não encontrado"
kubectl delete service aws-load-balancer-webhook-service -n kube-system 2>/dev/null || echo "  Service não encontrado"
echo -e "${GREEN}✅ ALB Controller removido${NC}"
echo ""

# Criar Service Account para ALB Controller
echo -e "${YELLOW}📝 Criando Service Account para ALB Controller...${NC}"
eksctl create iamserviceaccount \
  --cluster=${CLUSTER_NAME} \
  --region=${AWS_REGION} \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess \
  --override-existing-serviceaccounts \
  --approve

echo -e "${GREEN}✅ Service Account criada${NC}"
echo ""

# Obter VPC ID
VPC_ID=$(aws eks describe-cluster \
    --name ${CLUSTER_NAME} \
    --region ${AWS_REGION} \
    --query "cluster.resourcesVpcConfig.vpcId" \
    --output text)

# Reinstalar ALB Controller
echo -e "${YELLOW}📦 Instalando AWS Load Balancer Controller...${NC}"
helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
    -n kube-system \
    --set clusterName=${CLUSTER_NAME} \
    --set serviceAccount.create=false \
    --set serviceAccount.name=aws-load-balancer-controller \
    --set region=${AWS_REGION} \
    --set vpcId=${VPC_ID}

echo -e "${GREEN}✅ AWS Load Balancer Controller instalado${NC}"
echo ""

# Aguardar pods ficarem prontos
echo -e "${YELLOW}⏳ Aguardando pods do ALB Controller ficarem prontos...${NC}"
kubectl wait --namespace kube-system \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/name=aws-load-balancer-controller \
    --timeout=180s

echo -e "${GREEN}✅ ALB Controller pronto!${NC}"
echo ""

# Verificar webhook
echo -e "${YELLOW}🔍 Verificando webhook...${NC}"
kubectl get endpoints aws-load-balancer-webhook-service -n kube-system

echo ""
echo -e "${GREEN}✅ Webhook pronto com endpoints!${NC}"
echo ""

# Instalar Metrics Server agora que webhook está pronto
echo -e "${YELLOW}📊 Reinstalando Metrics Server...${NC}"
kubectl delete -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml 2>/dev/null || true
sleep 5
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

echo -e "${GREEN}✅ Metrics Server instalado${NC}"
echo ""

# Status final
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ Correções aplicadas com sucesso!${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${YELLOW}📊 Status dos Componentes:${NC}"
kubectl get deployment -n kube-system | grep -E "NAME|aws-load-balancer|coredns|metrics"
echo ""

echo -e "${YELLOW}🔗 Próximos Passos:${NC}"
echo ""
echo -e "1. ${BLUE}Verificar status completo:${NC}"
echo -e "   ./check-cluster-status.sh"
echo ""
echo -e "2. ${BLUE}Deploy da aplicação:${NC}"
echo -e "   kubectl apply -f ../k8s/production/"
echo ""
