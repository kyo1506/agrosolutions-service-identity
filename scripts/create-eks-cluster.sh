#!/bin/bash

###################################################################################
# Script de Criação do Cluster EKS 1.35 - AgroSolutions Identity Service
###################################################################################
# 
# Este script cria um cluster EKS completo com toda infraestrutura necessária:
# - EKS Cluster versão 1.35
# - Node Groups (on-demand e spot)
# - VPC dedicada com subnets públicas e privadas
# - Add-ons: EBS CSI, Load Balancer Controller, Metrics Server
# - IRSA para serviços AWS (SQS, SNS, SES)
# - Configurações de auto-scaling
#
# Pré-requisitos:
# - AWS CLI configurado com credenciais válidas
# - eksctl instalado (https://eksctl.io)
# - kubectl instalado
# - helm instalado
#
###################################################################################

set -e  # Sair em caso de erro

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variáveis de configuração
CLUSTER_NAME="agrosolutions-eks-cluster"
AWS_REGION="sa-east-1"
AWS_ACCOUNT_ID="316295889438"
K8S_VERSION="1.35"
VPC_CIDR="10.0.0.0/16"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  AgroSolutions - EKS Cluster Setup (Kubernetes 1.35)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

###################################################################################
# Função: Verificar pré-requisitos
###################################################################################
check_prerequisites() {
    echo -e "${YELLOW}🔍 Verificando pré-requisitos...${NC}"
    
    # Verificar AWS CLI
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}❌ AWS CLI não encontrado. Instale: https://aws.amazon.com/cli/${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ AWS CLI: $(aws --version | cut -d' ' -f1)${NC}"
    
    # Verificar eksctl
    if ! command -v eksctl &> /dev/null; then
        echo -e "${RED}❌ eksctl não encontrado. Instale: https://eksctl.io${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ eksctl: $(eksctl version)${NC}"
    
    # Verificar kubectl
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}❌ kubectl não encontrado. Instale: https://kubernetes.io/docs/tasks/tools/${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ kubectl: $(kubectl version --client --short 2>/dev/null || kubectl version --client)${NC}"
    
    # Verificar helm
    if ! command -v helm &> /dev/null; then
        echo -e "${RED}❌ helm não encontrado. Instale: https://helm.sh${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ helm: $(helm version --short)${NC}"
    
    # Verificar credenciais AWS
    if ! aws sts get-caller-identity &> /dev/null; then
        echo -e "${RED}❌ Credenciais AWS inválidas ou não configuradas${NC}"
        exit 1
    fi
    
    CURRENT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
    CURRENT_USER=$(aws sts get-caller-identity --query Arn --output text)
    
    echo -e "${GREEN}✅ AWS Account: $CURRENT_ACCOUNT${NC}"
    echo -e "${GREEN}✅ AWS User: $CURRENT_USER${NC}"
    
    if [ "$CURRENT_ACCOUNT" != "$AWS_ACCOUNT_ID" ]; then
        echo -e "${YELLOW}⚠️  Aviso: Account ID atual ($CURRENT_ACCOUNT) difere do configurado ($AWS_ACCOUNT_ID)${NC}"
        read -p "Deseja continuar? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
        AWS_ACCOUNT_ID=$CURRENT_ACCOUNT
    fi
    
    echo ""
}

