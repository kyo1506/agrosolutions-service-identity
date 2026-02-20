# 🛠️ Scripts de Gerenciamento do Cluster EKS

Scripts para criar, gerenciar e deletar o cluster EKS do AgroSolutions Identity Service.

---

## 📋 Scripts Disponíveis

### 1. `create-eks-cluster.sh` - Criar Cluster EKS 1.35

Cria um cluster EKS completo com toda infraestrutura necessária.

**Uso:**
```bash
chmod +x scripts/create-eks-cluster.sh
./scripts/create-eks-cluster.sh
```

**O que o script faz:**
- ✅ Verifica pré-requisitos (AWS CLI, eksctl, kubectl, helm)
- ✅ Cria cluster EKS 1.35
- ✅ Provisiona VPC dedicada (10.0.0.0/16)
- ✅ Cria 2 node groups:
  - **primary-nodes** (on-demand): 2x t3.medium (min: 2, max: 4)
  - **observability-nodes** (spot): 2x t3.large (min: 1, max: 3)
- ✅ Habilita OIDC para IRSA (IAM Roles for Service Accounts)
- ✅ Cria Service Accounts com IAM:
  - `aws-load-balancer-controller` (ALB Controller)
  - `ebs-csi-controller-sa` (EBS CSI Driver)
  - `identity-api-sa` (SQS, SNS, SES)
- ✅ Instala add-ons:
  - VPC-CNI, CoreDNS, kube-proxy
  - AWS EBS CSI Driver
  - AWS Load Balancer Controller
  - Metrics Server (para HPA)
- ✅ Configura Storage Class gp3 padrão
- ✅ Cria namespace `agrosolutions-identity`
- ✅ Habilita CloudWatch Logs (7 dias retenção)

**Tempo de execução:** ~15-20 minutos

**Custo estimado (sa-east-1):**
- EKS Control Plane: ~$73/mês
- 2x t3.medium nodes: ~$60/mês
- NAT Gateway: ~$45/mês
- EBS Volumes: ~$8/mês
- **Total: ~$186/mês**

---

### 2. `delete-eks-cluster.sh` - Deletar Cluster EKS

Deleta completamente o cluster e todos os recursos associados.

**Uso:**
```bash
chmod +x scripts/delete-eks-cluster.sh
./scripts/delete-eks-cluster.sh
```

**⚠️ ATENÇÃO:** Esta operação é **IRREVERSÍVEL**!

**O que o script faz:**
- ✅ Solicita confirmação dupla
- ✅ Remove Load Balancers criados via Ingress
- ✅ Remove volumes EBS (PVCs)
- ✅ Deleta namespace e todos os recursos
- ✅ Remove node groups
- ✅ Deleta cluster EKS
- ✅ Remove VPC e recursos de rede
- ✅ Verifica recursos órfãos

**Tempo de execução:** ~10-15 minutos

---

### 3. `init-db.sql` - Inicialização do Banco de Dados

Script SQL executado automaticamente pelo PostgreSQL ao iniciar (via `docker-compose.yml` ou deployment K8s).

**Função:**
- Cria database `outbox` para Outbox Pattern

---

## 🚀 Fluxo de Uso Completo

### Passo 1: Criar Cluster

```bash
# Executar script de criação
./scripts/create-eks-cluster.sh
```

**Aguarde a conclusão (~20 minutos)**

### Passo 2: Verificar Cluster

```bash
# Ver informações do cluster
kubectl cluster-info

# Ver nodes
kubectl get nodes

# Ver namespaces
kubectl get namespaces

# Ver add-ons
kubectl get deployment -n kube-system

# Ver storage classes
kubectl get storageclass
```

### Passo 3: Configurar Secrets do GitHub

Siga as instruções em [../.github/SECRETS_SETUP.md](../.github/SECRETS_SETUP.md)

### Passo 4: Criar IAM Role para Lambda

Execute os comandos da seção 9.2 de [../docs/AWS_SETUP_MANUAL.md](../docs/AWS_SETUP_MANUAL.md):

```bash
# Criar trust policy
cat > /tmp/lambda-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "lambda.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
EOF

# Criar role
aws iam create-role \
  --role-name AgroSolutions-Lambda-EmailProcessor-Role \
  --assume-role-policy-document file:///tmp/lambda-trust-policy.json

# ... (seguir resto do guia)
```

### Passo 5: Deploy da Aplicação

**Opção A: Via GitHub Actions (Recomendado)**
```bash
git add .
git commit -m "feat: initial deployment to EKS"
git push origin main

# Acompanhar deploy em:
# https://github.com/<seu-usuario>/agrosolutions-service-identity/actions
```

