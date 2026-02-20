#!/bin/bash

###################################################################################
# Script de Verificação do Cluster EKS - AgroSolutions Identity Service
###################################################################################
#
# Verifica status e saúde do cluster EKS
#
###################################################################################

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Variáveis
CLUSTER_NAME="agrosolutions-eks-cluster"
AWS_REGION="sa-east-1"
NAMESPACE="agrosolutions-identity"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  AgroSolutions - Status do Cluster EKS${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Verificar se cluster existe
echo -e "${YELLOW}🔍 Verificando se cluster existe...${NC}"
if ! aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} &>/dev/null; then
    echo -e "${RED}❌ Cluster ${CLUSTER_NAME} não encontrado na região ${AWS_REGION}${NC}"
    echo ""
    echo -e "${YELLOW}Para criar o cluster, execute:${NC}"
    echo -e "  ./scripts/create-eks-cluster.sh"
    echo ""
    exit 1
fi

CLUSTER_STATUS=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --query 'cluster.status' --output text)
echo -e "${GREEN}✅ Cluster encontrado: ${CLUSTER_STATUS}${NC}"
echo ""

# Verificar conectividade kubectl
echo -e "${YELLOW}🔍 Verificando conectividade kubectl...${NC}"
if kubectl cluster-info &>/dev/null; then
    echo -e "${GREEN}✅ kubectl conectado${NC}"
else
    echo -e "${RED}❌ kubectl não conectado${NC}"
    echo ""
    echo -e "${YELLOW}Para conectar, execute:${NC}"
    echo -e "  aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${AWS_REGION}"
    echo ""
    exit 1
fi
echo ""

# Informações do cluster
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}📊 Informações do Cluster${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

CLUSTER_VERSION=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --query 'cluster.version' --output text)
CLUSTER_ENDPOINT=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --query 'cluster.endpoint' --output text)
CLUSTER_ARN=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --query 'cluster.arn' --output text)
VPC_ID=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --query 'cluster.resourcesVpcConfig.vpcId' --output text)

echo -e "  ${YELLOW}Nome:${NC} ${CLUSTER_NAME}"
echo -e "  ${YELLOW}Região:${NC} ${AWS_REGION}"
echo -e "  ${YELLOW}Versão K8s:${NC} ${CLUSTER_VERSION}"
echo -e "  ${YELLOW}Status:${NC} ${CLUSTER_STATUS}"
echo -e "  ${YELLOW}VPC:${NC} ${VPC_ID}"
echo -e "  ${YELLOW}Endpoint:${NC} ${CLUSTER_ENDPOINT}"
echo ""

