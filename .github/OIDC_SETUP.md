# GitHub Actions OIDC Setup - AgroSolutions

Este documento descreve a configuração de **OIDC (OpenID Connect)** para autenticação do GitHub Actions com AWS, eliminando a necessidade de credenciais estáticas.

## 🔐 Benefícios da Autenticação OIDC

✅ **Mais Seguro**: Sem credenciais de longa duração armazenadas  
✅ **Rotação Automática**: Tokens temporários com curta validade  
✅ **Auditoria**: Rastreamento via CloudTrail com session names  
✅ **Least Privilege**: Permissões específicas por repositório  
✅ **Compliance**: Atende requisitos de segurança enterprise  

## 📋 Pré-requisitos

1. Conta AWS com permissões IAM administrativas
2. Repositórios GitHub no formato: `kyo1506/agrosolutions-*`
3. AWS CLI configurado

## 🚀 Configuração do OIDC Provider (AWS)

### 1. Criar OIDC Provider no IAM

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 \
  --tags Key=Name,Value=GitHubActionsOIDC Key=ManagedBy,Value=Terraform
```

**Resultado esperado:**
```json
{
  "OpenIDConnectProviderArn": "arn:aws:iam::316295889438:oidc-provider/token.actions.githubusercontent.com"
}
```

### 2. Criar IAM Role para GitHub Actions

#### Policy de Trust (Trust Relationship)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::316295889438:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:kyo1506/agrosolutions-*:*"
        },
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
```

**Criar o Role:**

```bash
aws iam create-role \
  --role-name AgroSolutionsGatewayGithubActionsRole \
  --assume-role-policy-document file://github-oidc-trust-policy.json \
  --description "GitHub Actions OIDC role for AgroSolutions microservices deployment"
```

**Ou atualizar policy existente:**

```bash
aws iam update-assume-role-policy \
  --role-name AgroSolutionsGatewayGithubActionsRole \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Federated": "arn:aws:iam::316295889438:oidc-provider/token.actions.githubusercontent.com"
        },
        "Action": "sts:AssumeRoleWithWebIdentity",
        "Condition": {
          "StringLike": {
            "token.actions.githubusercontent.com:sub": "repo:kyo1506/agrosolutions-*:*"
          },
          "StringEquals": {
            "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
          }
        }
      }
    ]
  }'
```

### 3. Anexar Permissões ao Role

#### Política Inline (Desenvolvimento/PoC)

```bash
aws iam put-role-policy \
  --role-name AgroSolutionsGatewayGithubActionsRole \
  --policy-name GitHubActionsDeploymentPolicy \
  --policy-document '{
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
          "lambda:UpdateFunctionCode",
          "lambda:UpdateFunctionConfiguration",
          "lambda:GetFunction",
          "lambda:ListEventSourceMappings",
          "lambda:CreateEventSourceMapping"
        ],
        "Resource": [
          "arn:aws:lambda:sa-east-1:316295889438:function:AgroSolutions-*"
        ]
      },
      {
        "Effect": "Allow",
        "Action": [
          "iam:GetRole",
          "iam:PassRole"
        ],
        "Resource": [
          "arn:aws:iam::316295889438:role/AgroSolutions-*"
        ]
      }
    ]
  }'
```

#### Políticas AWS Managed (Produção - Least Privilege)

```bash
# ECR Read/Write
aws iam attach-role-policy \
  --role-name AgroSolutionsGatewayGithubActionsRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser

# EKS Read-only
aws iam attach-role-policy \
  --role-name AgroSolutionsGatewayGithubActionsRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
```

## 🔧 Configuração no GitHub Workflow

### Estrutura do Workflow

```yaml
name: Deploy to AWS

on:
  push:
    branches: [main]

env:
  AWS_REGION: sa-east-1
  AWS_ROLE_TO_ASSUME: arn:aws:iam::316295889438:role/AgroSolutionsGatewayGithubActionsRole

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      id-token: write   # OBRIGATÓRIO para OIDC
      contents: read    # OBRIGATÓRIO para checkout
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Configure AWS credentials via OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ env.AWS_ROLE_TO_ASSUME }}
          role-session-name: GitHubActions-Deploy-${{ github.run_id }}
          aws-region: ${{ env.AWS_REGION }}
      
      - name: Test AWS connection
        run: aws sts get-caller-identity
```

### Permissões Necessárias no Job

**CRÍTICO**: Adicionar as permissões no nível do job:

```yaml
permissions:
  id-token: write   # Permite solicitação de token OIDC
  contents: read    # Permite checkout do código
```

## 🔍 Validação

### 1. Testar Assume Role Localmente

```bash
aws sts assume-role-with-web-identity \
  --role-arn arn:aws:iam::316295889438:role/AgroSolutionsGatewayGithubActionsRole \
  --role-session-name test-session \
  --web-identity-token "$(curl -H 'Authorization: Bearer $GITHUB_TOKEN' \
    https://api.github.com/repos/kyo1506/agrosolutions-service-identity/actions/runs/latest/token | jq -r .token)"
```

### 2. Verificar Trust Policy

```bash
aws iam get-role \
  --role-name AgroSolutionsGatewayGithubActionsRole \
  --query 'Role.AssumeRolePolicyDocument' \
  --output json
```

### 3. Listar Permissões do Role

```bash
# Políticas Inline
aws iam list-role-policies \
  --role-name AgroSolutionsGatewayGithubActionsRole

# Políticas Managed
aws iam list-attached-role-policies \
  --role-name AgroSolutionsGatewayGithubActionsRole
```

## 📊 Auditoria e Monitoramento

