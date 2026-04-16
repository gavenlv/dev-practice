# GCP Secret Manager 实践指南

## 概述

Secret Manager 是 GCP 提供的安全密钥存储服务，用于存储和管理敏感信息如：
- 数据库密码
- API 密钥
- TLS 证书
- OAuth 令牌
- 加密密钥

## 架构设计

```
┌─────────────────────────────────────────────────────────────────┐
│                    Secret Manager 架构                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    GCP Project (per env)                │   │
│  │  ┌─────────────────────────────────────────────────┐   │   │
│  │  │              Secret Manager                      │   │   │
│  │  │  ┌─────────────┐  ┌─────────────┐               │   │   │
│  │  │  │ db-password │  │  api-key    │               │   │   │
│  │  │  │  v1, v2...  │  │  v1, v2...  │               │   │   │
│  │  │  └─────────────┘  └─────────────┘               │   │   │
│  │  │  ┌─────────────┐  ┌─────────────┐               │   │   │
│  │  │  │ tls-cert    │  │ redis-pass  │               │   │   │
│  │  │  │  v1, v2...  │  │  v1, v2...  │               │   │   │
│  │  │  └─────────────┘  └─────────────┘               │   │   │
│  │  └─────────────────────────────────────────────────┘   │   │
│  │                          │                              │   │
│  │                          ▼                              │   │
│  │  ┌─────────────────────────────────────────────────┐   │   │
│  │  │              GKE Workload Identity              │   │   │
│  │  │         (Pod → Service Account → Secrets)       │   │   │
│  │  └─────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Secret 命名规范

### 命名格式

```
{environment}/{service}/{resource-type}/{resource-name}

示例:
- prod/myapp/database/password
- prod/myapp/api-keys/stripe
- prod/myapp/tls/myapp-tls-cert
- dev/myapp/database/password
```

### 命名规则

| 规则 | 说明 |
|------|------|
| 使用小写字母 | Secret ID 只能包含小写字母、数字、连字符和下划线 |
| 环境前缀 | 以环境名称开头，便于权限管理 |
| 服务分组 | 按服务分组，便于批量管理 |
| 类型分类 | 按资源类型分类（database, api-keys, tls 等） |

## Secret 管理

### 创建 Secret

#### 使用 gcloud CLI

```bash
# 创建 Secret
gcloud secrets create prod/myapp/database/password \
    --replication-policy="automatic" \
    --project=myapp-prod

# 添加 Secret 版本
echo -n "my-secure-password" | gcloud secrets versions add prod/myapp/database/password \
    --data-file=- \
    --project=myapp-prod

# 从文件创建
gcloud secrets versions add prod/myapp/tls/myapp-tls-cert \
    --data-file=./certs/tls.crt \
    --project=myapp-prod
```

#### 使用 Terraform

```hcl
# terraform/modules/secrets/main.tf

resource "google_secret_manager_secret" "db_password" {
  secret_id = "${var.environment}/myapp/database/password"
  project   = var.project_id

  replication {
    automatic = true
  }
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = var.db_password
}

resource "google_secret_manager_secret_iam_member" "db_password_accessor" {
  secret_id  = google_secret_manager_secret.db_password.id
  role       = "roles/secretmanager.secretAccessor"
  member     = "serviceAccount:${var.service_account_email}"
}
```

### 读取 Secret

#### 使用 gcloud CLI

```bash
# 读取最新版本
gcloud secrets versions access latest \
    --secret=prod/myapp/database/password \
    --project=myapp-prod

# 读取特定版本
gcloud secrets versions access 1 \
    --secret=prod/myapp/database/password \
    --project=myapp-prod
```

#### 使用 Go SDK

```go
package secrets

import (
    "context"
    "fmt"

    secretmanager "cloud.google.com/go/secretmanager/apiv1"
    "cloud.google.com/go/secretmanager/apiv1/secretmanagerpb"
)

type SecretManager struct {
    client    *secretmanager.Client
    projectID string
}

