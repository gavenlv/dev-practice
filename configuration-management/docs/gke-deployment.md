# GKE 部署配置实践

## 概述

本文档详细说明在 Google Kubernetes Engine (GKE) 环境下的配置管理最佳实践，包括 ConfigMap、Secret、环境变量注入等。

## GKE 架构

```
┌─────────────────────────────────────────────────────────────────────┐
│                        GKE 部署架构                                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐ │
│  │                     GKE Cluster                               │ │
│  │  ┌─────────────────────────────────────────────────────────┐  │ │
│  │  │                    Namespace: myapp                     │  │ │
│  │  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │  │ │
│  │  │  │   Pod       │  │   Pod       │  │   Pod       │     │  │ │
│  │  │  │  ┌───────┐  │  │  ┌───────┐  │  │  ┌───────┐  │     │  │ │
│  │  │  │  │ App   │  │  │  │ App   │  │  │  │ App   │  │     │  │ │
│  │  │  │  │       │  │  │  │       │  │  │  │       │  │     │  │ │
│  │  │  │  │ Config│  │  │  │ Config│  │  │  │ Config│  │     │  │ │
│  │  │  │  └───────┘  │  │  └───────┘  │  │  └───────┘  │     │  │ │
│  │  │  └─────────────┘  └─────────────┘  └─────────────┘     │  │ │
│  │  │         │                │                │             │  │ │
│  │  │         └────────────────┼────────────────┘             │  │ │
│  │  │                          │                              │  │ │
│  │  │  ┌───────────────────────┴───────────────────────┐     │  │ │
│  │  │  │              ConfigMap / Secret               │     │  │ │
│  │  │  └───────────────────────────────────────────────┘     │  │ │
│  │  └─────────────────────────────────────────────────────────┘  │ │
│  │                          │                                    │ │
│  │                          ▼                                    │ │
│  │  ┌───────────────────────────────────────────────────────┐   │ │
│  │  │              Workload Identity                        │   │ │
│  │  │         (K8s SA → GCP Service Account)               │   │ │
│  │  └───────────────────────────────────────────────────────┘   │ │
│  └───────────────────────────────────────────────────────────────┘ │
│                          │                                         │
│                          ▼                                         │
│  ┌───────────────────────────────────────────────────────────────┐ │
│  │                    GCP Services                               │ │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────┐  │ │
│  │  │ CloudSQL │  │ PubSub   │  │   GCS    │  │ Secret Mgr   │  │ │
│  │  └──────────┘  └──────────┘  └──────────┘  └──────────────┘  │ │
│  └───────────────────────────────────────────────────────────────┘ │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## 目录结构

```
kubernetes/
├── base/                          # 基础配置
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── configmap.yaml
│   ├── service-account.yaml
│   └── kustomization.yaml
├── overlays/                      # 环境覆盖配置
│   ├── dev/
│   │   ├── kustomization.yaml
│   │   ├── configmap-patch.yaml
│   │   └── deployment-patch.yaml
│   ├── sit/
│   │   ├── kustomization.yaml
│   │   └── ...
│   ├── uat/
│   │   ├── kustomization.yaml
│   │   └── ...
│   └── prod/
│       ├── kustomization.yaml
│       ├── configmap-patch.yaml
│       ├── deployment-patch.yaml
│       └── managed-certificate.yaml
└── secrets/                       # Secret 模板（不提交）
    └── .gitkeep
```

## 基础配置

### Deployment

```yaml
# kubernetes/base/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  labels:
    app: myapp
spec:
  replicas: 2
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      serviceAccountName: myapp-sa
      containers:
        - name: app
          image: myapp:latest
          ports:
            - containerPort: 8080
              name: http
          env:
            - name: APP_ENV
              value: "development"
            - name: GCP_PROJECT_ID
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
          envFrom:
            - configMapRef:
                name: myapp-config
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "500m"
              memory: "512Mi"
          livenessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /ready
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 5
          volumeMounts:
            - name: config-volume
              mountPath: /etc/config
              readOnly: true
      volumes:
        - name: config-volume
          configMap:
            name: myapp-config
