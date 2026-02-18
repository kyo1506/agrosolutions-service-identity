# 🚀 CI/CD Pipeline - AgroSolutions Identity Service

## 📋 Visão Geral

O pipeline de CI/CD é executado automaticamente via **GitHub Actions** definido em `.github/workflows/deploy.yml`.

---

## 🔄 Trigger Automático

O workflow é disparado quando:
- ✅ Push na branch `main` ou `develop`
- ✅ Pull Request para `main`
- ✅ Execução manual via `workflow_dispatch`

---

## 📦 Jobs do Pipeline

### 1️⃣ Build and Test

**Execução**: Sempre (em todos os eventos)

**Passos**:
1. Checkout do código
2. Setup .NET SDK 10.0
3. Restore de dependências
4. Build da solution
5. Execução de testes unitários

**Resultado**: Valida que o código compila e testes passam.

---

### 2️⃣ Deploy to EKS

**Execução**: Apenas quando push em `main`

**Dependência**: `build-and-test` deve passar

**Passos**:
1. **Build Docker Image**
   - Build multi-stage com .NET 10 Alpine
   - Tag com `$(github.sha)` e `latest`
   
2. **Push para ECR**
   - Login no Amazon ECR
   - Push da imagem para `316295889438.dkr.ecr.sa-east-1.amazonaws.com/agrosolutions-identity-api`

3. **Deploy Kubernetes**
   ```bash
   kubectl apply -f k8s/production/namespace.yaml
   kubectl apply -f k8s/production/configmaps.yaml
   kubectl apply -f k8s/production/storage-class.yaml
   kubectl apply -f k8s/production/volumes.yaml
   kubectl apply -f k8s/production/databases.yaml
   kubectl apply -f k8s/production/services.yaml
   kubectl apply -f k8s/production/infrastructure.yaml
   kubectl apply -f k8s/production/deployment.yaml
   kubectl apply -f k8s/production/hpa.yaml
   kubectl apply -f k8s/production/ingress-aws.yaml
   kubectl apply -f k8s/production/ingress-grafana.yaml
   kubectl apply -f k8s/production/prometheus-rbac.yaml
   kubectl apply -f k8s/production/observability.yaml
   kubectl apply -f k8s/production/resource-configs.yaml
   ```

4. **Criação de Secrets Kubernetes**
   - `keycloak-client-secrets`
   - `jwt-secrets`
   - `database-secrets`
   - `aws-credentials`

5. **Verificação do Deploy**
   - Wait for rollout: `identity-api`, `keycloak`
   - Health checks
   - Status dos pods, services, ingress

6. **Rollback Automático**
   - Se houver falha, executa `kubectl rollout undo`

---

### 3️⃣ Deploy Lambda (Email Processor) ⭐ NOVO

**Execução**: Apenas quando:
- Push em `main` **E**
- Há mudanças no diretório `lambda/`

**Dependência**: `build-and-test` deve passar

**Detecção Inteligente**:
```bash
# Verifica mudanças apenas no código da Lambda
git diff --name-only HEAD~1 HEAD | grep -q '^lambda/'
```

**Passos**:

1. **Verificar IAM Role**
   - Confirma que `AgroSolutions-Lambda-EmailProcessor-Role` existe
   - Se não existe, **falha com mensagem clara** direcionando para [docs/AWS_SETUP_MANUAL.md](../docs/AWS_SETUP_MANUAL.md)

2. **Build Lambda**
   ```bash
   cd lambda/EmailLambda/
   dotnet restore
   dotnet build -c Release
   ```

3. **Deploy Lambda Function**
   ```bash
   dotnet lambda deploy-function AgroSolutions-EmailProcessor \
     --function-role AgroSolutions-Lambda-EmailProcessor-Role \
     --region sa-east-1 \
     --configuration Release \
     --function-runtime dotnet8 \
     --function-memory-size 512 \
     --function-timeout 300 \
     --environment-variables \
       ENVIRONMENT=Production \
       FROM_EMAIL=vinicius_pinheiro02@hotmail.com \
       FROM_NAME=AgroSolutions
   ```

4. **Configurar SQS Trigger**
   - Verifica se event source mapping já existe
   - Se não existe, cria:
     ```bash
     aws lambda create-event-source-mapping \
       --function-name AgroSolutions-EmailProcessor \
       --event-source-arn arn:aws:sqs:sa-east-1:316295889438:agrosolutions-email-queue \
       --batch-size 10 \
       --maximum-batching-window-in-seconds 5
     ```