###################################################################################
# Função: Criar configuração do cluster
###################################################################################
create_cluster_config() {
    echo -e "${YELLOW}📝 Criando configuração do cluster...${NC}"
    
    cat > /tmp/eks-cluster-config.yaml <<EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: ${CLUSTER_NAME}
  region: ${AWS_REGION}
  version: "${K8S_VERSION}"
  tags:
    Environment: production
    Project: agrosolutions
    Service: identity
    ManagedBy: eksctl
    CreatedAt: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# VPC Configuration
vpc:
  cidr: ${VPC_CIDR}
  nat:
    gateway: Single  # Usar um único NAT Gateway (economia de custos)
  clusterEndpoints:
    publicAccess: true
    privateAccess: true

# IAM Configuration
iam:
  withOIDC: true  # Habilitar OIDC para IRSA (IAM Roles for Service Accounts)
  serviceAccounts:
    # Service Account para AWS Load Balancer Controller
    - metadata:
        name: aws-load-balancer-controller
        namespace: kube-system
      wellKnownPolicies:
        awsLoadBalancerController: true
    
    # Service Account para EBS CSI Driver
    - metadata:
        name: ebs-csi-controller-sa
        namespace: kube-system
      wellKnownPolicies:
        ebsCSIController: true
    
    # Service Account para aplicação Identity (SQS, SNS, SES)
    - metadata:
        name: identity-api-sa
        namespace: agrosolutions-identity
      attachPolicyARNs:
        - arn:aws:iam::aws:policy/AmazonSQSFullAccess
        - arn:aws:iam::aws:policy/AmazonSNSFullAccess
        - arn:aws:iam::aws:policy/AmazonSESFullAccess

# Managed Node Groups
managedNodeGroups:
  # Node Group Principal (On-Demand - Free Tier Eligible)
  - name: primary-nodes
    instanceType: m7i-flex.large  # Free Tier eligible - 2 vCPU, 8 GB RAM
    minSize: 2
    maxSize: 4
    desiredCapacity: 2
    volumeSize: 30
    volumeType: gp3
    privateNetworking: true
    labels:
      role: primary
      workload: general
    tags:
      Name: ${CLUSTER_NAME}-primary-node
      k8s.io/cluster-autoscaler/enabled: "true"
      k8s.io/cluster-autoscaler/${CLUSTER_NAME}: "owned"
    iam:
      withAddonPolicies:
        imageBuilder: true
        autoScaler: true
        ebs: true
        efs: true
        albIngress: true
        cloudWatch: true
    ssh:
      allow: false  # Desabilitar SSH por segurança

# Add-ons do cluster
addons:
  - name: vpc-cni
    version: latest
    attachPolicyARNs:
      - arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
    
  - name: coredns
    version: latest
    
  - name: kube-proxy
    version: latest
    
  - name: aws-ebs-csi-driver
    version: latest
    wellKnownPolicies:
      ebsCSIController: true

# CloudWatch Logging
cloudWatch:
  clusterLogging:
    enableTypes:
      - api
      - audit
      - authenticator
      - controllerManager
      - scheduler
    logRetentionInDays: 7

EOF

    echo -e "${GREEN}✅ Configuração criada em /tmp/eks-cluster-config.yaml${NC}"
    echo ""
}

###################################################################################
# Função: Verificar se cluster já existe
###################################################################################
check_cluster_exists() {
    if eksctl get cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} &> /dev/null; then
        echo -e "${YELLOW}⚠️  Cluster '${CLUSTER_NAME}' já existe na região ${AWS_REGION}${NC}"
        echo -e "${YELLOW}Pulando criação do cluster...${NC}"
        echo ""
        return 0  # Cluster existe
    fi
    return 1  # Cluster não existe
}

###################################################################################
# Função: Verificar e criar node groups se necessário
###################################################################################
check_and_create_nodegroups() {
    echo -e "${YELLOW}🔍 Verificando node groups...${NC}"
    
    NODEGROUP_COUNT=$(eksctl get nodegroup --cluster ${CLUSTER_NAME} --region ${AWS_REGION} --output json 2>/dev/null | jq '. | length' || echo "0")
    
    if [ "$NODEGROUP_COUNT" -eq 0 ]; then
        echo -e "${YELLOW}⚠️  Nenhum node group encontrado. Criando node groups...${NC}"
        echo -e "${BLUE}Isso pode levar de 5 a 10 minutos...${NC}"
        echo ""
        
        # Criar apenas os node groups usando o arquivo de configuração
        eksctl create nodegroup --config-file=/tmp/eks-cluster-config.yaml
        
        echo -e "${GREEN}✅ Node groups criados com sucesso!${NC}"
        echo ""
    else
        echo -e "${GREEN}✅ Node groups já existem ($NODEGROUP_COUNT encontrados)${NC}"
        echo ""
    fi
}

###################################################################################
# Função: Criar cluster EKS
###################################################################################
create_cluster() {
    echo -e "${YELLOW}🚀 Criando cluster EKS...${NC}"
    echo -e "${BLUE}Isso pode levar de 15 a 20 minutos...${NC}"
    echo ""
    
    eksctl create cluster -f /tmp/eks-cluster-config.yaml
    
    echo -e "${GREEN}✅ Cluster criado com sucesso!${NC}"
    echo ""
}

###################################################################################
# Função: Configurar kubectl context
###################################################################################
configure_kubectl() {
    echo -e "${YELLOW}⚙️  Configurando kubectl...${NC}"
    
    aws eks update-kubeconfig \
        --region ${AWS_REGION} \
        --name ${CLUSTER_NAME}
    
    echo -e "${GREEN}✅ kubectl configurado${NC}"
    
    # Verificar conexão
    echo ""
    echo -e "${YELLOW}🔍 Verificando cluster...${NC}"
    kubectl cluster-info
    kubectl get nodes
    echo ""
}

