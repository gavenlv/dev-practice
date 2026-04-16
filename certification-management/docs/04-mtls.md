# 04 — mTLS 双向认证

> **难度**：⭐⭐⭐ 高级 | **阅读时间**：25 分钟 | **实践时间**：30 分钟

## 你将学到什么

- mTLS 和 TLS 的区别（为什么需要双向认证）
- 零信任网络架构
- 服务网格中的 mTLS（Istio/Linkerd）
- SPIFFE/SPIRE 身份框架
- 实战：搭建完整的 mTLS 环境

---

## 1. TLS vs mTLS

### 1.1 普通 TLS（单向认证）

```
客户端验证服务器身份：

客户端                                    服务器
  │                                         │
  │  "请出示你的证书"                        │
  │  ─────────────────────────────────────→ │
  │                                         │
  │  "这是我的证书"                          │
  │  ←───────────────────────────────────── │
  │                                         │
  │  客户端验证证书 ✅                       │
  │  "我相信你是真的服务器"                  │
  │                                         │
  │  ═══ 加密通信建立 ═══                   │

问题：服务器不知道客户端是谁
      任何人都可以连接服务器
```

### 1.2 mTLS（双向认证）

```
双方互相验证身份：

客户端                                    服务器
  │                                         │
  │  "请出示你的证书"                        │
  │  ─────────────────────────────────────→ │
  │                                         │
  │  "这是我的证书，也请出示你的"             │
  │  ←───────────────────────────────────── │
  │                                         │
  │  客户端验证服务器证书 ✅                  │
  │  "这是我的证书"                          │
  │  ─────────────────────────────────────→ │
  │                                         │
  │  服务器验证客户端证书 ✅                  │
  │  "我相信你是合法的客户端"                │
  │                                         │
  │  ═══ 双向信任的加密通信 ═══              │
```

### 1.3 对比

| | TLS（单向） | mTLS（双向） |
|---|-------------|-------------|
| 客户端验证服务器 | ✅ | ✅ |
| 服务器验证客户端 | ❌ | ✅ |
| 客户端需要证书 | ❌ | ✅ |
| 适用场景 | 公网服务 | 服务间通信 |
| 认证方式 | 服务器证书 | 双方证书 |
| 典型用户 | 浏览器 → 网站 | 微服务 → 微服务 |

---

## 2. 为什么需要 mTLS？

### 2.1 传统网络模型（城堡与护城河）

```
┌─────────────────────────────────────────────┐
│              可信内部网络                     │
│                                             │
│  ┌───────┐    ┌───────┐    ┌───────┐       │
│  │服务 A │←──→│服务 B │←──→│服务 C │       │
│  └───────┘    └───────┘    └───────┘       │
│                                             │
│  内部通信不需要加密，因为都在城墙内 ✅        │
└─────────────────────────────────────────────┘
         │
    ┌────┴────┐
    │  防火墙  │  ← 只保护边界
    └────┬────┘
         │
    外部不可信网络 ❌

问题：一旦攻击者进入内部网络，所有通信都是明文
     横向移动毫无阻碍
```

### 2.2 零信任模型（Zero Trust）

```
┌─────────────────────────────────────────────┐
│            零信任网络                         │
│                                             │
│  ┌───────┐  mTLS  ┌───────┐  mTLS ┌───────┐│
│  │服务 A │←══════→│服务 B │←═════→│服务 C ││
│  └───────┘        └───────┘       └───────┘│
│                                             │
│  每次通信都验证身份 + 加密                    │
│  不信任任何网络位置                           │
└─────────────────────────────────────────────┘

核心原则：
1. 永不信任，始终验证
2. 最小权限
3. 假设已被入侵
```

### 2.3 mTLS 解决的问题

| 问题 | 没有 mTLS | 有 mTLS |
|------|-----------|---------|
| 未授权访问 | 任何服务都能调用 | 只有持有有效证书的服务才能调用 |
| 中间人攻击 | 内部网络可能被监听 | 通信全程加密 |
| 身份伪造 | 无法确认调用方身份 | 证书证明身份 |
| 横向移动 | 入侵一个服务后自由移动 | 每个服务都需要独立证书 |

---

## 3. mTLS 握手过程