func NewSecretManager(ctx context.Context, projectID string) (*SecretManager, error) {
    client, err := secretmanager.NewClient(ctx)
    if err != nil {
        return nil, fmt.Errorf("failed to create secret manager client: %w", err)
    }
    
    return &SecretManager{
        client:    client,
        projectID: projectID,
    }, nil
}

func (sm *SecretManager) GetSecret(ctx context.Context, name string) (string, error) {
    req := &secretmanagerpb.AccessSecretVersionRequest{
        Name: fmt.Sprintf("projects/%s/secrets/%s/versions/latest", sm.projectID, name),
    }
    
    result, err := sm.client.AccessSecretVersion(ctx, req)
    if err != nil {
        return "", fmt.Errorf("failed to access secret: %w", err)
    }
    
    return string(result.Payload.Data), nil
}

func (sm *SecretManager) GetSecretVersion(ctx context.Context, name string, version string) (string, error) {
    req := &secretmanagerpb.AccessSecretVersionRequest{
        Name: fmt.Sprintf("projects/%s/secrets/%s/versions/%s", sm.projectID, name, version),
    }
    
    result, err := sm.client.AccessSecretVersion(ctx, req)
    if err != nil {
        return "", fmt.Errorf("failed to access secret version: %w", err)
    }
    
    return string(result.Payload.Data), nil
}

func (sm *SecretManager) Close() error {
    return sm.client.Close()
}
```

#### 使用 Python SDK

```python
from google.cloud import secretmanager
from typing import Optional


class SecretManagerClient:
    def __init__(self, project_id: str):
        self.client = secretmanager.SecretManagerServiceClient()
        self.project_id = project_id
    
    def get_secret(self, secret_id: str, version: str = "latest") -> str:
        name = f"projects/{self.project_id}/secrets/{secret_id}/versions/{version}"
        
        response = self.client.access_secret_version(request={"name": name})
        
        return response.payload.data.decode("UTF-8")
    
    def get_secret_bytes(self, secret_id: str, version: str = "latest") -> bytes:
        name = f"projects/{self.project_id}/secrets/{secret_id}/versions/{version}"
        
        response = self.client.access_secret_version(request={"name": name})
        
        return response.payload.data


def load_database_config(project_id: str) -> dict:
    sm = SecretManagerClient(project_id)
    
    return {
        "host": sm.get_secret("prod/myapp/database/host"),
        "port": sm.get_secret("prod/myapp/database/port"),
        "user": sm.get_secret("prod/myapp/database/user"),
        "password": sm.get_secret("prod/myapp/database/password"),
        "database": sm.get_secret("prod/myapp/database/name"),
    }
```

#### 使用 Node.js SDK

```javascript
const { SecretManagerServiceClient } = require('@google-cloud/secret-manager');

class SecretManager {
    constructor(projectId) {
        this.client = new SecretManagerServiceClient();
        this.projectId = projectId;
    }
    
    async getSecret(secretId, version = 'latest') {
        const name = `projects/${this.projectId}/secrets/${secretId}/versions/${version}`;
        
        const [versionResponse] = await this.client.accessSecretVersion({ name });
        
        return versionResponse.payload.data.toString('utf8');
    }
    
    async getSecretBytes(secretId, version = 'latest') {
        const name = `projects/${this.projectId}/secrets/${secretId}/versions/${version}`;
        
        const [versionResponse] = await this.client.accessSecretVersion({ name });
        
        return versionResponse.payload.data;
    }
}

async function loadConfig(projectId) {
    const sm = new SecretManager(projectId);
    
    const [dbPassword, redisPassword, apiKey] = await Promise.all([
        sm.getSecret('prod/myapp/database/password'),
        sm.getSecret('prod/myapp/redis/password'),
        sm.getSecret('prod/myapp/api-keys/external'),
    ]);
    
    return {
        database: { password: dbPassword },
        redis: { password: redisPassword },
        api: { key: apiKey },
    };
}