```

### Service

```yaml
# kubernetes/base/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: myapp
  labels:
    app: myapp
spec:
  type: ClusterIP
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
      name: http
  selector:
    app: myapp
```

### ConfigMap

```yaml
# kubernetes/base/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: myapp-config
data:
  APP_NAME: "myapp"
  LOG_LEVEL: "info"
  DATABASE_PORT: "5432"
  DATABASE_SSL_MODE: "require"
  REDIS_PORT: "6379"
  REDIS_SSL: "true"
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: myapp-config-files
data:
  config.yaml: |
    app:
      name: myapp
      port: 8080
    database:
      ssl_mode: require
      max_connections: 10
    redis:
      ssl: true
      pool_size: 10
```

### Service Account

```yaml
# kubernetes/base/service-account.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: myapp-sa
  annotations:
    iam.gke.io/gcp-service-account: myapp-sa@PROJECT_ID.iam.gserviceaccount.com
```

### Kustomization

```yaml
# kubernetes/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - service-account.yaml
  - configmap.yaml
  - deployment.yaml
  - service.yaml

commonLabels:
  app.kubernetes.io/name: myapp
  app.kubernetes.io/managed-by: kustomize
```

## 环境覆盖配置

### Dev 环境

```yaml
# kubernetes/overlays/dev/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: myapp-dev

resources:
  - ../../base

patchesStrategicMerge:
  - deployment-patch.yaml
  - configmap-patch.yaml

images:
  - name: myapp
    newTag: dev-latest

configMapGenerator:
  - name: myapp-config
    behavior: merge
    literals:
      - APP_ENV=dev
      - LOG_LEVEL=debug
---
# kubernetes/overlays/dev/deployment-patch.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: 1
  template:
    spec:
      containers:
        - name: app
          resources:
            requests:
              cpu: "50m"
              memory: "64Mi"
            limits:
              cpu: "200m"
              memory: "256Mi"
---
# kubernetes/overlays/dev/configmap-patch.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: myapp-config
data:
  LOG_LEVEL: "debug"
  DATABASE_HOST: "dev-db.myapp-dev.svc.cluster.local"
  DATABASE_NAME: "myapp_dev"
  REDIS_HOST: "dev-redis.myapp-dev.svc.cluster.local"
```

### Prod 环境

```yaml
# kubernetes/overlays/prod/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: myapp-prod

resources:
  - ../../base
  - managed-certificate.yaml
  - ingress.yaml

patchesStrategicMerge:
  - deployment-patch.yaml
  - configmap-patch.yaml

images:
  - name: myapp
    newTag: v1.0.0

configMapGenerator:
  - name: myapp-config
    behavior: merge
    literals:
      - APP_ENV=prod
      - LOG_LEVEL=warn
---
# kubernetes/overlays/prod/deployment-patch.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    spec:
      containers:
        - name: app
          resources:
            requests:
              cpu: "200m"
              memory: "256Mi"
            limits:
              cpu: "1000m"
              memory: "1Gi"
          env:
            - name: GCP_PROJECT_ID
              value: "myapp-prod"
---
# kubernetes/overlays/prod/configmap-patch.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: myapp-config
data:
  LOG_LEVEL: "warn"
  DATABASE_HOST: "prod-db.myapp-prod.svc.cluster.local"
  DATABASE_NAME: "myapp_prod"
  REDIS_HOST: "prod-redis.myapp-prod.svc.cluster.local"
---
# kubernetes/overlays/prod/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-ingress
  annotations:
    kubernetes.io/ingress.global-static-ip-name: "myapp-prod-ip"
    networking.gke.io/managed-certificates: "myapp-prod-cert"
    kubernetes.io/ingress.class: "gce"
