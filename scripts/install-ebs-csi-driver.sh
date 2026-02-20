#!/bin/bash
set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Instalando AWS EBS CSI Driver no EKS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

CLUSTER_NAME="agrosolutions-eks-cluster"
REGION="sa-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "📋 Cluster: $CLUSTER_NAME"
echo "📋 Região: $REGION"
echo "📋 Account ID: $ACCOUNT_ID"
echo ""

# 1. Criar IAM Role para EBS CSI Driver
echo "🔐 Criando IAM Service Account para EBS CSI Driver..."
eksctl create iamserviceaccount \
  --name ebs-csi-controller-sa \
  --namespace kube-system \
  --cluster $CLUSTER_NAME \
  --region $REGION \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve \
  --role-name AmazonEKS_EBS_CSI_DriverRole \
  --override-existing-serviceaccounts

echo "✅ Service Account criado com sucesso!"
echo ""

# 2. Instalar o add-on EBS CSI Driver
echo "📦 Instalando add-on aws-ebs-csi-driver..."

# Obter ARN da role criada
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/AmazonEKS_EBS_CSI_DriverRole"
echo "📋 Role ARN: $ROLE_ARN"

aws eks create-addon \
  --cluster-name $CLUSTER_NAME \
  --addon-name aws-ebs-csi-driver \
  --service-account-role-arn $ROLE_ARN \
  --region $REGION || echo "⚠️  Add-on já existe, continuando..."

echo ""
echo "⏳ Aguardando add-on ficar ativo..."
aws eks wait addon-active \
  --cluster-name $CLUSTER_NAME \
  --addon-name aws-ebs-csi-driver \
  --region $REGION

echo "✅ EBS CSI Driver instalado com sucesso!"
echo ""

# 3. Verificar pods do EBS CSI Driver
echo "🔍 Verificando pods do EBS CSI Driver..."
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ EBS CSI Driver instalado e pronto para uso!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
