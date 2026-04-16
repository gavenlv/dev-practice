# 06 — GCP/GKE 证书实践

> **难度**：⭐⭐⭐⭐ 专家 | **阅读时间**：25 分钟 | **实践时间**：45 分钟

## 你将学到什么

- Google Certificate Authority Service (CAS) 企业级 PKI
- GKE Ingress TLS 配置
- GKE Workload mTLS
- Cloud SQL TLS 连接
- 端到端 TLS 实战

---

## 1. Google Certificate Authority Service (CAS)

### 1.1 CAS 概述

CAS 是 GCP 托管的私有 CA 服务，适合企业级 PKI。

```
┌─────────────────────────────────────────────────────────────┐
│                    Google CAS 架构                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Certificate Authority Service           │   │
│  │                                                     │   │
│  │  ┌──────────────┐  ┌──────────────┐                │   │
│  │  │  Root CA     │  │  Subordinate │                │   │
│  │  │  (Tier 1)    │→ │  CA (Tier 2) │                │   │
│  │  └──────────────┘  └──────────────┘                │   │
│  │                           │                         │   │
│  │                           ▼                         │   │
│  │                    签发终端证书                      │   │
│  │                                                     │   │
│  │  特性：                                             │   │
│  │  - 私钥由 Google HSM 保护                           │   │
│  │  - 自动证书轮换                                     │   │
│  │  - 审计日志集成 Cloud Audit Logs                    │   │
│  │  - 证书吊销支持                                     │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 创建 CA

```bash
# 创建根 CA
gcloud privateca roots create myapp-root-ca \
  --location=asia-east1 \
  --project=myapp-prod \
  --subject="CN=MyApp Root CA,O=MyApp,C=CN" \
  --key-algorithm=ec-p256-sha256 \
  --validity=10y \
  --tier=enterprise

# 创建中间 CA
gcloud privateca subordinates create myapp-intermediate-ca \
  --location=asia-east1 \
  --project=myapp-prod \
  --issuer=myapp-root-ca \
  --issuer-location=asia-east1 \
  --subject="CN=MyApp Intermediate CA,O=MyApp,C=CN" \
  --key-algorithm=ec-p256-sha256 \
  --validity=5y \
  --tier=enterprise

# 激活中间 CA
gcloud privateca subordinates activate myapp-intermediate-ca \
  --location=asia-east1 \
  --issuer=myapp-root-ca \
  --issuer-location=asia-east1
```

### 1.3 签发证书

```bash
# 生成 CSR
openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:P-256 \
  -keyout server.key -out server.csr \
  -subj "/CN=api.myapp.com/O=MyApp/C=CN"

# 用 CAS 签发证书
gcloud privateca certificates create myapp-server-cert \
  --issuer-pool=myapp-intermediate-ca \
  --issuer-location=asia-east1 \
  --csr-file=server.csr \
  --cert-output-file=server.crt \
  --validity=P365D \
  --subject-alt-names="dns:api.myapp.com,dns:*.myapp.com"

# 查看证书
gcloud privateca certificates describe myapp-server-cert \
  --issuer-pool=myapp-intermediate-ca \
  --issuer-location=asia-east1
```

### 1.4 Terraform 管理 CA

```hcl
# terraform/cas.tf

resource "google_privateca_ca_pool" "myapp_pool" {
  name     = "myapp-ca-pool"
  location = var.region
  project  = var.project_id
  tier     = "ENTERPRISE"
  
  publishing_options {
    publish_ca_cert = true
  }
  
  issuance_policy {
    allowed_key_types {
      elliptic_curve {
        signature_algorithm = "ECDSA_P256"
      }
    }
    maximum_lifetime = "2592000s"  # 30 days
  }
}

resource "google_privateca_certificate_authority" "root" {
  pool                     = google_privateca_ca_pool.myapp_pool.name
  certificate_authority_id = "myapp-root-ca"
  location                 = var.region
  project                  = var.project_id
  lifetime                 = "315360000s"  # 10 years
  
  config {
    subject_config {
      subject {
        common_name = "MyApp Root CA"
        organization = "MyApp"
        country_code = "CN"
      }
    }
    x509_config {
      ca_options {
        is_ca = true
      }
      key_usage {
        base_key_usage {
          cert_sign = true
          crl_sign  = true
        }
      }
    }
  }
  
  key_spec {
    algorithm = "EC_P256_SHA256"
  }
  
  type = "SELF_SIGNED"
}

