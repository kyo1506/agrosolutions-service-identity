# 🔐 GitHub Actions Secrets Setup Guide

Este guia explica como configurar os secrets necessários para o CI/CD funcionar corretamente.

---

## 📋 Secrets Necessários

Acesse: **Settings > Secrets and variables > Actions > New repository secret**

### 1. AWS Credentials

#### `AWS_ACCESS_KEY_ID`
- **Descrição**: Access Key da conta AWS IAM
- **Como obter**:
  ```bash
  # Criar usuário IAM com permissões necessárias
  aws iam create-user --user-name github-actions-agrosolutions
  
  # Criar access key
  aws iam create-access-key --user-name github-actions-agrosolutions
  ```
- **Valor**: `AKIAIOSFODNN7EXAMPLE`

#### `AWS_SECRET_ACCESS_KEY`
- **Descrição**: Secret Key da conta AWS IAM
- **Como obter**: Retornado no comando acima
- **Valor**: `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY`

**Permissões IAM necessárias:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "eks:DescribeCluster",
        "eks:ListClusters"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    }
  ]
}
```

---

### 2. Keycloak Secrets

#### `KEYCLOAK_ADMIN_CLIENT_SECRET`
- **Descrição**: Client Secret do service account admin do Keycloak
- **Como obter**:
  1. Acesse Keycloak Admin Console
  2. Vá para Realm `master` > Clients > `agrosolutions-api-service-account`
  3. Aba `Credentials` > copie o `Client Secret`
- **Valor**: Exemplo: `abc123def456ghi789jkl012mno345pqr678`

#### `KEYCLOAK_API_CLIENT_SECRET`
- **Descrição**: Client Secret da API do Keycloak
- **Como obter**:
  1. Acesse Keycloak Admin Console
  2. Vá para Realm `agrosolutions` > Clients > `agrosolutions-api`
  3. Aba `Credentials` > copie o `Client Secret`
- **Valor**: Exemplo: `xyz987wvu654tsr321qpo098nml876kji543`

---

### 3. Database Secrets

#### `KEYCLOAK_DB_PASSWORD`
- **Descrição**: Senha do banco de dados PostgreSQL do Keycloak
- **Como gerar**: 
  ```bash
  # Gerar senha segura
  openssl rand -base64 32
  ```
- **Valor**: Exemplo: `eK9xL2mP7nQ5rT8uV1wY4zA6bC3dF0gH`

**⚠️ IMPORTANTE**: Use a mesma senha ao criar o banco localmente ou no RDS!

---

## 🔧 Setup Completo Passo a Passo

### Passo 1: Criar usuário IAM para GitHub Actions

```bash
# Criar usuário
aws iam create-user --user-name github-actions-agrosolutions

# Criar access key
aws iam create-access-key --user-name github-actions-agrosolutions > github-iam-keys.json

# Ver as chaves (SALVE EM LOCAL SEGURO!)
cat github-iam-keys.json
```

### Passo 2: Anexar policies ao usuário IAM

```bash
# Criar policy customizada
cat > github-actions-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:*",
        "eks:DescribeCluster",
        "eks:ListClusters",
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    }
  ]
}
EOF

# Criar policy
aws iam create-policy \
  --policy-name AgroSolutionsGitHubActionsPolicy \
  --policy-document file://github-actions-policy.json

# Anexar policy ao usuário
aws iam attach-user-policy \
  --user-name github-actions-agrosolutions \
  --policy-arn arn:aws:iam::316295889438:policy/AgroSolutionsGitHubActionsPolicy
```

### Passo 3: Configurar Keycloak

1. **Acesse Keycloak local** (se ainda não configurou):
   ```bash
   docker-compose up -d keycloak
   ```

2. **Acesse** http://localhost:8080
   - User: `admin`
   - Password: `admin`

3. **Criar Realm `agrosolutions`**:
   - Menu superior esquerdo > `Add realm`
   - Name: `agrosolutions`
   - Enabled: `ON`
   - Save

4. **Criar Service Account Client** (para admin operations):
   - Clients > Create
   - Client ID: `agrosolutions-api-service-account`
   - Client Protocol: `openid-connect`
   - Access Type: `confidential`
   - Service Accounts Enabled: `ON`
   - Save
   - Aba `Credentials` > copie `Secret` → isso é `KEYCLOAK_ADMIN_CLIENT_SECRET`

5. **Criar API Client** (para autenticação de usuários):
   - Clients > Create
   - Client ID: `agrosolutions-api`
   - Client Protocol: `openid-connect`
   - Access Type: `confidential`
   - Direct Access Grants Enabled: `ON`
   - Save
   - Aba `Credentials` > copie `Secret` → isso é `KEYCLOAK_API_CLIENT_SECRET`

### Passo 4: Gerar senha do banco

```bash
# Gerar senha segura
SECRET_DB_PASSWORD=$(openssl rand -base64 32)
echo "Database Password: $SECRET_DB_PASSWORD"