module.exports = { SecretManager, loadConfig };
```

## GKE 集成

### Workload Identity 配置

```hcl
# terraform/modules/gke-workload-identity/main.tf

resource "google_service_account" "workload_sa" {
  account_id   = var.service_account_name
  project      = var.project_id
  display_name = "GKE Workload Identity SA"
}

resource "google_service_account_iam_member" "workload_identity" {
  service_account_id = google_service_account.workload_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.k8s_namespace}/${var.k8s_service_account}]"
}

resource "google_project_iam_member" "secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.workload_sa.email}"
}
```

### Kubernetes 配置

```yaml
# kubernetes/base/service-account.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: myapp-sa
  annotations:
    iam.gke.io/gcp-service-account: myapp-sa@myapp-prod.iam.gserviceaccount.com
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  template:
    spec:
      serviceAccountName: myapp-sa
      containers:
        - name: app
          image: myapp:latest
          env:
            - name: GCP_PROJECT_ID
              value: "myapp-prod"
```

### Secret 挂载方式

#### 方式一：环境变量注入（推荐）

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  template:
    spec:
      serviceAccountName: myapp-sa
      containers:
        - name: app
          image: myapp:latest
          env:
            - name: DATABASE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: gcp-secret-db-password
                  key: password
```

#### 方式二：Volume 挂载

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  template:
    spec:
      serviceAccountName: myapp-sa
      containers:
        - name: app
          image: myapp:latest
          volumeMounts:
            - name: secrets
              mountPath: /etc/secrets
              readOnly: true
      volumes:
        - name: secrets
          csi:
            driver: secrets-store.csi.k8s.io
            readOnly: true
            volumeAttributes:
              secretProviderClass: "myapp-secrets"
```

## Secret 版本管理

### 版本策略

```
┌────────────────────────────────────────────────────────────────┐
│                    Secret 版本生命周期                         │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  v1 ──> v2 ──> v3 ──> v4 (latest)                             │
│   │      │      │      │                                      │
│   │      │      │      └── 当前使用版本                        │
│   │      │      └── 保留用于回滚                               │
│   │      └── 保留用于审计                                      │
│   └── 禁用/销毁                                                │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

### 版本操作

```bash
# 列出所有版本
gcloud secrets versions list prod/myapp/database/password \
    --project=myapp-prod

# 禁用旧版本
gcloud secrets versions disable 1 \
    --secret=prod/myapp/database/password \
    --project=myapp-prod

# 启用版本
gcloud secrets versions enable 1 \
    --secret=prod/myapp/database/password \
    --project=myapp-prod

# 销毁版本（不可恢复）
gcloud secrets versions destroy 1 \
    --secret=prod/myapp/database/password \
    --project=myapp-prod
```

## Secret 轮换策略

### 自动轮换配置

```hcl
# terraform/modules/secrets-rotation/main.tf

resource "google_secret_manager_secret" "rotating_secret" {
  secret_id = "${var.environment}/myapp/database/password"
  project   = var.project_id

  replication {
    automatic = true
  }

  rotation {
    rotation_period    = "2592000s"  # 30 days
    next_rotation_time = time_rotating.rotation.rotation_rfc3339
  }

  topics {
    name = google_pubsub_topic.secret_rotation.id
  }
}

resource "time_rotating" "rotation" {
  rotation_days = 30
}

resource "google_pubsub_topic" "secret_rotation" {
  name    = "secret-rotation-topic"
  project = var.project_id
}
```

### 轮换处理函数

```go
package rotation

import (
    "context"
    "log"
    
    "cloud.google.com/go/pubsub"
)

type SecretRotator struct {
    projectID string
}

func (r *SecretRotator) HandleRotation(ctx context.Context, msg *pubsub.Message) {
    secretName := string(msg.Data)
    log.Printf("Processing rotation for secret: %s", secretName)
    
    newPassword := generateSecurePassword()
    
    if err := r.updateDatabasePassword(ctx, newPassword); err != nil {
        log.Printf("Failed to update database password: %v", err)
        msg.Nack()
        return
    }
    
    if err := r.updateSecretVersion(ctx, secretName, newPassword); err != nil {
        log.Printf("Failed to update secret version: %v", err)
        msg.Nack()
        return
    }
    
    msg.Ack()
    log.Printf("Successfully rotated secret: %s", secretName)
}
```

