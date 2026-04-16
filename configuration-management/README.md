# 配置管理实践指南

## 概述

本指南总结了多环境配置管理的最佳实践，涵盖本地开发、测试环境（dev、sit、uat）和生产环境（prod），重点关注：

- **多环境配置隔离**：确保各环境配置独立、互不干扰
- **敏感信息管理**：使用 GCP Secret Manager 安全管理 secrets
- **安全连接**：所有服务连接强制 TLS/SSL
- **GKE 部署**：Kubernetes 环境下的配置注入策略

## 环境架构

```
┌─────────────────────────────────────────────────────────────────┐
│                        环境架构图                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐      │
│  │    Local     │    │  Dev / SIT   │    │  UAT / Prod  │      │
│  │   开发环境    │    │   测试环境    │    │  预生产/生产  │      │
│  └──────┬───────┘    └──────┬───────┘    └──────┬───────┘      │
│         │                   │                   │               │
│         ▼                   ▼                   ▼               │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐      │
│  │  .env 文件   │    │ GCP Secret   │    │ GCP Secret   │      │
│  │  本地配置    │    │   Manager    │    │   Manager    │      │
│  └──────────────┘    └──────────────┘    └──────────────┘      │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                    GCP 服务 (TLS 连接)                    │  │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────────┐  │  │
│  │  │CloudSQL │  │ PubSub  │  │  GCS    │  │  其他服务    │  │  │
│  │  └─────────┘  └─────────┘  └─────────┘  └─────────────┘  │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 目录结构

```
configuration-management/
├── README.md                          # 本文档
├── docs/                              # 文档目录
│   ├── environment-strategy.md        # 多环境配置策略
│   ├── secret-management.md           # Secret 管理实践
│   ├── tls-ssl-configuration.md       # TLS/SSL 配置实践
│   └── gke-deployment.md              # GKE 部署配置实践
├── examples/                          # 代码示例
│   ├── go/                            # Go 配置加载示例
│   ├── python/                        # Python 配置加载示例
│   └── nodejs/                        # Node.js 配置加载示例
├── kubernetes/                        # Kubernetes 配置
│   ├── base/                          # 基础配置
│   └── overlays/                      # 环境覆盖配置
├── terraform/                         # Terraform 配置
│   ├── modules/                       # 模块
│   └── environments/                  # 环境配置
└── scripts/                           # 工具脚本
    ├── validate-config.sh             # 配置验证脚本
    └── check-secrets.sh               # Secret 检查脚本
```

## 核心原则

### 1. 配置分层原则

```
优先级（从高到低）：
1. 环境变量 (最高优先级，用于运行时覆盖)
2. Secret Manager (敏感信息)
3. 环境特定配置文件
4. 默认配置 (最低优先级)
```

### 2. 敏感信息处理原则

- ✅ **必须**：使用 Secret Manager 存储敏感信息
- ✅ **必须**：配置文件中不包含明文密码、密钥
- ✅ **必须**：日志中脱敏处理敏感配置
- ❌ **禁止**：将 secrets 提交到代码仓库
- ❌ **禁止**：在容器镜像中硬编码 secrets

### 3. 环境隔离原则

- 各环境使用独立的 GCP Project
- 各环境使用独立的 Secret Manager
- 生产环境数据**绝不**同步到非生产环境
- 配置变更需要经过审批流程

## 快速开始

### 本地开发环境配置

```bash
# 1. 复制配置模板
cp examples/env.template .env.local

# 2. 填写本地配置
vim .env.local

# 3. 启动应用
APP_ENV=local go run main.go
```

### GKE 环境部署

```bash
# 1. 验证配置
./scripts/validate-config.sh prod

# 2. 检查 secrets 是否配置完整
./scripts/check-secrets.sh prod

# 3. 部署到 GKE
kubectl apply -k kubernetes/overlays/prod
```

## 配置检查清单

### 部署前检查

- [ ] 所有必需的环境变量已配置
- [ ] Secret Manager 中的 secrets 已创建
- [ ] TLS 证书已配置且未过期
- [ ] 数据库连接字符串使用 TLS
- [ ] 服务账号权限已正确配置
- [ ] 配置变更已通过代码评审

### 安全检查

- [ ] 无明文密码或密钥在代码中
- [ ] 无生产数据在测试环境
- [ ] 所有外部连接使用 TLS
- [ ] Secret 访问权限最小化
- [ ] 审计日志已启用

## 相关文档

| 文档 | 说明 |
|------|------|
| [环境配置策略](docs/environment-strategy.md) | 多环境配置管理详细策略 |
| [Secret 管理](docs/secret-management.md) | GCP Secret Manager 使用实践 |
| [TLS/SSL 配置](docs/tls-ssl-configuration.md) | 安全连接配置实践 |
| [GKE 部署](docs/gke-deployment.md) | Kubernetes 部署配置实践 |

## 最佳实践总结

1. **配置即代码**：所有配置文件纳入版本控制
2. **环境变量优先**：敏感信息通过环境变量/Secret Manager 注入
3. **默认安全**：所有连接默认使用 TLS
4. **最小权限**：服务账号仅授予必需权限
5. **审计追踪**：记录所有配置变更
6. **自动化验证**：CI/CD 中集成配置检查

## 常见问题

### Q: 如何处理本地开发时的 secrets？

A: 本地开发使用 `.env.local` 文件，该文件已添加到 `.gitignore`。敏感信息可使用本地模拟值或开发环境的 secrets。

### Q: 如何确保配置不被遗漏？

A: 使用配置验证脚本和 CI/CD 检查，确保所有必需配置项都已设置。

### Q: 生产环境配置变更流程？

A: 通过 Terraform 或 Kubernetes 配置变更，需要代码评审和审批后才能部署。