spec:
  rules:
    - host: api.myapp.com
      http:
        paths:
          - path: /*
            pathType: ImplementationSpecific
            backend:
              service:
                name: myapp
                port:
                  number: 80
---
# kubernetes/overlays/prod/managed-certificate.yaml
apiVersion: networking.gke.io/v1
kind: ManagedCertificate
metadata:
  name: myapp-prod-cert
spec:
  domains:
    - api.myapp.com
```

## Secret 管理

### External Secrets Operator

```yaml
# kubernetes/base/external-secret.yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: gcp-secret-store
spec:
  provider:
    gcpsm:
      projectID: myapp-prod
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: myapp-secrets
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: gcp-secret-store
    kind: SecretStore
  target:
    name: myapp-secrets
    creationPolicy: Owner
  data:
    - secretKey: database-password
      remoteRef:
        key: prod/myapp/database/password
    - secretKey: redis-password
      remoteRef:
        key: prod/myapp/redis/password
    - secretKey: api-key
      remoteRef:
        key: prod/myapp/api-keys/external
```

### CSI Secret Store

```yaml
# kubernetes/base/secret-provider.yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: myapp-secrets
spec:
  provider: gcp
  parameters:
    secrets: |
      - resourceName: "projects/myapp-prod/secrets/prod-myapp-database-password/versions/latest"
        path: "database-password"
      - resourceName: "projects/myapp-prod/secrets/prod-myapp-redis-password/versions/latest"
        path: "redis-password"
---
# Deployment 中使用
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  template:
    spec:
      containers:
        - name: app
          volumeMounts:
            - name: secrets-store
              mountPath: "/mnt/secrets"
              readOnly: true
      volumes:
        - name: secrets-store
          csi:
            driver: secrets-store.csi.k8s.io
            readOnly: true
            volumeAttributes:
              secretProviderClass: "myapp-secrets"
```

## Cloud SQL 连接

### Cloud SQL Proxy

```yaml
# kubernetes/base/cloudsql-proxy.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  template:
    spec:
      containers:
        - name: app
          env:
            - name: DATABASE_HOST
              value: "127.0.0.1"
            - name: DATABASE_PORT
              value: "5432"
        - name: cloudsql-proxy
          image: gcr.io/cloudsql-docker/gce-proxy:1.33.2
          command:
            - "/cloud_sql_proxy"
            - "-instances=myapp-prod:asia-east1:myapp-db=tcp:5432"
            - "-credential_file=/secrets/service-account.json"
          securityContext:
            runAsNonRoot: true
          volumeMounts:
            - name: sa-key
              mountPath: /secrets
              readOnly: true
      volumes:
        - name: sa-key
          secret:
            secretName: cloudsql-sa-key
```

### 使用 Workload Identity

```yaml
# 使用 Workload Identity 时无需服务账号密钥
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  template:
    spec:
      serviceAccountName: myapp-sa
      containers:
        - name: cloudsql-proxy
          image: gcr.io/cloudsql-docker/gce-proxy:1.33.2
          args:
            - "--structured-logs"
            - "--port=5432"
            - "myapp-prod:asia-east1:myapp-db"
```

## 配置注入方式

### 方式一：环境变量

```yaml
env:
  - name: DATABASE_HOST
    valueFrom:
      configMapKeyRef:
        name: myapp-config
        key: DATABASE_HOST
  - name: DATABASE_PASSWORD
    valueFrom:
      secretKeyRef:
        name: myapp-secrets
        key: database-password
```

### 方式二：envFrom

```yaml
envFrom:
  - configMapRef:
      name: myapp-config
  - secretRef:
      name: myapp-secrets
```

### 方式三：Volume 挂载

```yaml
volumeMounts:
  - name: config-volume
    mountPath: /etc/config
    readOnly: true
  - name: secret-volume
    mountPath: /etc/secrets
    readOnly: true
volumes:
  - name: config-volume
    configMap:
      name: myapp-config
  - name: secret-volume
    secret:
      secretName: myapp-secrets
```

## 部署流程

### 部署命令

```bash
# 预览配置
kubectl kustomize kubernetes/overlays/dev

# 部署到 Dev 环境
kubectl apply -k kubernetes/overlays/dev

# 部署到 Prod 环境
kubectl apply -k kubernetes/overlays/prod

# 验证部署
kubectl get pods -n myapp-prod
kubectl logs -f deployment/myapp -n myapp-prod
```

### CI/CD 集成

```yaml
# .github/workflows/deploy.yaml
name: Deploy to GKE

on:
  push:
    branches:
      - main

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup gcloud
        uses: google-github-actions/setup-gcloud@v1
        with:
          project_id: ${{ secrets.GCP_PROJECT_ID }}
          service_account_key: ${{ secrets.GCP_SA_KEY }}
      
      - name: Configure kubectl
        run: |
          gcloud container clusters get-credentials myapp-cluster \
            --region asia-east1 \
            --project ${{ secrets.GCP_PROJECT_ID }}
      
      - name: Deploy to GKE
        run: |
          kubectl apply -k kubernetes/overlays/prod
      
      - name: Verify deployment
        run: |
          kubectl rollout status deployment/myapp -n myapp-prod --timeout=300s
```

## 配置验证

### 部署前检查

```bash
#!/bin/bash
# scripts/pre-deploy-check.sh

ENV=${1:-dev}
NAMESPACE="myapp-${ENV}"

echo "Pre-deployment checks for ${ENV}..."

# 检查 ConfigMap
if ! kubectl get configmap myapp-config -n $NAMESPACE &>/dev/null; then
    echo "❌ ConfigMap myapp-config not found"
    exit 1
fi

# 检查 Secret
if ! kubectl get secret myapp-secrets -n $NAMESPACE &>/dev/null; then
    echo "❌ Secret myapp-secrets not found"
    exit 1
fi

# 检查 Service Account
if ! kubectl get serviceaccount myapp-sa -n $NAMESPACE &>/dev/null; then
    echo "❌ ServiceAccount myapp-sa not found"
    exit 1
fi

# 验证配置内容
echo "Validating configuration..."
kubectl get configmap myapp-config -n $NAMESPACE -o yaml | grep -E "DATABASE_HOST|REDIS_HOST"

echo "✅ Pre-deployment checks passed!"
```

### 部署后验证

```bash
#!/bin/bash
# scripts/post-deploy-check.sh

ENV=${1:-dev}
NAMESPACE="myapp-${ENV}"

echo "Post-deployment checks for ${ENV}..."

# 检查 Pod 状态
echo "Checking pod status..."
kubectl get pods -n $NAMESPACE -l app=myapp

# 检查 Pod 是否就绪
echo "Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app=myapp -n $NAMESPACE --timeout=300s

# 检查日志是否有错误
echo "Checking for errors in logs..."
kubectl logs -l app=myapp -n $NAMESPACE --tail=100 | grep -i error || echo "No errors found"

# 测试服务连通性
echo "Testing service..."
kubectl exec -it deployment/myapp -n $NAMESPACE -- curl -s http://localhost:8080/health

echo "✅ Post-deployment checks passed!"
```

## 最佳实践

### 1. 配置分离

- ✅ 非敏感配置使用 ConfigMap
- ✅ 敏感配置使用 Secret Manager
- ✅ 环境特定配置使用 overlays
- ❌ 不在镜像中硬编码配置

### 2. 版本控制

- ✅ 所有 Kubernetes 配置纳入 Git
- ✅ 使用 Kustomize 管理环境差异
- ✅ 配置变更通过 PR 审批
- ❌ 不直接修改运行时配置

### 3. 安全配置

- ✅ 使用 Workload Identity
- ✅ 最小权限原则
- ✅ Secret 自动轮换
- ❌ 不使用默认服务账号

### 4. 资源管理

```yaml
# 资源配额
apiVersion: v1
kind: ResourceQuota
metadata:
  name: myapp-quota
  namespace: myapp-prod
spec:
  hard:
    requests.cpu: "4"
    requests.memory: "8Gi"
    limits.cpu: "8"
    limits.memory: "16Gi"
    pods: "10"
---
# Pod Disruption Budget
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: myapp-pdb
  namespace: myapp-prod
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: myapp
```
