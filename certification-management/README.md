# SSL / TLS / mTLS / HTTPS — 从零基础到专家

## 这是什么？

你每天上网，地址栏里那个 🔒 小锁头，背后就是这套技术。  
本指南从"什么是加密"开始，一直讲到企业级 mTLS 零信任架构，让你真正搞懂每一层。

## 学习路径

```
入门 ──────────────────────────────────────────────────── 专家

  ① 密码学基础        ② SSL/TLS 协议       ③ HTTPS 实战
  ┌──────────┐      ┌──────────────┐     ┌──────────┐
  │ 对称加密  │      │  握手过程     │     │  浏览器   │
  │ 非对称加密│  →   │  密码套件     │  →  │  服务器   │
  │ 哈希算法  │      │  证书链       │     │  调试技巧 │
  │ 数字签名  │      │  协议版本     │     │  性能优化 │
  └──────────┘      └──────────────┘     └──────────┘

       ④ mTLS 零信任         ⑤ 证书管理           ⑥ GCP/GKE 实战
      ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
      │ 双向认证      │     │  PKI 体系     │     │  Google CA   │
      │ 服务网格      │  →  │  证书生命周期 │  →  │  GKE Ingress │
      │ 零信任网络    │     │  自动轮换     │     │  Workload    │
      │ SPIFFE/SPIRE │     │  审计合规     │     │  mTLS        │
      └──────────────┘     └──────────────┘     └──────────────┘
```

## 文档目录

| # | 文档 | 难度 | 你将学到 |
|---|------|------|----------|
| 1 | [密码学与证书基础](docs/01-fundamentals.md) | ⭐ 入门 | 加密原理、公钥私钥、数字证书是什么 |
| 2 | [SSL/TLS 协议详解](docs/02-ssl-tls-protocol.md) | ⭐⭐ 进阶 | 握手全过程、密码套件、协议版本演进 |
| 3 | [HTTPS 实战](docs/03-https.md) | ⭐⭐ 进阶 | HTTPS 工作原理、配置、调试、性能优化 |
| 4 | [mTLS 双向认证](docs/04-mtls.md) | ⭐⭐⭐ 高级 | 零信任、服务网格、SPIFFE/SPIRE |
| 5 | [证书管理](docs/05-certificate-management.md) | ⭐⭐⭐ 高级 | PKI 体系、证书生命周期、自动轮换 |
| 6 | [GCP/GKE 证书实践](docs/06-gcp-gke-practice.md) | ⭐⭐⭐⭐ 专家 | Google CAS、GKE TLS、Workload mTLS |

## 实践目录

```
certification-management/
├── README.md
├── docs/                           # 理论文档
│   ├── 01-fundamentals.md
│   ├── 02-ssl-tls-protocol.md
│   ├── 03-https.md
│   ├── 04-mtls.md
│   ├── 05-certificate-management.md
│   └── 06-gcp-gke-practice.md
├── scripts/                        # 实践脚本
│   ├── generate-ca.sh              # 生成私有 CA
│   ├── generate-server-cert.sh     # 生成服务器证书
│   ├── generate-client-cert.sh     # 生成客户端证书
│   ├── verify-cert-chain.sh        # 验证证书链
│   └── check-tls-endpoint.sh       # 检查 TLS 端点
├── examples/                       # 代码示例
│   ├── go/
│   │   └── tls-server/             # Go TLS 服务器
│   ├── python/
│   │   └── tls-server/             # Python TLS 服务器
│   └── nginx/
│       └── tls-config/             # Nginx TLS 配置
└── pki/                            # PKI 实践
    ├── root-ca/                    # 根 CA
    ├── intermediate-ca/            # 中间 CA
    └── certs/                      # 签发证书
```

## 速查表

### 关键概念一句话总结

| 概念 | 一句话 |
|------|--------|
| **SSL** | 已淘汰的安全协议，TLS 的前身 |
| **TLS** | 当前使用的安全传输协议，SSL 的继任者 |
| **HTTPS** | HTTP + TLS = 加密的网页传输 |
| **mTLS** | 双方都要出示证书，不只是服务器证明自己 |
| **证书** | 公钥 + 身份信息 + CA 签名，类似电子身份证 |
| **CA** | 证书颁发机构，类似公安局，负责签发证书 |
| **PKI** | 公钥基础设施，管理证书的整套体系 |

### TLS 版本对照

| 版本 | 年份 | 状态 | 安全性 |
|------|------|------|--------|
| SSL 3.0 | 1996 | ❌ 已废弃 | POODLE 攻击 |
| TLS 1.0 | 1999 | ❌ 已废弃 | BEAST 攻击 |
| TLS 1.1 | 2006 | ❌ 已废弃 | 缺乏现代加密 |
| TLS 1.2 | 2008 | ✅ 广泛使用 | 安全（配置正确时） |
| TLS 1.3 | 2018 | ✅ 推荐使用 | 最安全、最快 |

### 常用端口

| 服务 | 端口 | 协议 |
|------|------|------|
| HTTPS | 443 | TLS over TCP |
| SMTPS | 465 | TLS over TCP |
| LDAPS | 636 | TLS over TCP |
| MQTTs | 8883 | TLS over TCP |
| Database (PostgreSQL) | 5432 | 可选 TLS |
| Redis | 6379 | 可选 TLS |

## 快速开始

### 5 分钟体验 TLS

```bash
# 查看网站的证书信息
openssl s_client -connect google.com:443 -showcerts

# 查看证书详情
echo | openssl s_client -connect google.com:443 2>/dev/null | openssl x509 -noout -text

# 测试 TLS 版本
openssl s_client -connect google.com:443 -tls1_3 < /dev/null
```

### 10 分钟生成自己的证书

```bash
# 1. 生成私钥
openssl genrsa -out server.key 2048

# 2. 生成证书签名请求 (CSR)
openssl req -new -key server.key -out server.csr -subj "/CN=myapp.local"

# 3. 自签名证书（仅开发用！）
openssl x509 -req -in server.csr -signkey server.key -out server.crt -days 365

# 4. 验证证书
openssl x509 -in server.crt -text -noout
```

## 谁应该读这个？

| 角色 | 推荐章节 | 你将收获 |
|------|----------|----------|
| 后端开发者 | 1→2→3 | 搞懂 HTTPS，正确配置 TLS |
| 运维工程师 | 2→3→5→6 | 管理证书、排查 TLS 问题 |
| 安全工程师 | 全部 | 深入理解协议、零信任架构 |
| 架构师 | 4→5→6 | 设计安全的服务间通信 |
| 零基础 | 1→2→3 | 从"什么是加密"开始理解 |

## 前置知识

- **入门篇**（1-3）：无前置要求，从零开始
- **进阶篇**（4-5）：需要基本的网络知识（TCP/IP）
- **专家篇**（6）：需要 GCP/Kubernetes 基础