**Opção B: Deploy Manual**
```bash
# Aplicar todos os manifestos
kubectl apply -f k8s/production/namespace.yaml
kubectl apply -f k8s/production/configmaps.yaml
kubectl apply -f k8s/production/storage-class.yaml
kubectl apply -f k8s/production/volumes.yaml
kubectl apply -f k8s/production/databases.yaml
kubectl wait --for=condition=ready pod -l app=keycloak-db -n agrosolutions-identity --timeout=300s
kubectl apply -f k8s/production/services.yaml
kubectl apply -f k8s/production/infrastructure.yaml
kubectl apply -f k8s/production/deployment.yaml
kubectl apply -f k8s/production/hpa.yaml
kubectl apply -f k8s/production/ingress-aws.yaml
kubectl apply -f k8s/production/ingress-grafana.yaml
kubectl apply -f k8s/production/prometheus-rbac.yaml
kubectl apply -f k8s/production/observability.yaml
kubectl apply -f k8s/production/resource-configs.yaml

# Verificar deploy
kubectl get pods -n agrosolutions-identity
kubectl get svc -n agrosolutions-identity
kubectl get ingress -n agrosolutions-identity
```

### Passo 6: Verificar Aplicação

```bash
# Ver status dos pods
kubectl get pods -n agrosolutions-identity -o wide

# Ver logs
kubectl logs -f -l app=identity-api -n agrosolutions-identity

# Port-forward para testar localmente
kubectl port-forward svc/identity-api-service 8080:80 -n agrosolutions-identity
curl http://localhost:8080/v1/health
```

---

## 📊 Comandos Úteis

### Informações do Cluster

```bash
# Contexto atual
kubectl config current-context

# Informações do cluster
kubectl cluster-info

# Nodes detalhados
kubectl get nodes -o wide

# Uso de recursos dos nodes
kubectl top nodes

# Todos os pods em todos os namespaces
kubectl get pods -A
```

### Debugging

```bash
# Logs de um pod
kubectl logs <pod-name> -n agrosolutions-identity

# Logs anteriores (se o pod reiniciou)
kubectl logs <pod-name> -n agrosolutions-identity --previous

# Descrever pod (ver eventos)
kubectl describe pod <pod-name> -n agrosolutions-identity

# Shell em um pod
kubectl exec -it <pod-name> -n agrosolutions-identity -- /bin/sh

# Port forward
kubectl port-forward <pod-name> 8080:80 -n agrosolutions-identity
```

### Escalar Aplicação

```bash
# Escalar manualmente
kubectl scale deployment identity-api --replicas=3 -n agrosolutions-identity

# Ver status do HPA
kubectl get hpa -n agrosolutions-identity
kubectl describe hpa identity-api-hpa -n agrosolutions-identity

# Gerar carga (teste de auto-scaling)
kubectl run -i --tty load-generator --rm --image=busybox --restart=Never -- /bin/sh
# Dentro do pod:
# while true; do wget -q -O- http://identity-api-service.agrosolutions-identity/v1/health; done
```

### Gerenciamento de Recursos

```bash
# Ver uso de recursos
kubectl top pods -n agrosolutions-identity

# Ver eventos recentes
kubectl get events -n agrosolutions-identity --sort-by='.lastTimestamp'

# Ver todos os recursos em um namespace
kubectl get all -n agrosolutions-identity
```

---

## 🗑️ Deletar Cluster

**⚠️ CUIDADO:** Operação irreversível!

```bash
./scripts/delete-eks-cluster.sh
```

O script solicitará:
1. Nome do cluster para confirmar
2. Digite "DELETE" em maiúsculas

---

## 🔧 Troubleshooting

### Problema: "eksctl not found"

```bash
# macOS
brew install eksctl

# Linux
curl --silent --location "https://github.com/weksctl/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin
```

### Problema: "AWS credentials not configured"

```bash
aws configure
# Forneça: Access Key, Secret Key, região (sa-east-1), formato (json)

# Verificar
aws sts get-caller-identity
```

### Problema: "Insufficient capacity" ao criar nodes

**Causa:** Região/AZ sem capacidade para tipo de instância

**Solução:** Editar `/tmp/eks-cluster-config.yaml` e mudar `instanceType`:
```yaml
- t3.medium  # mudar para t3a.medium ou t3.small
```

### Problema: Load Balancer não provisiona

```bash
# Verificar logs do ALB controller
kubectl logs -n kube-system deployment/aws-load-balancer-controller

# Verificar service account
kubectl get sa -n kube-system aws-load-balancer-controller -o yaml

# Verificar se IRSA está funcionando
kubectl describe sa -n kube-system aws-load-balancer-controller | grep Annotations
```

### Problema: Pods ficam em "Pending"

```bash
# Ver eventos
kubectl describe pod <pod-name> -n agrosolutions-identity

# Causas comuns:
# 1. Sem recursos (CPU/memória) - escalar nodes
# 2. PVC não consegue provisionar - verificar EBS CSI driver
# 3. Taints/tolerations - verificar node selector
```

---

## 📚 Referências

- [Documentação eksctl](https://eksctl.io/)
- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)

---

**Última atualização:** 2026-02-19  
**Versão do Cluster:** EKS 1.35
