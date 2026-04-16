# 多环境配置策略

## 环境定义

| 环境 | 用途 | 数据 | GCP Project | 访问权限 |
|------|------|------|-------------|----------|
| local | 本地开发 | 模拟数据 | 无（本地） | 开发者 |
| dev | 开发测试 | 测试数据 | myapp-dev | 开发团队 |
| sit | 系统集成测试 | 测试数据 | myapp-sit | 开发+QA |
| uat | 用户验收测试 | 测试数据 | myapp-uat | QA+业务 |
| prod | 生产环境 | **生产数据** | myapp-prod | 运维团队 |

## 配置分层架构

```
┌────────────────────────────────────────────────────────────────┐
│                        配置加载顺序                             │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  ① 默认配置 (config.default.yaml)                              │
│     └── 应用默认值，所有环境共享                                │
│                                                                │
│  ② 环境配置 (config.{env}.yaml)                                │
│     └── 环境特定配置，覆盖默认值                                │
│                                                                │
│  ③ Secret Manager                                              │
│     └── 敏感信息，运行时注入                                    │
│                                                                │
│  ④ 环境变量                                                    │
│     └── 最高优先级，用于运行时覆盖                              │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

## 配置文件结构

### 目录结构

```
config/
├── config.default.yaml          # 默认配置
├── config.local.yaml            # 本地开发配置
├── config.dev.yaml              # Dev 环境配置
├── config.sit.yaml              # SIT 环境配置
├── config.uat.yaml              # UAT 环境配置
├── config.prod.yaml             # 生产环境配置
└── secrets/                     # Secret 配置（不提交到仓库）
    ├── .gitkeep
    └── secrets.local.yaml       # 本地 secrets 模板
```

### 配置文件示例

#### config.default.yaml

```yaml
app:
  name: myapp
  port: 8080
  log_level: info

database:
  host: localhost
  port: 5432
  name: myapp
  ssl_mode: require
  max_connections: 10
  connection_timeout: 30s

redis:
  host: localhost
  port: 6379
  ssl: true
  pool_size: 10

pubsub:
  project_id: ${GCP_PROJECT_ID}
  subscription_timeout: 30s

features:
  feature_a: false
  feature_b: false
```

#### config.dev.yaml

```yaml
app:
  log_level: debug

database:
  host: dev-db.myapp-dev.svc.cluster.local
  name: myapp_dev
  max_connections: 5

redis:
  host: dev-redis.myapp-dev.svc.cluster.local

features:
  feature_a: true
  feature_b: true
```

#### config.prod.yaml

```yaml
app:
  log_level: warn

database:
  host: prod-db.myapp-prod.svc.cluster.local
  name: myapp_prod
  max_connections: 50

redis:
  host: prod-redis.myapp-prod.svc.cluster.local
  pool_size: 50

features:
  feature_a: true
  feature_b: false
```

## 环境变量规范

### 命名规范

```bash
# 格式: {SERVICE}_{COMPONENT}_{ATTRIBUTE}

# 数据库配置
DATABASE_HOST=xxx
DATABASE_PORT=5432
DATABASE_NAME=myapp
DATABASE_USER=xxx
DATABASE_PASSWORD=xxx

# Redis 配置
REDIS_HOST=xxx
REDIS_PORT=6379
REDIS_PASSWORD=xxx

# GCP 配置
GCP_PROJECT_ID=myapp-prod
GCP_REGION=asia-east1
```

### 必需环境变量清单

```bash
# 应用环境
APP_ENV=local|dev|sit|uat|prod

# GCP 配置（非本地环境）
GCP_PROJECT_ID=
GCP_REGION=

# 数据库（通过 Secret Manager 注入）
DATABASE_HOST=
DATABASE_PORT=
DATABASE_NAME=
DATABASE_USER=
DATABASE_PASSWORD=

# Redis（通过 Secret Manager 注入）
REDIS_HOST=
REDIS_PASSWORD=
```

## 配置注入策略

### 本地开发环境

```yaml
# docker-compose.yaml
services:
  app:
    build: .
    env_file:
      - .env.local
    environment:
      - APP_ENV=local
    volumes:
      - ./config:/app/config:ro
```

### GKE 环境

```yaml
# Kubernetes Deployment
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
            - name: APP_ENV
              value: "prod"
            - name: GCP_PROJECT_ID
              value: "myapp-prod"
          envFrom:
            - configMapRef:
                name: myapp-config
            - secretRef:
                name: myapp-secrets
```

## 配置验证

### 必需配置项检查

```yaml
# config-schema.yaml
required:
  - app.name
  - app.port
  - database.host
  - database.name
  - database.ssl_mode
  - redis.host
  - redis.ssl