```
客户端                                    服务器
  │                                         │
  │  ① ClientHello                          │
  │  ─────────────────────────────────────→ │
  │                                         │
  │  ② ServerHello + Certificate            │
  │  ←───────────────────────────────────── │
  │  + CertificateRequest                   │  ← 关键！服务器请求客户端证书
  │                                         │
  │  ③ 验证服务器证书                        │
  │                                         │
  │  ④ Certificate (客户端证书)              │  ← 关键！客户端发送证书
  │  ─────────────────────────────────────→ │
  │                                         │
  │  ⑤ CertificateVerify                    │  ← 客户端证明持有私钥
  │  ─────────────────────────────────────→ │
  │                                         │
  │  ⑥ 服务器验证客户端证书                   │
  │                                         │
  │  ⑦ 双方计算密钥                          │
  │                                         │
  │  ⑧ Finished + ChangeCipherSpec          │
  │  ←────────────────────────────────────→ │
  │                                         │
  │  ═══ 双向认证的加密通道 ═══               │
```

与普通 TLS 的区别就是多了 **CertificateRequest** 和客户端的 **Certificate + CertificateVerify**。

---

## 4. 实战：搭建 mTLS 环境

### 4.1 创建私有 CA

```bash
#!/bin/bash
# scripts/generate-ca.sh

set -euo pipefail

CA_DIR="pki/root-ca"

mkdir -p "${CA_DIR}"

# 1. 生成根 CA 私钥
openssl genrsa -out "${CA_DIR}/ca.key" 4096

# 2. 生成根 CA 证书
openssl req -x509 -new -nodes \
  -key "${CA_DIR}/ca.key" \
  -sha256 -days 3650 \
  -out "${CA_DIR}/ca.crt" \
  -subj "/C=CN/ST=Shanghai/L=Shanghai/O=MyApp/CN=MyApp Root CA"

# 3. 创建 CA 配置文件
cat > "${CA_DIR}/ca.cnf" << 'EOF'
[ ca ]
default_ca = CA_default

[ CA_default ]
dir               = ./pki/root-ca
database          = $dir/index.txt
new_certs_dir     = $dir
serial            = $dir/serial
default_md        = sha256
default_days      = 365
policy            = policy_anything
copy_extensions   = copy

[ policy_anything ]
countryName            = optional
stateOrProvinceName    = optional
localityName           = optional
organizationName       = optional
organizationalUnitName = optional
commonName             = supplied
emailAddress           = optional
EOF

# 4. 初始化 CA 数据库
touch "${CA_DIR}/index.txt"
echo "01" > "${CA_DIR}/serial"

echo "✅ Root CA created:"
echo "   Key:  ${CA_DIR}/ca.key"
echo "   Cert: ${CA_DIR}/ca.crt"
```

### 4.2 签发服务器证书

```bash
#!/bin/bash
# scripts/generate-server-cert.sh

set -euo pipefail

CA_DIR="pki/root-ca"
SERVER_DIR="pki/certs/server"
SERVER_NAME="server.myapp.local"

mkdir -p "${SERVER_DIR}"

# 1. 生成服务器私钥
openssl genrsa -out "${SERVER_DIR}/${SERVER_NAME}.key" 2048

# 2. 创建扩展配置
cat > "${SERVER_DIR}/${SERVER_NAME}.ext" << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${SERVER_NAME}
DNS.2 = *.myapp.local
IP.1  = 127.0.0.1
EOF

# 3. 生成 CSR
openssl req -new \
  -key "${SERVER_DIR}/${SERVER_NAME}.key" \
  -out "${SERVER_DIR}/${SERVER_NAME}.csr" \
  -subj "/C=CN/ST=Shanghai/L=Shanghai/O=MyApp/CN=${SERVER_NAME}"

# 4. 用 CA 签发证书
openssl x509 -req \
  -in "${SERVER_DIR}/${SERVER_NAME}.csr" \
  -CA "${CA_DIR}/ca.crt" \
  -CAkey "${CA_DIR}/ca.key" \
  -CAcreateserial \
  -out "${SERVER_DIR}/${SERVER_NAME}.crt" \
  -days 365 -sha256 \
  -extfile "${SERVER_DIR}/${SERVER_NAME}.ext"

# 5. 验证证书链
openssl verify -CAfile "${CA_DIR}/ca.crt" "${SERVER_DIR}/${SERVER_NAME}.crt"

echo "✅ Server certificate created:"
echo "   Key:  ${SERVER_DIR}/${SERVER_NAME}.key"
echo "   Cert: ${SERVER_DIR}/${SERVER_NAME}.crt"
```