resource "google_privateca_certificate_authority" "intermediate" {
  pool                     = google_privateca_ca_pool.myapp_pool.name
  certificate_authority_id = "myapp-intermediate-ca"
  location                 = var.region
  project                  = var.project_id
  lifetime                 = "157680000s"  # 5 years
  
  config {
    subject_config {
      subject {
        common_name = "MyApp Intermediate CA"
        organization = "MyApp"
        country_code = "CN"
      }
    }
    x509_config {
      ca_options {
        is_ca = true
      }
      key_usage {
        base_key_usage {
          cert_sign = true
          crl_sign  = true
        }
      }
    }
  }
  
  key_spec {
    algorithm = "EC_P256_SHA256"
  }
  
  type             = "SUBORDINATE"
  subordinate_config {
    parent = google_privateca_certificate_authority.root.name
  }
}
```

---

## 2. GKE Ingress TLS

### 2.1 Google Managed Certificate

```yaml
# 自动管理证书（推荐公网服务使用）
apiVersion: networking.gke.io/v1
kind: ManagedCertificate
metadata:
  name: myapp-cert
  namespace: myapp
spec:
  domains:
    - api.myapp.com
    - www.myapp.com
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-ingress
  namespace: myapp
  annotations:
    networking.gke.io/managed-certificates: "myapp-cert"
    kubernetes.io/ingress.global-static-ip-name: "myapp-prod-ip"
    kubernetes.io/ingress.class: "gce"
spec:
  rules:
    - host: api.myapp.com
      http:
        paths:
          - path: /
            pathType: ImplementationSpecific
            backend:
              service:
                name: myapp
                port:
                  number: 80
```

### 2.2 自带证书（自定义 CA / CAS 签发）

```yaml
# 从 CAS 签发的证书存入 Secret
apiVersion: v1
kind: Secret
metadata:
  name: myapp-tls-secret
  namespace: myapp
type: kubernetes.io/tls
data:
  tls.crt: <base64-encoded-cert-chain>
  tls.key: <base64-encoded-private-key>
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-ingress-custom-cert
  namespace: myapp
  annotations:
    kubernetes.io/ingress.class: "gce"
spec:
  tls:
    - hosts:
        - api.myapp.com
      secretName: myapp-tls-secret
  rules:
    - host: api.myapp.com
      http:
        paths:
          - path: /
            pathType: ImplementationSpecific
            backend:
              service:
                name: myapp
                port:
                  number: 80
```

### 2.3 cert-manager + Google CAS

```yaml
# cert-manager 使用 Google CAS 作为 Issuer
apiVersion: cas-issuer.chickenhip.com/v1beta1
kind: GoogleCASIssuer
metadata:
  name: myapp-cas-issuer
  namespace: cert-manager
spec:
  projectID: myapp-prod
  location: asia-east1
  caPoolID: myapp-ca-pool
  serviceAccountSecretRef:
    name: cas-issuer-sa
    key: key.json
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: myapp-cert
  namespace: myapp
spec:
  secretName: myapp-tls
  issuerRef:
    name: myapp-cas-issuer
    kind: GoogleCASIssuer
    group: cas-issuer.chickenhip.com
  dnsNames:
    - api.myapp.com
  duration: 720h
  renewBefore: 168h
  privateKey:
    algorithm: ECDSA
    size: 256
```

---

## 3. GKE 内部 mTLS

### 3.1 服务间 mTLS 架构

```
┌─────────────────────────────────────────────────────────────────┐
│                 GKE 内部 mTLS 架构                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │                    GKE Cluster                             │ │
│  │                                                           │ │
│  │  ┌─────────────┐  mTLS  ┌─────────────┐  mTLS ┌────────┐│ │
│  │  │  Service A  │←══════→│  Service B  │←═════→│ServiceC││ │
│  │  │             │        │             │       │        ││ │
│  │  │ ┌─────────┐ │        │ ┌─────────┐ │       │┌──────┐││ │
│  │  │ │Sidecar │ │        │ │Sidecar │ │       ││Sidecar│││ │
│  │  │ │(Envoy) │ │        │ │(Envoy) │ │       ││(Envoy)│││ │
│  │  │ └─────────┘ │        │ └─────────┘ │       │└──────┘││ │
│  │  └─────────────┘        └─────────────┘       └────────┘│ │
│  │         ↑                     ↑                    ↑     │ │
│  │         └─────────────────────┼────────────────────┘     │ │
│  │                               │                          │ │
│  │                    Istio Citadel CA                       │ │
│  │                    (自动签发和轮换证书)                     │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Istio mTLS 配置

```yaml
# 全局 STRICT mTLS
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: istio-system
spec:
  mtls:
    mode: STRICT
---
# 服务级别 mTLS 策略
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: myapp
  namespace: myapp
spec:
  selector:
    matchLabels:
      app: myapp
  mtls:
    mode: STRICT
  portLevelMtls:
    8080:
      mode: STRICT
---
# Destination Rule
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: myapp-dr
  namespace: myapp
spec:
  host: myapp.myapp.svc.cluster.local
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        h2UpgradePolicy: UPGRADE
```