# SALVE ESSE VALOR! Você vai usar em KEYCLOAK_DB_PASSWORD
```

### Passo 5: Adicionar secrets no GitHub

1. Vá para o repositório no GitHub
2. `Settings` > `Secrets and variables` > `Actions`
3. Clique em `New repository secret`
4. Adicione cada secret:

| Name | Value |
|------|-------|
| `AWS_ACCESS_KEY_ID` | Da saída do `create-access-key` (campo `AccessKeyId`) |
| `AWS_SECRET_ACCESS_KEY` | Da saída do `create-access-key` (campo `SecretAccessKey`) |
| `KEYCLOAK_ADMIN_CLIENT_SECRET` | Do passo 3, item 4 |
| `KEYCLOAK_API_CLIENT_SECRET` | Do passo 3, item 5 |
| `KEYCLOAK_DB_PASSWORD` | Do passo 4 |

---

## ✅ Verificação

### Testar credenciais AWS localmente

```bash
export AWS_ACCESS_KEY_ID="sua-access-key"
export AWS_SECRET_ACCESS_KEY="sua-secret-key"
export AWS_REGION="sa-east-1"

# Testar
aws sts get-caller-identity
aws eks describe-cluster --name agrosolutions-eks-cluster --region sa-east-1
aws ecr describe-repositories --region sa-east-1 | grep agrosolutions-identity-api
```

### Verificar secrets do Keycloak

```bash
# Testar login com service account
curl -X POST http://localhost:8080/realms/master/protocol/openid-connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=agrosolutions-api-service-account" \
  -d "client_secret=SEU_ADMIN_CLIENT_SECRET" \
  -d "grant_type=client_credentials"

# Deve retornar um access_token
```

---

## 🔒 Segurança

### Boas Práticas

1. **Nunca commite secrets no código**
   - Use `.gitignore` para arquivos sensíveis
   - Use secrets do GitHub Actions

2. **Rotacione secrets periodicamente**
   ```bash
   # Rotacionar AWS access keys
   aws iam create-access-key --user-name github-actions-agrosolutions
   # Atualize no GitHub Secrets
   aws iam delete-access-key --user-name github-actions-agrosolutions --access-key-id OLD_KEY_ID
   ```

3. **Use IAM Roles quando possível**
   - Para EKS, use IRSA (IAM Roles for Service Accounts)
   - Reduz necessidade de credentials estáticas

4. **Monitore uso de credenciais**
   ```bash
   # Ver quando as keys foram usadas pela última vez
   aws iam get-access-key-last-used --access-key-id YOUR_KEY_ID
   ```

---

## 🐛 Troubleshooting

### Erro: "AWS credentials not configured"

**Causa**: Secrets não configurados corretamente no GitHub

**Solução**:
1. Verifique se os secrets existem: Settings > Secrets
2. Verifique se os nomes estão corretos (são case-sensitive!)
3. Re-crie os secrets se necessário

### Erro: "Access Denied" ao fazer ECR push

**Causa**: Usuário IAM não tem permissões ECR

**Solução**:
```bash
# Adicionar permissões ECR
aws iam attach-user-policy \
  --user-name github-actions-agrosolutions \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser
```

### Erro: "Invalid client credentials" do Keycloak

**Causa**: Client secret incorreto ou client não configurado

**Solução**:
1. Verifique se o client existe no Keycloak
2. Verifique se `Service Accounts Enabled` está ON
3. Re-gere o secret e atualize no GitHub

---
## 🚀 Deploy Automático da Lambda

### Requisito: IAM Role Pre-existente

O deploy automático da Lambda **requer** que a IAM Role `AgroSolutions-Lambda-EmailProcessor-Role` exista.

**⚠️ IMPORTANTE**: Esta role deve ser criada **uma única vez** antes do primeiro deploy (manual ou automático).

Execute os comandos descritos em [docs/AWS_SETUP_MANUAL.md](../docs/AWS_SETUP_MANUAL.md) seção 9.2:

```bash
# Criar IAM Role
aws iam create-role \
  --role-name AgroSolutions-Lambda-EmailProcessor-Role \
  --assume-role-policy-document file:///tmp/lambda-trust-policy.json \
  --description "Role para Lambda EmailProcessor com permissões SQS, SES e CloudWatch"

# Anexar policy
aws iam put-role-policy \
  --role-name AgroSolutions-Lambda-EmailProcessor-Role \
  --policy-name AgroSolutions-Lambda-EmailProcessor-Policy \
  --policy-document file:///tmp/lambda-permissions-policy.json
```

### Quando a Lambda é Deployada

O job `deploy-lambda` no workflow é executado quando:
1. ✅ Push na branch `main`
2. ✅ Há mudanças no diretório `lambda/`

Se não houver mudanças no código da Lambda, o job é **pulado automaticamente** para economizar tempo.

### Forçar Deploy da Lambda

Se precisar forçar o deploy sem mudanças:
```bash
# Adicionar whitespace ou comentário
echo "# $(date)" >> lambda/EmailLambda/Function.cs
git add lambda/EmailLambda/Function.cs
git commit -m "chore: trigger lambda deployment"
git push origin main
```

---
## 📚 Referências

- [GitHub Actions Secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets)
- [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [Keycloak Client Configuration](https://www.keycloak.org/docs/latest/server_admin/#clients)

---

**Última atualização**: 2026-02-18