# Nodes
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}🖥️  Nodes${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
kubectl get nodes -o wide

READY_NODES=$(kubectl get nodes --no-headers | grep -c " Ready ")
TOTAL_NODES=$(kubectl get nodes --no-headers | wc -l)

echo ""
echo -e "  ${GREEN}Nodes Ready: ${READY_NODES}/${TOTAL_NODES}${NC}"
echo ""

# Uso de recursos dos nodes
if command -v kubectl top &> /dev/null; then
    echo -e "${YELLOW}📊 Uso de Recursos dos Nodes:${NC}"
    kubectl top nodes 2>/dev/null || echo -e "${YELLOW}  ⏳ Metrics Server ainda não disponível${NC}"
    echo ""
fi

# Node Groups
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}👥 Node Groups${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

aws eks list-nodegroups --cluster-name ${CLUSTER_NAME} --region ${AWS_REGION} --query 'nodegroups' --output text | while read nodegroup; do
    if [ -n "$nodegroup" ]; then
        STATUS=$(aws eks describe-nodegroup --cluster-name ${CLUSTER_NAME} --nodegroup-name ${nodegroup} --region ${AWS_REGION} --query 'nodegroup.status' --output text)
        DESIRED=$(aws eks describe-nodegroup --cluster-name ${CLUSTER_NAME} --nodegroup-name ${nodegroup} --region ${AWS_REGION} --query 'nodegroup.scalingConfig.desiredSize' --output text)
        MIN=$(aws eks describe-nodegroup --cluster-name ${CLUSTER_NAME} --nodegroup-name ${nodegroup} --region ${AWS_REGION} --query 'nodegroup.scalingConfig.minSize' --output text)
        MAX=$(aws eks describe-nodegroup --cluster-name ${CLUSTER_NAME} --nodegroup-name ${nodegroup} --region ${AWS_REGION} --query 'nodegroup.scalingConfig.maxSize' --output text)
        INSTANCE_TYPE=$(aws eks describe-nodegroup --cluster-name ${CLUSTER_NAME} --nodegroup-name ${nodegroup} --region ${AWS_REGION} --query 'nodegroup.instanceTypes[0]' --output text 2>/dev/null || echo "mixed")
        
        echo -e "  ${YELLOW}${nodegroup}:${NC}"
        echo -e "    Status: ${STATUS}"
        echo -e "    Instances: ${DESIRED} (min: ${MIN}, max: ${MAX})"
        echo -e "    Type: ${INSTANCE_TYPE}"
        echo ""
    fi
done

# Namespaces
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}📁 Namespaces${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
kubectl get namespaces
echo ""

# Status da aplicação
if kubectl get namespace ${NAMESPACE} &>/dev/null; then
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}🚀 Aplicação (${NAMESPACE})${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    echo -e "${YELLOW}Pods:${NC}"
    kubectl get pods -n ${NAMESPACE} -o wide
    echo ""
    
    RUNNING_PODS=$(kubectl get pods -n ${NAMESPACE} --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    TOTAL_PODS=$(kubectl get pods -n ${NAMESPACE} --no-headers 2>/dev/null | wc -l || echo "0")
    
    if [ "$TOTAL_PODS" -gt 0 ]; then
        echo -e "  ${GREEN}Pods Running: ${RUNNING_PODS}/${TOTAL_PODS}${NC}"
        echo ""
        
        echo -e "${YELLOW}Services:${NC}"
        kubectl get svc -n ${NAMESPACE}
        echo ""
        
        echo -e "${YELLOW}Deployments:${NC}"
        kubectl get deployments -n ${NAMESPACE}
        echo ""
        
        echo -e "${YELLOW}HPA (Horizontal Pod Autoscaler):${NC}"
        kubectl get hpa -n ${NAMESPACE} 2>/dev/null || echo "  Nenhum HPA configurado"
        echo ""
        
        echo -e "${YELLOW}Ingress:${NC}"
        kubectl get ingress -n ${NAMESPACE} 2>/dev/null || echo "  Nenhum Ingress configurado"
        echo ""
        
        # Uso de recursos dos pods
        if command -v kubectl top &> /dev/null; then
            echo -e "${YELLOW}📊 Uso de Recursos dos Pods:${NC}"
            kubectl top pods -n ${NAMESPACE} 2>/dev/null || echo -e "${YELLOW}  ⏳ Metrics Server ainda não disponível${NC}"
            echo ""
        fi
    else
        echo -e "${YELLOW}  ⚠️  Nenhum pod deployado ainda${NC}"
        echo ""
    fi
else
    echo -e "${YELLOW}⚠️  Namespace ${NAMESPACE} não encontrado${NC}"
    echo -e "${YELLOW}A aplicação ainda não foi deployada.${NC}"
    echo ""
fi

# Add-ons e System Components
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}🔌 Add-ons e Componentes do Sistema${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

echo -e "${YELLOW}Deployments em kube-system:${NC}"
kubectl get deployment -n kube-system
echo ""

echo -e "${YELLOW}DaemonSets em kube-system:${NC}"
kubectl get daemonset -n kube-system
echo ""

# Storage Classes
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}💾 Storage Classes${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
kubectl get storageclass
echo ""

# PVCs se existirem
PVC_COUNT=$(kubectl get pvc -n ${NAMESPACE} --no-headers 2>/dev/null | wc -l)
if [ "$PVC_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}Persistent Volume Claims:${NC}"
    kubectl get pvc -n ${NAMESPACE}
    echo ""
fi

# Eventos recentes
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}📋 Eventos Recentes (últimos 10)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
kubectl get events -n ${NAMESPACE} --sort-by='.lastTimestamp' 2>/dev/null | tail -n 10 || echo -e "${YELLOW}  Nenhum evento no namespace ${NAMESPACE}${NC}"
echo ""

# Health Summary
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}💚 Resumo de Saúde${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Verificar se cluster está saudável
ISSUES=0

if [ "$CLUSTER_STATUS" != "ACTIVE" ]; then
    echo -e "${RED}❌ Cluster status: ${CLUSTER_STATUS}${NC}"
    ISSUES=$((ISSUES + 1))
else
    echo -e "${GREEN}✅ Cluster: ACTIVE${NC}"
fi

if [ "$READY_NODES" -lt "$TOTAL_NODES" ]; then
    echo -e "${YELLOW}⚠️  Nodes: ${READY_NODES}/${TOTAL_NODES} ready${NC}"
    ISSUES=$((ISSUES + 1))
else
    echo -e "${GREEN}✅ Nodes: ${READY_NODES}/${TOTAL_NODES} ready${NC}"
fi

if [ "$TOTAL_PODS" -gt 0 ]; then
    if [ "$RUNNING_PODS" -lt "$TOTAL_PODS" ]; then
        echo -e "${YELLOW}⚠️  Pods: ${RUNNING_PODS}/${TOTAL_PODS} running${NC}"
        ISSUES=$((ISSUES + 1))
    else
        echo -e "${GREEN}✅ Pods: ${RUNNING_PODS}/${TOTAL_PODS} running${NC}"
    fi
fi

# Verificar componentes críticos
COREDNS_READY=$(kubectl get deployment coredns -n kube-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
if [ "$COREDNS_READY" -gt 0 ]; then
    echo -e "${GREEN}✅ CoreDNS: Running${NC}"
else
    echo -e "${RED}❌ CoreDNS: Not ready${NC}"
    ISSUES=$((ISSUES + 1))
fi

ALB_CONTROLLER_READY=$(kubectl get deployment aws-load-balancer-controller -n kube-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
if [ "$ALB_CONTROLLER_READY" -gt 0 ]; then
    echo -e "${GREEN}✅ AWS Load Balancer Controller: Running${NC}"
else
    echo -e "${YELLOW}⚠️  AWS Load Balancer Controller: Not deployed${NC}"
fi

METRICS_SERVER_READY=$(kubectl get deployment metrics-server -n kube-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
if [ "$METRICS_SERVER_READY" -gt 0 ]; then
    echo -e "${GREEN}✅ Metrics Server: Running${NC}"
else
    echo -e "${YELLOW}⚠️  Metrics Server: Not deployed${NC}"
fi

echo ""

if [ $ISSUES -eq 0 ]; then
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✅ Cluster está saudável! Tudo funcionando corretamente.${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
else
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}⚠️  ${ISSUES} problema(s) detectado(s). Verifique os detalhes acima.${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
fi

echo ""