###################################################################################
# Função: Instalar AWS Load Balancer Controller
###################################################################################
install_alb_controller() {
    # Verificar se já está instalado
    if helm list -n kube-system | grep -q aws-load-balancer-controller; then
        echo -e "${YELLOW}⚠️  AWS Load Balancer Controller já está instalado${NC}"
        echo -e "${YELLOW}Verificando se webhook está pronto...${NC}"
    else
        echo -e "${YELLOW}📦 Instalando AWS Load Balancer Controller...${NC}"
        
        # Adicionar repositório Helm
        helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
        helm repo update
        
        # Instalar AWS Load Balancer Controller
        helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
            -n kube-system \
            --set clusterName=${CLUSTER_NAME} \
            --set serviceAccount.create=false \
            --set serviceAccount.name=aws-load-balancer-controller \
            --set region=${AWS_REGION} \
            --set vpcId=$(aws eks describe-cluster \
                --name ${CLUSTER_NAME} \
                --region ${AWS_REGION} \
                --query "cluster.resourcesVpcConfig.vpcId" \
                --output text)
        
        echo -e "${GREEN}✅ AWS Load Balancer Controller instalado${NC}"
    fi
    
    # Aguardar webhook ficar pronto (crítico para próximos passos)
    echo -e "${YELLOW}⏳ Aguardando webhook do ALB Controller ficar pronto...${NC}"
    
    # Aguardar pods ficarem prontos
    kubectl wait --namespace kube-system \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/name=aws-load-balancer-controller \
        --timeout=180s 2>/dev/null || {
            echo -e "${YELLOW}⚠️  Timeout aguardando pods. Verificando deployment...${NC}"
            kubectl rollout status deployment/aws-load-balancer-controller -n kube-system --timeout=60s || true
        }
    
    # Verificar se webhook service tem endpoints
    echo -e "${YELLOW}⏳ Verificando endpoints do webhook...${NC}"
    for i in {1..30}; do
        ENDPOINTS=$(kubectl get endpoints aws-load-balancer-webhook-service -n kube-system -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || echo "")
        if [ -n "$ENDPOINTS" ]; then
            echo -e "${GREEN}✅ ALB Controller webhook pronto (endpoints: $ENDPOINTS)${NC}"
            echo ""
            return 0
        fi
        echo -e "${YELLOW}  Tentativa $i/30: Aguardando endpoints...${NC}"
        sleep 2
    done
    
    echo -e "${YELLOW}⚠️  Webhook ainda sem endpoints, mas continuando...${NC}"
    echo ""
}

###################################################################################
# Função: Instalar Metrics Server (para HPA)
###################################################################################
install_metrics_server() {
    echo -e "${YELLOW}📊 Instalando Metrics Server...${NC}"
    
    # Tentar instalar Metrics Server
    # O erro do webhook é não-fatal; se falhar, tentar novamente após pequeno delay
    if ! kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml 2>&1; then
        echo -e "${YELLOW}⚠️  Erro ao aplicar Metrics Server (provavelmente webhook não pronto)${NC}"
        echo -e "${YELLOW}⏳ Aguardando 10s e tentando novamente...${NC}"
        sleep 10
        
        # Segunda tentativa
        if ! kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml 2>&1; then
            echo -e "${YELLOW}⚠️  Segunda tentativa falhou. Continuando sem Metrics Server.${NC}"
            echo -e "${YELLOW}💡 Execute manualmente depois:${NC}"
            echo -e "   kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
            echo ""
            return 0
        fi
    fi
    
    echo -e "${GREEN}✅ Metrics Server instalado${NC}"
    echo ""
}

###################################################################################
# Função: Criar namespaces
###################################################################################
create_namespaces() {
    echo -e "${YELLOW}📁 Criando namespaces...${NC}"
    
    kubectl create namespace agrosolutions-identity --dry-run=client -o yaml | kubectl apply -f -
    kubectl label namespace agrosolutions-identity environment=production --overwrite
    
    echo -e "${GREEN}✅ Namespace agrosolutions-identity criado${NC}"
    echo ""
}

###################################################################################
# Função: Configurar Storage Class padrão
###################################################################################
configure_storage() {
    echo -e "${YELLOW}💾 Configurando Storage Classes...${NC}"
    
    # Marcar gp2 como não-padrão (caso exista)
    kubectl annotate storageclass gp2 storageclass.kubernetes.io/is-default-class=false --overwrite 2>/dev/null || true
    
    # Aplicar storage class gp3 do projeto (caminho relativo ao diretório do workspace)
    STORAGE_CLASS_FILE="../k8s/production/storage-class.yaml"
    if [ -f "$STORAGE_CLASS_FILE" ]; then
        kubectl apply -f "$STORAGE_CLASS_FILE"
        echo -e "${GREEN}✅ Storage Classes configuradas${NC}"
    else
        echo -e "${YELLOW}⚠️  Arquivo storage-class.yaml não encontrado em $STORAGE_CLASS_FILE${NC}"
        echo -e "${YELLOW}Storage class será criada durante deploy da aplicação${NC}"
    fi
    echo ""
}