### 3.3 Authorization Policy

```yaml
# 只允许特定服务访问
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: myapp-policy
  namespace: myapp
spec:
  selector:
    matchLabels:
      app: myapp
  rules:
    - from:
        - source:
            principals:
              - "cluster.local/ns/myapp/sa/service-a"
              - "cluster.local/ns/myapp/sa/service-b"
      to:
        - operation:
            methods: ["GET", "POST"]
            paths: ["/api/*"]
```

---

## 4. Cloud SQL TLS 连接

### 4.1 Cloud SQL 自动 TLS

```
Cloud SQL 默认使用 TLS：
- 所有连接自动加密
- 服务器证书由 Google 管理
- 自动轮换服务器证书

客户端验证方式：
1. Cloud SQL Proxy（推荐）→ 自动处理 TLS
2. Cloud SQL Auth Proxy → 新版代理
3. 直接连接 → 需要配置客户端证书
```

### 4.2 Cloud SQL Proxy

```yaml
# GKE 中使用 Cloud SQL Proxy
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: myapp
spec:
  template:
    spec:
      serviceAccountName: myapp-sa
      containers:
        - name: app
          image: myapp:latest
          env:
            - name: DATABASE_HOST
              value: "127.0.0.1"
            - name: DATABASE_PORT
              value: "5432"
        - name: cloudsql-proxy
          image: gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.8.1
          args:
            - "--structured-logs"
            - "--port=5432"
            - "myapp-prod:asia-east1:myapp-db"
          securityContext:
            runAsNonRoot: true
          resources:
            requests:
              cpu: "50m"
              memory: "64Mi"
            limits:
              cpu: "200m"
              memory: "256Mi"
```

### 4.3 客户端证书验证（mTLS to Cloud SQL）

```bash
# 下载客户端证书
gcloud sql ssl client-certs create myapp-client \
  --instance=myapp-db \
  --project=myapp-prod

# 下载服务器 CA 证书
gcloud sql instances describe myapp-db \
  --project=myapp-prod \
  --format="value(serverCaCert.cert)" > server-ca.pem

# 连接
psql "host=myapp-db-user.asia-east1.cloudsql.googleapis.com \
      sslmode=verify-ca \
      sslrootcert=server-ca.pem \
      sslcert=client-cert.pem \
      sslkey=client-key.pem \
      dbname=myapp \
      user=myapp_user"
```

---

## 5. 端到端 TLS 实战

### 5.1 完整架构

```
┌─────────────────────────────────────────────────────────────────┐
│                    端到端 TLS 架构                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  用户                                           Cloud SQL      │
│  ┌───┐                                         ┌──────────┐   │
│  │   │  ① TLS 1.3        ③ mTLS               │          │   │
│  │   │────────→ GCLB ──────→ GKE Pod ──────────→│ CloudSQL │   │
│  │   │         (Google    (Istio    (Proxy      │          │   │
│  └───┘          Managed     mTLS)    TLS)       └──────────┘   │
│                 Cert)                                          │
│                                                                 │
│  ① 用户 → GCLB：TLS 1.3，Google Managed Certificate           │
│  ② GCLB → GKE：TLS 或 mTLS                                    │
│  ③ GKE Pod → Pod：Istio mTLS                                   │
│  ④ GKE Pod → Cloud SQL：Cloud SQL Proxy TLS                    │
│  ⑤ GKE Pod → PubSub：Google API TLS                            │
│  ⑥ GKE Pod → Redis：Memorystore TLS                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 5.2 完整配置

```yaml
# 1. Google Managed Certificate（用户 → GCLB）
apiVersion: networking.gke.io/v1
kind: ManagedCertificate
metadata:
  name: myapp-cert
  namespace: myapp
spec:
  domains:
    - api.myapp.com
---
# 2. Ingress
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-ingress
  namespace: myapp
  annotations:
    networking.gke.io/managed-certificates: "myapp-cert"
    kubernetes.io/ingress.global-static-ip-name: "myapp-prod-ip"
spec:
  rules:
    - host: api.myapp.com
      http:
        paths:
          - path: /
            pathType: ImplementationSpecific
            backend:
              service:
                name: myapp
                port:
                  number: 80
---
# 3. Istio mTLS（Pod → Pod）
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: myapp
spec:
  mtls:
    mode: STRICT
