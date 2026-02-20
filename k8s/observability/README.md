# Stack de Observabilidade - AgroSolutions

Este diretório contém a **stack de observabilidade compartilhada** por todos os microserviços da plataforma AgroSolutions.

## 📊 Namespace: `agrosolutions-observability`

A stack de observabilidade é **centralizada e compartilhada** entre todos os serviços:
- `agrosolutions-identity`
- `agrosolutions-gestao`
- `agrosolutions-ingestao`
- `agrosolutions-telemetria`
- `agrosolutions-alertas`

## 🛠️ Componentes

### Ativos (Free Tier)

| Componente | Propósito | Status | Endpoint |
|------------|-----------|--------|----------|
| **OpenTelemetry Collector** | Coleta de traces, métricas e logs | ✅ Running | `otel-collector-service.agrosolutions-observability:4317` (gRPC) |
| **Prometheus** | Armazenamento de métricas | ✅ Running | `prometheus-service.agrosolutions-observability:9090` |

### Desabilitados (Recursos Limitados)

| Componente | Propósito | Status |
|------------|-----------|--------|
| **Loki** | Agregação de logs | ⏸️ Scaled to 0 |
| **Tempo** | Armazenamento de traces | ⏸️ Scaled to 0 |
| **Grafana** | Visualização de dados | ⏸️ Scaled to 0 |

## 🔧 Configuração nos Serviços

Para integrar um serviço com a stack de observabilidade, configure no **ConfigMap**:

```yaml
# OpenTelemetry Configuration
OTEL_EXPORTER_OTLP_ENDPOINT: "http://otel-collector-service.agrosolutions-observability:4317"
OTEL_EXPORTER_OTLP_PROTOCOL: "grpc"
OTEL_SERVICE_NAME: "seu-servico"
OTEL_RESOURCE_ATTRIBUTES: "deployment.environment=production,service.version=1.0.0"
OTEL_TRACES_EXPORTER: "otlp"
OTEL_METRICS_EXPORTER: "otlp"
OTEL_LOGS_EXPORTER: "otlp"
```

**Nota**: Use o **FQDN completo** `<service>.<namespace>:<port>` para comunicação cross-namespace.

## 📁 Arquivos

- `namespace.yaml` - Namespace dedicado de observabilidade
- `observability.yaml` - Deployments, Services, ConfigMaps da stack completa
- `prometheus-rbac.yaml` - RBAC para Prometheus scraping cross-namespace
- `resource-configs.yaml` - Quotas e limites de recursos
- `ingress-grafana.yaml` - Ingress para acesso externo ao Grafana (quando habilitado)

## 🚀 Deploy

```bash
# Criar namespace
kubectl apply -f k8s/observability/namespace.yaml

# Aplicar RBAC (ClusterRole)
kubectl apply -f k8s/observability/prometheus-rbac.yaml

# Deploy da stack
kubectl apply -f k8s/observability/resource-configs.yaml
kubectl apply -f k8s/observability/observability.yaml

# Desabilitar componentes pesados (Free Tier)
kubectl scale deployment -n agrosolutions-observability grafana loki tempo --replicas=0
```

## 📈 Verificar Status

```bash
# Pods
kubectl get pods -n agrosolutions-observability

# Services
kubectl get svc -n agrosolutions-observability

# Recursos alocados
kubectl describe ns agrosolutions-observability
```

## 🔍 Acessar Prometheus

```bash
# Port-forward para acesso local
kubectl port-forward -n agrosolutions-observability svc/prometheus-service 9090:9090

# Abrir no navegador
http://localhost:9090
```

## 🎯 Métricas Disponíveis

- **Aplicação**: Métricas customizadas via OpenTelemetry SDK
- **Runtime**: .NET metrics (GC, threads, exceptions)
- **HTTP**: Request duration, status codes, latency
- **Database**: Connection pools, query duration
- **Kubernetes**: Pod/container metrics via Prometheus

## 🌐 Service Discovery

Prometheus usa **service discovery do Kubernetes** para encontrar targets automaticamente via annotations:

```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "9090"
  prometheus.io/path: "/metrics"
```

## 🔐 RBAC

O ClusterRole `prometheus` permite ao ServiceAccount:
- Ler nodes, services, endpoints, pods
- Scrape métricas de todos os namespaces
- Acesso a ingresses para discovery

## 💾 Persistência

PVCs para armazenamento (quando habilitados):
- `prometheus-pvc` - 10Gi (gp3, encrypted)
- `loki-pvc` - 20Gi (gp3, encrypted)
- `tempo-pvc` - 20Gi (gp3, encrypted)
- `grafana-pvc` - 5Gi (gp3, encrypted)

## ⚡ Recursos

**Quotas do Namespace:**
- CPU requests: 2 cores
- Memory requests: 4Gi
- CPU limits: 4 cores
- Memory limits: 8Gi

**OTel Collector:**
- Requests: 256Mi / 100m CPU
- Limits: 512Mi / 500m CPU

**Prometheus:**
- Requests: 512Mi / 200m CPU
- Limits: 2Gi / 1000m CPU

## 🔄 Escalabilidade

Para habilitar Loki/Tempo/Grafana quando houver mais recursos:

```bash
kubectl scale deployment -n agrosolutions-observability grafana --replicas=1
kubectl scale deployment -n agrosolutions-observability loki --replicas=1
kubectl scale deployment -n agrosolutions-observability tempo --replicas=1

# Aplicar ingress
kubectl apply -f k8s/observability/ingress-grafana.yaml
```

## 📚 Referências

- [OpenTelemetry Collector](https://opentelemetry.io/docs/collector/)
- [Prometheus](https://prometheus.io/docs/)
- [Grafana](https://grafana.com/docs/)
- [Loki](https://grafana.com/docs/loki/)
- [Tempo](https://grafana.com/docs/tempo/)