### 4.3 签发客户端证书

```bash
#!/bin/bash
# scripts/generate-client-cert.sh

set -euo pipefail

CA_DIR="pki/root-ca"
CLIENT_DIR="pki/certs/client"
CLIENT_NAME="client.myapp.local"

mkdir -p "${CLIENT_DIR}"

# 1. 生成客户端私钥
openssl genrsa -out "${CLIENT_DIR}/${CLIENT_NAME}.key" 2048

# 2. 创建扩展配置
cat > "${CLIENT_DIR}/${CLIENT_NAME}.ext" << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
extendedKeyUsage = clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${CLIENT_NAME}
EOF

# 3. 生成 CSR
openssl req -new \
  -key "${CLIENT_DIR}/${CLIENT_NAME}.key" \
  -out "${CLIENT_DIR}/${CLIENT_NAME}.csr" \
  -subj "/C=CN/ST=Shanghai/L=Shanghai/O=MyApp/CN=${CLIENT_NAME}"

# 4. 用 CA 签发证书
openssl x509 -req \
  -in "${CLIENT_DIR}/${CLIENT_NAME}.csr" \
  -CA "${CA_DIR}/ca.crt" \
  -CAkey "${CA_DIR}/ca.key" \
  -CAcreateserial \
  -out "${CLIENT_DIR}/${CLIENT_NAME}.crt" \
  -days 365 -sha256 \
  -extfile "${CLIENT_DIR}/${CLIENT_NAME}.ext"

# 5. 验证证书链
openssl verify -CAfile "${CA_DIR}/ca.crt" "${CLIENT_DIR}/${CLIENT_NAME}.crt"

echo "✅ Client certificate created:"
echo "   Key:  ${CLIENT_DIR}/${CLIENT_NAME}.key"
echo "   Cert: ${CLIENT_DIR}/${CLIENT_NAME}.crt"
```

### 4.4 Go mTLS 服务器

```go
package main

import (
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"log"
	"net/http"
	"os"
)

func main() {
	caCert, err := os.ReadFile("pki/root-ca/ca.crt")
	if err != nil {
		log.Fatalf("Failed to read CA cert: %v", err)
	}

	caCertPool := x509.NewCertPool()
	caCertPool.AppendCertsFromPEM(caCert)

	tlsConfig := &tls.Config{
		Certificates: []tls.Certificate{},
		ClientAuth:   tls.RequireAndVerifyClientCert,
		ClientCAs:    caCertPool,
		MinVersion:   tls.VersionTLS12,
		CipherSuites: []uint16{
			tls.TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,
			tls.TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,
		},
	}

	serverCert, err := tls.LoadX509KeyPair(
		"pki/certs/server/server.myapp.local.crt",
		"pki/certs/server/server.myapp.local.key",
	)
	if err != nil {
		log.Fatalf("Failed to load server cert: %v", err)
	}
	tlsConfig.Certificates = []tls.Certificate{serverCert}

	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.TLS != nil && len(r.TLS.PeerCertificates) > 0 {
			clientCN := r.TLS.PeerCertificates[0].Subject.CommonName
			fmt.Fprintf(w, "Hello, %s! mTLS authentication successful.", clientCN)
		} else {
			fmt.Fprintf(w, "Hello! No client certificate.")
		}
	})

	server := &http.Server{
		Addr:      ":8443",
		Handler:   mux,
		TLSConfig: tlsConfig,
	}

	log.Println("mTLS server starting on :8443")
	log.Fatal(server.ListenAndServeTLS("", ""))
}
```

### 4.5 Go mTLS 客户端