---
# 4. Deployment（含 Cloud SQL Proxy）
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: myapp
spec:
  template:
    spec:
      serviceAccountName: myapp-sa
      containers:
        - name: app
          image: myapp:latest
          env:
            - name: DATABASE_HOST
              value: "127.0.0.1"
            - name: DATABASE_SSL_MODE
              value: "require"
        - name: cloudsql-proxy
          image: gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.8.1
          args:
            - "--structured-logs"
            - "--port=5432"
            - "myapp-prod:asia-east1:myapp-db"
```

---

## 6. 证书自动化流水线

### 6.1 CI/CD 集成

```yaml
# .github/workflows/certificate-rotation.yaml
name: Certificate Rotation

on:
  schedule:
    - cron: '0 0 * * 0'  # 每周日检查
  workflow_dispatch:

jobs:
  check-and-rotate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup gcloud
        uses: google-github-actions/setup-gcloud@v1
        with:
          project_id: ${{ secrets.GCP_PROJECT_ID }}
          service_account_key: ${{ secrets.GCP_SA_KEY }}
      
      - name: Check certificate expiry
        run: |
          DOMAINS=("api.myapp.com" "app.myapp.com")
          for domain in "${DOMAINS[@]}"; do
            days_left=$(echo | openssl s_client -connect "$domain:443" -servername "$domain" 2>/dev/null | \
              openssl x509 -noout -checkend 2592000 && echo "30+" || echo "<30")
            echo "$domain: $days_left days"
          done
      
      - name: Rotate internal certificates
        if: needs-rotation
        run: |
          kubectl apply -k kubernetes/overlays/prod
          kubectl rollout restart deployment/myapp -n myapp-prod
      
      - name: Verify deployment
        run: |
          kubectl rollout status deployment/myapp -n myapp-prod --timeout=300s
```

### 6.2 证书监控仪表盘

```
关键指标：
1. 证书过期倒计时（按域名分组）
2. 证书签发/续期事件
3. TLS 握手错误率
4. mTLS 连接成功率
5. 证书吊销事件

工具：
- Grafana + Prometheus
- Google Cloud Monitoring
- SSL Labs 监控
```

---

## 7. 故障排查手册

### 7.1 常见问题

| 问题 | 症状 | 排查方法 |
|------|------|----------|
| 证书过期 | 浏览器警告 | `openssl s_client -connect host:443 \| openssl x509 -noout -dates` |
| 证书链不完整 | 移动端无法访问 | `openssl s_client -connect host:443 -showcerts` |
| 域名不匹配 | NET::ERR_CERT_COMMON_NAME_INVALID | 检查 SAN |
| mTLS 失败 | 连接被拒 | 检查客户端证书和 CA 信任 |
| Cloud SQL 连接失败 | TLS 握手错误 | 检查 Proxy 配置和 SA 权限 |

### 7.2 调试命令

```bash
# 检查 GKE Ingress 证书状态
kubectl describe managedcertificate myapp-cert -n myapp

# 检查 cert-manager 证书状态
kubectl describe certificate myapp-cert -n myapp
kubectl logs -n cert-manager -l app=cert-manager

# 检查 Istio mTLS 状态
istioctl analyze
istioctl proxy-config secret deployment/myapp -n myapp

# 检查 Cloud SQL 连接
gcloud sql instances describe myapp-db --project=myapp-prod | grep ssl

# 检查 Workload Identity
gcloud iam service-accounts get-iam-policy myapp-sa@myapp-prod.iam.gserviceaccount.com
```

---

## 8. 知识总结

### GCP/GKE TLS 决策树

```
需要 TLS 证书？
│
├─ 公网服务？
│  ├─ 是 → Google Managed Certificate（自动管理）
│  └─ 否 → 内部服务
│     ├─ 服务间通信？
│     │  ├─ 是 → Istio mTLS（自动管理）
│     │  └─ 否 → 数据库/中间件连接
│     │     ├─ Cloud SQL → Cloud SQL Proxy（自动 TLS）
│     │     ├─ Memorystore → 启用 TLS（in-transit encryption）
│     │     └─ PubSub → Google API 自动 TLS
│     └─ 需要自定义 CA？
│        ├─ 是 → Google CAS
│        └─ 否 → cert-manager + Let's Encrypt
```

### 自检清单

- [ ] 我能配置 Google Managed Certificate
- [ ] 我理解 Google CAS 的使用场景
- [ ] 我能配置 Istio mTLS
- [ ] 我能配置 Cloud SQL TLS 连接
- [ ] 我理解端到端 TLS 的完整架构
- [ ] 我知道如何排查 TLS 问题

---

**上一篇**：[证书管理 ←](05-certificate-management.md) | **返回目录**：[README](../README.md)