### CloudTrail - Rastrear Ações

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=Username,AttributeValue=AgroSolutionsGatewayGithubActionsRole \
  --max-results 50 \
  --query 'Events[*].[EventTime,EventName,Username,CloudTrailEvent]' \
  --output table
```

### Session Names Padrão

Os workflows usam session names rastreáveis:

- **EKS Deploy**: `GitHubActions-IdentityDeploy-<run_id>`
- **Lambda Deploy**: `GitHubActions-LambdaDeploy-<run_id>`

Exemplo no CloudTrail:

```json
{
  "userIdentity": {
    "type": "AssumedRole",
    "principalId": "AROA...:GitHubActions-IdentityDeploy-123456",
    "arn": "arn:aws:sts::316295889438:assumed-role/AgroSolutionsGatewayGithubActionsRole/GitHubActions-IdentityDeploy-123456"
  }
}
```

## 🛡️ Segurança - Best Practices

### 1. Condition Keys Recomendadas

```json
"Condition": {
  "StringLike": {
    "token.actions.githubusercontent.com:sub": "repo:kyo1506/agrosolutions-*:*"
  },
  "StringEquals": {
    "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
  },
  "StringLike": {
    "token.actions.githubusercontent.com:sub": [
      "repo:kyo1506/agrosolutions-*:ref:refs/heads/main",
      "repo:kyo1506/agrosolutions-*:environment:production"
    ]
  }
}
```

**Filtros disponíveis:**
- `sub`: Repositório e referência (branch/tag/environment)
- `aud`: Audiência (sempre `sts.amazonaws.com`)
- `repository`: Nome do repositório
- `repository_owner`: Proprietário do repo
- `actor`: Usuário que triggou a action
- `environment`: GitHub Environment usado

### 2. Limitar por Branch/Environment

**Apenas branch main:**

```json
{
  "StringEquals": {
    "token.actions.githubusercontent.com:sub": "repo:kyo1506/agrosolutions-service-identity:ref:refs/heads/main"
  }
}
```

**Apenas environment production:**

```json
{
  "StringEquals": {
    "token.actions.githubusercontent.com:sub": "repo:kyo1506/agrosolutions-service-identity:environment:production"
  }
}
```

### 3. Rotação de Thumbprint

**Verificar thumbprint atual:**

```bash
openssl s_client -servername token.actions.githubusercontent.com \
  -connect token.actions.githubusercontent.com:443 < /dev/null 2>/dev/null \
  | openssl x509 -fingerprint -sha1 -noout \
  | sed 's/://g' | awk -F= '{print tolower($2)}'
```

**Atualizar se necessário:**

```bash
aws iam update-open-id-connect-provider-thumbprint \
  --open-id-connect-provider-arn arn:aws:iam::316295889438:oidc-provider/token.actions.githubusercontent.com \
  --thumbprint-list <new_thumbprint>
```

## 🔄 Migração de Secrets Estáticos

### Antes (Secrets Estáticos)

```yaml
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
    aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
    aws-region: sa-east-1
```

### Depois (OIDC)

```yaml
permissions:
  id-token: write
  contents: read

- name: Configure AWS credentials via OIDC
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::316295889438:role/AgroSolutionsGatewayGithubActionsRole
    role-session-name: GitHubActions-${{ github.run_id }}
    aws-region: sa-east-1
```

### Remover Secrets do GitHub

Após validação, **deletar secrets antigos**:

```bash
# Via GitHub UI:
Settings → Secrets and variables → Actions → Delete

# Secrets a remover:
- AWS_ACCESS_KEY_ID
- AWS_SECRET_ACCESS_KEY
```

## 🧪 Troubleshooting

### Erro: "Not authorized to perform sts:AssumeRoleWithWebIdentity"

**Causa**: Trust policy incorreta ou OIDC provider não configurado

**Solução**:

```bash
# 1. Verificar se OIDC provider existe
aws iam list-open-id-connect-providers

# 2. Validar trust policy
aws iam get-role --role-name AgroSolutionsGatewayGithubActionsRole \
  --query 'Role.AssumeRolePolicyDocument'

# 3. Verificar repositório na condição StringLike
```

### Erro: "AccessDenied" após assumir role

**Causa**: Permissões insuficientes no IAM Role

**Solução**:

```bash
# Ver políticas anexadas
aws iam list-attached-role-policies --role-name AgroSolutionsGatewayGithubActionsRole
aws iam list-role-policies --role-name AgroSolutionsGatewayGithubActionsRole

# Adicionar permissões necessárias (ver seção 3)
```

### Workflow não encontra permissões

**Causa**: Falta `permissions` no job

**Solução**: Adicionar no YAML:

```yaml
jobs:
  deploy:
    permissions:
      id-token: write
      contents: read
```

## 📚 Referências

- [GitHub Docs: OIDC with AWS](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [AWS Docs: IAM OIDC Identity Providers](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
- [aws-actions/configure-aws-credentials](https://github.com/aws-actions/configure-aws-credentials)
- [CloudTrail Event Reference](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-event-reference.html)

## ✅ Checklist de Setup

- [ ] OIDC Provider criado no IAM
- [ ] IAM Role `AgroSolutionsGatewayGithubActionsRole` criado
- [ ] Trust policy configurada com wildcard `agrosolutions-*`
- [ ] Permissões ECR/EKS/Lambda anexadas ao role
- [ ] Workflows atualizados com `permissions` e `role-to-assume`
- [ ] Testado deploy via GitHub Actions
- [ ] Secrets estáticos removidos do GitHub
- [ ] CloudTrail validando session names
- [ ] Documentação atualizada