###################################################################################
# Função: Verificar status do cluster
###################################################################################
verify_cluster() {
    echo -e "${YELLOW}🔍 Verificando status do cluster...${NC}"
    echo ""
    
    echo -e "${BLUE}Nodes:${NC}"
    kubectl get nodes -o wide
    echo ""
    
    echo -e "${BLUE}Namespaces:${NC}"
    kubectl get namespaces
    echo ""
    
    echo -e "${BLUE}Add-ons:${NC}"
    kubectl get deployment -n kube-system
    echo ""
    
    echo -e "${BLUE}Storage Classes:${NC}"
    kubectl get storageclass
    echo ""
    
    echo -e "${BLUE}Service Accounts (IRSA):${NC}"
    kubectl get sa -n kube-system aws-load-balancer-controller 2>/dev/null && echo "✅ ALB Controller SA" || echo "❌ ALB Controller SA"
    kubectl get sa -n kube-system ebs-csi-controller-sa 2>/dev/null && echo "✅ EBS CSI SA" || echo "❌ EBS CSI SA"
    kubectl get sa -n agrosolutions-identity identity-api-sa 2>/dev/null && echo "✅ Identity API SA" || echo "⏳ Identity API SA (será criado no deploy)"
    echo ""
}

###################################################################################
# Função: Exibir informações finais
###################################################################################
display_summary() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✅ Cluster EKS criado com sucesso!${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}📋 Informações do Cluster:${NC}"
    echo -e "  • Nome: ${CLUSTER_NAME}"
    echo -e "  • Região: ${AWS_REGION}"
    echo -e "  • Versão K8s: ${K8S_VERSION}"
    echo -e "  • Account ID: ${AWS_ACCOUNT_ID}"
    echo ""
    echo -e "${YELLOW}🔗 Próximos Passos:${NC}"
    echo ""
    echo -e "1. ${BLUE}Configurar GitHub Secrets:${NC}"
    echo -e "   Siga: .github/SECRETS_SETUP.md"
    echo ""
    echo -e "2. ${BLUE}Criar IAM Role para Lambda:${NC}"
    echo -e "   Execute comandos da seção 9.2 de docs/AWS_SETUP_MANUAL.md"
    echo ""
    echo -e "3. ${BLUE}Deploy via GitHub Actions:${NC}"
    echo -e "   git push origin main"
    echo ""
    echo -e "4. ${BLUE}OU Deploy Manual:${NC}"
    echo -e "   kubectl apply -f k8s/production/"
    echo ""
    echo -e "${YELLOW}📊 Monitoramento:${NC}"
    echo -e "  • Console EKS: https://console.aws.amazon.com/eks/home?region=${AWS_REGION}#/clusters/${CLUSTER_NAME}"
    echo -e "  • CloudWatch Logs: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#logsV2:log-groups/log-group/\\/aws\\/eks\\/${CLUSTER_NAME}"
    echo ""
    echo -e "${YELLOW}💰 Estimativa de Custos (sa-east-1):${NC}"
    echo -e "  • EKS Control Plane: ~\$73/mês"
    echo -e "  • Nodes (2x m7i-flex.large): ~\$80/mês"
    echo -e "  • NAT Gateway: ~\$45/mês"
    echo -e "  • EBS Volumes (60GB gp3): ~\$6/mês"
    echo -e "  ${BLUE}Total estimado: ~\$204/mês${NC}"
    echo -e "  ${GREEN}💡 Nodes Free Tier eligible (m7i-flex.large: 2 vCPU, 8GB RAM)${NC}"
    echo ""
    echo -e "${YELLOW}🗑️  Para deletar o cluster:${NC}"
    echo -e "  eksctl delete cluster --name ${CLUSTER_NAME} --region ${AWS_REGION}"
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

###################################################################################
# Main Execution
###################################################################################
main() {
    check_prerequisites
    
    # Verificar se cluster já existe
    if check_cluster_exists; then
        echo -e "${YELLOW}Continuando com configuração do cluster existente...${NC}"
        echo ""
        
        # Criar arquivo de configuração para poder criar node groups se necessário
        create_cluster_config
        
        # Verificar e criar node groups se não existirem
        check_and_create_nodegroups
    else
        echo -e "${YELLOW}⚠️  Este script criará um cluster EKS que gerará custos na AWS.${NC}"
        echo -e "${YELLOW}Estimativa: ~\$204/mês (sa-east-1) - Nodes Free Tier eligible${NC}"
        echo ""
        read -p "Deseja continuar? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}Operação cancelada.${NC}"
            exit 0
        fi
        echo ""
        
        create_cluster_config
        create_cluster
    fi
    
    configure_kubectl
    install_alb_controller
    install_metrics_server
    create_namespaces
    configure_storage
    verify_cluster
    display_summary
}

# Executar script
main "$@"