```go
package main

import (
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
)

func main() {
	caCert, err := os.ReadFile("pki/root-ca/ca.crt")
	if err != nil {
		log.Fatalf("Failed to read CA cert: %v", err)
	}

	caCertPool := x509.NewCertPool()
	caCertPool.AppendCertsFromPEM(caCert)

	clientCert, err := tls.LoadX509KeyPair(
		"pki/certs/client/client.myapp.local.crt",
		"pki/certs/client/client.myapp.local.key",
	)
	if err != nil {
		log.Fatalf("Failed to load client cert: %v", err)
	}

	tlsConfig := &tls.Config{
		RootCAs:      caCertPool,
		Certificates: []tls.Certificate{clientCert},
		MinVersion:   tls.VersionTLS12,
	}

	client := &http.Client{
		Transport: &http.Transport{
			TLSClientConfig: tlsConfig,
		},
	}

	resp, err := client.Get("https://server.myapp.local:8443/")
	if err != nil {
		log.Fatalf("Request failed: %v", err)
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	fmt.Println(string(body))
}
```

### 4.6 测试 mTLS

```bash
# 用 curl 测试 mTLS
curl --cacert pki/root-ca/ca.crt \
     --cert pki/certs/client/client.myapp.local.crt \
     --key pki/certs/client/client.myapp.local.key \
     https://server.myapp.local:8443/

# 输出：Hello, client.myapp.local! mTLS authentication successful.

# 不带客户端证书（应该失败）
curl --cacert pki/root-ca/ca.crt \
     https://server.myapp.local:8443/
# 输出：curl: (56) OpenSSL SSL_read: error:...
```

---

## 5. 服务网格中的 mTLS

### 5.1 为什么用服务网格？

手动管理每个服务的证书太痛苦了：
- 几十个/上百个服务
- 证书需要自动签发
- 证书需要自动轮换
- 策略需要统一管理

服务网格自动处理这些。

### 5.2 Istio mTLS

```
┌─────────────────────────────────────────────────────────────┐
│                    Istio 服务网格                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────┐                    ┌──────────┐              │
│  │ Service A │                    │ Service B │              │
│  │          │                    │          │              │
│  │ ┌──────┐ │   mTLS (自动)     │ ┌──────┐ │              │
│  │ │Envoy│←═╪══════════════════╪→│Envoy│ │              │
│  │ └──────┘ │                    │ └──────┘ │              │
│  └──────────┘                    └──────────┘              │
│       ↑                               ↑                    │
│       │ 证书由 Istio CA 自动签发和轮换  │                    │
│       └───────────────────────────────┘                    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 5.3 Istio mTLS 配置

```yaml
# 严格模式：只接受 mTLS
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: myapp
spec:
  mtls:
    mode: STRICT
---
# 目标规则：使用 Istio 双向 TLS
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: myapp-dr
  namespace: myapp
spec:
  host: "*.myapp.svc.cluster.local"
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
```

### 5.4 PeerAuthentication 模式

| 模式 | 行为 | 适用场景 |
|------|------|----------|
| UNSET | 继承父级策略 | 默认 |
| DISABLE | 不使用 mTLS | 兼容旧服务 |
| PERMISSIVE | 同时接受 mTLS 和明文 | 迁移期 |
| STRICT | 只接受 mTLS | 生产环境 |

### 5.5 迁移到 mTLS 的步骤

```
阶段 1：PERMISSIVE 模式
  └── 新旧服务都能通信，观察是否有问题

阶段 2：逐个服务切换到 STRICT
  └── 确认每个服务都支持 mTLS

阶段 3：全局 STRICT 模式
  └── 所有服务间通信强制 mTLS
```

---

## 6. SPIFFE/SPIRE

### 6.1 什么是 SPIFFE？

SPIFFE（Secure Production Identity Framework for Everyone）是一套服务身份标准。

```
传统身份：
  服务身份 = 证书的 CN（Common Name）
  问题：CN 是自由文本，没有统一格式

SPIFFE 身份：
  服务身份 = SPIFFE ID（URI 格式）
  spiffe://myapp.com/ns/myapp/sa/service-a

  格式：spiffe://<trust domain>/<path>
  - trust domain：信任域（类似组织）
  - path：服务路径（类似命名空间/服务名）