## 权限管理

### IAM 角色

| 角色 | 说明 | 使用场景 |
|------|------|----------|
| `roles/secretmanager.admin` | 完全管理权限 | 管理员 |
| `roles/secretmanager.secretAccessor` | 读取 Secret | 应用服务账号 |
| `roles/secretmanager.viewer` | 查看 Secret 元数据 | 审计人员 |

### 最小权限配置

```hcl
# 仅授予特定 Secret 的访问权限
resource "google_secret_manager_secret_iam_member" "specific_secret_access" {
  secret_id = google_secret_manager_secret.db_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.app_service_account}"
}
```

## 安全最佳实践

### 1. 访问控制

- ✅ 使用 Workload Identity 而非服务账号密钥
- ✅ 遵循最小权限原则
- ✅ 定期审计 Secret 访问日志
- ❌ 不在代码中硬编码 Secret ID

### 2. Secret 存储

- ✅ 敏感信息必须存储在 Secret Manager
- ✅ 使用自动复制策略
- ✅ 启用版本管理
- ❌ 不在日志中输出 Secret 值

### 3. Secret 使用

- ✅ 按需读取，不缓存 Secret
- ✅ 使用最新版本或指定版本
- ✅ 实现优雅的 Secret 更新
- ❌ 不将 Secret 写入文件系统

### 4. 审计与监控

```bash
# 启用审计日志
gcloud projects set-iam-policy myapp-prod policy.yaml

# 查看 Secret 访问日志
gcloud logging read "resource.type=audited_resource AND \
    protoPayload.methodName=google.cloud.secretmanager.v1.SecretManagerService.AccessSecretVersion" \
    --project=myapp-prod
```

## Secret 清单模板

```yaml
# secrets-manifest.yaml
secrets:
  - name: prod/myapp/database/password
    description: "Production database password"
    type: string
    rotation:
      enabled: true
      period: 30d
    accessors:
      - myapp-sa@myapp-prod.iam.gserviceaccount.com
    
  - name: prod/myapp/database/host
    description: "Production database host"
    type: string
    rotation:
      enabled: false
    
  - name: prod/myapp/tls/myapp-tls-cert
    description: "TLS certificate for myapp"
    type: binary
    rotation:
      enabled: true
      period: 365d
    
  - name: prod/myapp/api-keys/stripe
    description: "Stripe API key"
    type: string
    rotation:
      enabled: true
      period: 90d
```

## 检查脚本

```bash
#!/bin/bash
# scripts/check-secrets.sh

ENV=${1:-prod}
PROJECT_ID="myapp-${ENV}"

echo "Checking secrets for ${ENV} environment..."

REQUIRED_SECRETS=(
    "${ENV}/myapp/database/password"
    "${ENV}/myapp/database/host"
    "${ENV}/myapp/database/user"
    "${ENV}/myapp/redis/password"
    "${ENV}/myapp/api-keys/external"
)

MISSING_SECRETS=()

for secret in "${REQUIRED_SECRETS[@]}"; do
    if ! gcloud secrets describe "$secret" --project="$PROJECT_ID" &>/dev/null; then
        MISSING_SECRETS+=("$secret")
        echo "❌ Missing: $secret"
    else
        echo "✅ Found: $secret"
    fi
done

if [ ${#MISSING_SECRETS[@]} -gt 0 ]; then
    echo ""
    echo "ERROR: Missing ${#MISSING_SECRETS[@]} secrets!"
    echo "Please create the missing secrets before deployment."
    exit 1
fi

echo ""
echo "All required secrets are present!"
```