sensitive:
  - database.password
  - redis.password
  - api_keys.*

patterns:
  database.ssl_mode: "^(disable|require|verify-ca|verify-full)$"
  app.port: "^[0-9]+$"
```

### 验证脚本

```bash
#!/bin/bash
# scripts/validate-config.sh

ENV=${1:-local}
CONFIG_FILE="config/config.${ENV}.yaml"

echo "Validating configuration for ${ENV} environment..."

# 检查配置文件存在
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Config file not found: $CONFIG_FILE"
    exit 1
fi

# 检查必需字段
required_fields=(
    "app.name"
    "app.port"
    "database.host"
)

for field in "${required_fields[@]}"; do
    if ! yq eval ".${field}" "$CONFIG_FILE" | grep -q .; then
        echo "ERROR: Required field missing: $field"
        exit 1
    fi
done

# 检查敏感信息是否明文
if grep -E "(password|secret|key|token)" "$CONFIG_FILE" | grep -v "^\s*#" | grep -q ":"; then
    echo "WARNING: Possible sensitive data in config file"
fi

echo "Configuration validation passed!"
```

## 环境切换机制

### 通过环境变量切换

```bash
# 设置环境
export APP_ENV=dev

# 应用自动加载 config/config.dev.yaml
```

### 通过启动参数切换

```bash
# 命令行指定
./myapp --env=prod --config=/path/to/config
```

### 配置加载代码示例

```go
package config

import (
    "fmt"
    "os"
    "strings"

    "gopkg.in/yaml.v3"
)

type Config struct {
    App      AppConfig      `yaml:"app"`
    Database DatabaseConfig `yaml:"database"`
    Redis    RedisConfig    `yaml:"redis"`
}

func Load() (*Config, error) {
    env := getEnv("APP_ENV", "local")
    
    cfg := &Config{}
    
    if err := loadDefault(cfg); err != nil {
        return nil, err
    }
    
    if err := loadEnvironment(cfg, env); err != nil {
        return nil, err
    }
    
    if err := loadFromEnvVars(cfg); err != nil {
        return nil, err
    }
    
    return cfg, nil
}

func getEnv(key, defaultValue string) string {
    if value := os.Getenv(key); value != "" {
        return value
    }
    return defaultValue
}
```

## 配置变更流程

### 变更审批流程

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│  提交变更   │ -> │  代码评审   │ -> │  测试验证   │ -> │  部署上线   │
│  (PR)      │    │  (Review)   │    │  (CI/CD)    │    │  (Deploy)   │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
      │                  │                  │                  │
      ▼                  ▼                  ▼                  ▼
  配置文件变更      至少1人审批        自动化测试        分阶段发布
  说明变更原因      安全审查          配置验证          回滚预案
```

### 生产环境变更要求

1. **变更申请**：提交 PR 并填写变更说明
2. **代码评审**：至少 2 人审批，包括运维人员
3. **测试验证**：在 UAT 环境验证通过
4. **变更窗口**：在批准的维护窗口执行
5. **回滚预案**：准备回滚方案和脚本

## 配置审计

### 审计日志

```json
{
  "timestamp": "2024-01-15T10:30:00Z",
  "event": "config_change",
  "environment": "prod",
  "user": "admin@example.com",
  "changes": [
    {
      "field": "database.max_connections",
      "old_value": "30",
      "new_value": "50"
    }
  ],
  "approved_by": ["reviewer1@example.com", "reviewer2@example.com"],
  "ticket": "JIRA-12345"
}
```

### 变更追踪

```bash
# 查看配置变更历史
git log --oneline config/config.prod.yaml

# 查看特定配置的变更
git log -p -- config/config.prod.yaml | grep "max_connections"
```

## 最佳实践

### 1. 配置文件管理

- ✅ 所有配置文件纳入版本控制
- ✅ 使用 YAML 格式，便于阅读和维护
- ✅ 配置文件中添加注释说明
- ✅ 使用配置模板和示例文件

### 2. 敏感信息处理

- ✅ 敏感信息通过 Secret Manager 管理
- ✅ 配置文件中使用占位符引用 secrets
- ✅ 日志输出时脱敏处理
- ❌ 不在配置文件中存储明文密码

### 3. 环境隔离

- ✅ 每个环境独立的配置文件
- ✅ 生产环境使用独立的 GCP Project
- ✅ 配置变更需要审批流程
- ❌ 不在生产环境使用测试配置

### 4. 配置验证

- ✅ 启动时验证必需配置项
- ✅ CI/CD 中集成配置检查
- ✅ 定期审计配置合规性
- ❌ 不跳过配置验证步骤