```

### 6.2 SPIFFE vs 传统 mTLS

| | 传统 mTLS | SPIFFE |
|---|-----------|--------|
| 身份格式 | CN=service-a | spiffe://domain/ns/sa/service-a |
| 身份粒度 | 粗（通常按服务） | 细（按工作负载） |
| 证书管理 | 手动或服务网格 | SPIRE 自动 |
| 跨平台 | 依赖特定实现 | 开放标准 |
| 证书轮换 | 需要额外机制 | SPIRE 自动（短寿命证书） |

### 6.3 SPIRE 架构

```
┌─────────────────────────────────────────────────────────┐
│                    SPIRE 架构                            │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌─────────────────────────────────────────────────┐   │
│  │              SPIRE Server                        │   │
│  │  - 管理信任域                                    │   │
│  │  - 签发 SVID（SPIFFE Verifiable Identity Doc）  │   │
│  │  - 管理注册条目                                  │   │
│  └──────────────────────┬──────────────────────────┘   │
│                         │                               │
│           ┌─────────────┼─────────────┐                 │
│           ▼             ▼             ▼                 │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐   │
│  │ SPIRE Agent  │ │ SPIRE Agent  │ │ SPIRE Agent  │   │
│  │  (Node A)    │ │  (Node B)    │ │  (Node C)    │   │
│  │              │ │              │ │              │   │
│  │ ┌──────────┐ │ │ ┌──────────┐ │ │ ┌──────────┐ │   │
│  │ │Workload A│ │ │ │Workload B│ │ │ │Workload C│ │   │
│  │ │  SVID    │ │ │ │  SVID    │ │ │ │  SVID    │ │   │
│  │ └──────────┘ │ │ └──────────┘ │ │ └──────────┘ │   │
│  └──────────────┘ └──────────────┘ └──────────────┘   │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### 6.4 SVID（SPIFFE Verifiable Identity Document）

SVID 是 SPIFFE 的身份凭证，可以是：
- **X.509 证书**：最常用，兼容 TLS
- **JWT 令牌**：适合非 TLS 场景

```
X.509 SVID：
- 标准 X.509 证书
- Subject Alternative Name (SAN) 中包含 SPIFFE ID
- 短寿命（默认 1 小时）
- 自动轮换

JWT SVID：
- 标准 JWT
- sub 字段包含 SPIFFE ID
- 适合跨服务调用传递身份
```

---

## 7. mTLS 最佳实践

### 7.1 证书管理

| 实践 | 说明 |
|------|------|
| 短寿命证书 | 证书有效期 ≤ 24 小时，减少泄露影响 |
| 自动轮换 | 使用 SPIRE 或 cert-manager 自动轮换 |
| 私钥保护 | 私钥不落盘，使用内存存储 |
| 证书撤销 | 实现 CRL 或 OCSP 检查 |

### 7.2 网络策略

```yaml
# Kubernetes NetworkPolicy + mTLS
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: myapp-policy
  namespace: myapp
spec:
  podSelector:
    matchLabels:
      app: myapp
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: myapp-client
      ports:
        - port: 8443
          protocol: TCP
```

### 7.3 监控和审计

```
监控指标：
- mTLS 握手成功率
- 证书过期时间
- 证书签发/轮换次数
- 未经认证的连接尝试

审计日志：
- 证书签发记录
- 证书撤销记录
- 连接建立记录
- 身份验证失败记录
```

---

## 8. 知识总结

### mTLS 适用场景

| 场景 | 推荐方案 |
|------|----------|
| 微服务间通信 | Istio/Linkerd mTLS |
| 零信任网络 | SPIRE + mTLS |
| API 网关认证 | mTLS + JWT |
| 数据库连接 | Cloud SQL mTLS |
| B2B API | mTLS 客户端证书 |

### 自检清单

- [ ] 我理解 mTLS 和 TLS 的区别
- [ ] 我知道零信任模型的核心原则
- [ ] 我能搭建完整的 mTLS 环境
- [ ] 我理解服务网格如何自动化 mTLS
- [ ] 我了解 SPIFFE/SPIRE 的作用
- [ ] 我知道如何从明文通信迁移到 mTLS

---

**上一篇**：[HTTPS 实战 ←](03-https.md) | **下一篇**：[证书管理 →](05-certificate-management.md)