5. **Deployment Summary**
   - Mostra informações da função deployada
   - Versão runtime, memória, timeout
   - Última modificação

**Otimização**: Se não há mudanças em `lambda/`, o job é pulado automaticamente (economia de tempo/custo).

---

## 🔒 Secrets Necessários

Configure em: `Settings > Secrets and variables > Actions`

| Secret Name | Descrição | Usado em |
|-------------|-----------|----------|
| `AWS_ACCESS_KEY_ID` | Chave de acesso AWS | EKS + Lambda |
| `AWS_SECRET_ACCESS_KEY` | Secret key AWS | EKS + Lambda |
| `KEYCLOAK_ADMIN_CLIENT_SECRET` | Client secret do Keycloak admin | EKS |
| `KEYCLOAK_API_CLIENT_SECRET` | Client secret da API | EKS |
| `KEYCLOAK_DB_PASSWORD` | Senha do banco Keycloak | EKS |

---

## 📊 Fluxo Completo

```
┌─────────────────────────────────────────────────────────────┐
│  1. Developer: git push origin main                         │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  2. GitHub Actions: Inicia Workflow                         │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  3. Job: build-and-test                                     │
│     - dotnet restore, build, test                           │
└────────────────────────┬────────────────────────────────────┘
                         │
              ┌──────────┴──────────┐
              │                     │
              ▼                     ▼
┌──────────────────────┐  ┌─────────────────────────┐
│ 4a. Job: deploy-eks  │  │ 4b. Job: deploy-lambda  │
│  - Build Docker      │  │  - Detecta mudanças     │
│  - Push ECR          │  │  - Build Lambda         │
│  - kubectl apply     │  │  - Deploy função        │
│  - Health check      │  │  - Config SQS trigger   │
└──────────────────────┘  └─────────────────────────┘
           │                         │
           └──────────┬──────────────┘
                      ▼
┌─────────────────────────────────────────────────────────────┐
│  5. Ambiente de Produção Atualizado                         │
│     - Identity API rodando no EKS                           │
│     - Lambda processando emails via SQS                     │
└─────────────────────────────────────────────────────────────┘
```

---

## 🧪 Testes Locais do Workflow

Para testar localmente sem rodar no GitHub:

### Build Local
```bash
# Test
dotnet test src/AgroSolutions.Identity.Test/

# Build Docker
docker build -t agrosolutions-identity-api:dev .

# Run local
docker run -p 8080:80 agrosolutions-identity-api:dev
```

### Deploy Manual EKS
```bash
# Configurar kubeconfig
aws eks update-kubeconfig --name agrosolutions-eks-cluster --region sa-east-1

# Deploy
kubectl apply -f k8s/production/
```

### Deploy Manual Lambda
```bash
cd lambda/EmailLambda/

dotnet lambda deploy-function AgroSolutions-EmailProcessor \
  --function-role AgroSolutions-Lambda-EmailProcessor-Role \
  --region sa-east-1
```

---

## 🐛 Troubleshooting

### Lambda Deploy Falha: "IAM Role not found"

**Erro**:
```
❌ IAM Role não encontrado: AgroSolutions-Lambda-EmailProcessor-Role
```

**Solução**:
Execute os comandos da seção 9.2 do [docs/AWS_SETUP_MANUAL.md](../docs/AWS_SETUP_MANUAL.md) para criar a IAM Role.

### EKS Deploy Falha: "Secrets not found"

**Erro**:
```
Error from server (NotFound): secrets "keycloak-client-secrets" not found
```

**Solução**:
Verifique se todos os GitHub Secrets estão configurados corretamente.

### Lambda não é deployada

**Causa**:
Não houve mudanças no diretório `lambda/` entre commits.

**Comportamento**:
✅ Esperado - otimização para economizar tempo de CI/CD.

**Forçar deploy**:
```bash
# Fazer uma mudança trivial no código da Lambda
touch lambda/EmailLambda/Function.cs
git add lambda/EmailLambda/Function.cs
git commit -m "chore: trigger lambda deploy"
git push
```

---

## 📚 Referências

- [GitHub Actions Workflow](.github/workflows/deploy.yml)
- [AWS Setup Manual](../docs/AWS_SETUP_MANUAL.md)
- [Kubernetes Deployment](production/)
- [Lambda Function Code](../lambda/EmailLambda/)

---

**Última atualização:** 2026-02-18  
**Versão:** 2.0.0 (com deploy automático de Lambda)
