# 05 — 证书管理

> **难度**：⭐⭐⭐ 高级 | **阅读时间**：25 分钟 | **实践时间**：30 分钟

## 你将学到什么

- PKI 体系架构设计
- 证书生命周期管理（签发→部署→监控→轮换→吊销）
- cert-manager 自动化证书管理
- 证书监控和告警
- 合规和审计

---

## 1. PKI 体系架构

### 1.1 什么是 PKI？

PKI（Public Key Infrastructure）= 公钥基础设施，是管理证书的整套体系。

```
┌─────────────────────────────────────────────────────────────┐
│                      PKI 体系                                │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                  根 CA (Root CA)                     │   │
│  │  - 最高信任锚点                                      │   │
│  │  - 私钥离线保存（HSM）                               │   │
│  │  - 只签发中间 CA 证书                                │   │
│  │  - 有效期 10-25 年                                   │   │
│  └───────────────────────┬─────────────────────────────┘   │
│                          │ 签名                             │
│           ┌──────────────┼──────────────┐                   │
│           ▼              ▼              ▼                   │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐       │
│  │ 中间 CA A    │ │ 中间 CA B    │ │ 中间 CA C    │       │
│  │ (Web 服务器) │ │ (内部服务)   │ │ (客户端)     │       │
│  │ 有效期 5-10年│ │ 有效期 5-10年│ │ 有效期 5-10年│       │
│  └──────┬───────┘ └──────┬───────┘ └──────┬───────┘       │
│         │                │                │                 │
│         ▼                ▼                ▼                 │
│  ┌──────────┐     ┌──────────┐     ┌──────────┐           │
│  │终端证书  │     │终端证书  │     │终端证书  │           │
│  │(服务器)  │     │(服务间)  │     │(客户端)  │           │
│  │有效期≤1年│     │有效期≤90天│    │有效期≤90天│          │
│  └──────────┘     └──────────┘     └──────────┘           │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              支撑组件                                │   │
│  │  - 证书注册机构 (RA)：验证申请者身份                  │   │
│  │  - 证书目录 (LDAP/HTTP)：发布证书                    │   │
│  │  - OCSP/CRL 服务：证书状态查询                       │   │
│  │  - HSM：硬件安全模块，保护 CA 私钥                   │   │
│  │  - 审计日志：记录所有操作                            │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 三层 CA 架构

| 层级 | 用途 | 私钥保护 | 有效期 | 签发对象 |
|------|------|----------|--------|----------|
| 根 CA | 信任锚点 | HSM 离线 | 10-25 年 | 中间 CA |
| 中间 CA | 分层管理 | HSM/加密存储 | 5-10 年 | 终端证书 |
| 终端证书 | 实际使用 | 文件/内存 | ≤1 年 | 无 |

**为什么要三层？**

- 根 CA 私钥离线 → 即使中间 CA 被攻破，根 CA 安全
- 中间 CA 分层 → 不同用途用不同中间 CA，隔离风险
- 终端证书短寿命 → 减少泄露影响

---

## 2. 证书生命周期

```
┌──────────────────────────────────────────────────────────────────┐
│                     证书生命周期                                   │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. 申请 ──→ 2. 验证 ──→ 3. 签发 ──→ 4. 部署                    │
│     │            │          │          │                         │
│     │  提交CSR   │  验证身份 │  CA签名  │  安装到服务器            │
│     │            │          │          │                         │
│  ───┴────────────┴──────────┴──────────┴────────────────────── │
│                                                                  │
│  5. 监控 ──→ 6. 续期 ──→ 7. 轮换 ──→ 8. 吊销（如需要）          │
│     │            │          │          │                         │
│     │  检查过期  │  重新签发 │  替换证书 │  紧急撤销              │
│     │            │          │          │                         │
│  ───┴────────────┴──────────┴──────────┴────────────────────── │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

### 2.1 申请与验证

```
申请者                         CA/RA
  │                              │
  │  1. 生成密钥对               │
  │  2. 生成 CSR                 │
  │  3. 提交 CSR ──────────────→ │
  │                              │  4. 验证身份
  │                              │     - 域名控制权（DNS/HTTP）
  │                              │     - 组织信息（OV/EV）
  │  5. 完成验证挑战 ←────────── │
  │  6. 响应挑战 ──────────────→ │
  │                              │  7. 签发证书
  │  8. 下载证书 ←────────────── │
  │                              │
```

### 2.2 部署

```
证书部署位置：

1. Web 服务器（Nginx/Apache）
   └── ssl_certificate / ssl_certificate_key

2. 应用服务器（Go/Java/Node.js）
   └── TLS 配置中加载证书和私钥

3. Kubernetes
   └── Secret → 挂载到 Pod

4. 负载均衡器
   └── GKE Ingress / Google Cloud Load Balancer

5. 服务网格
   └── Istio/Linkerd 自动注入
```

### 2.3 监控

```bash
# 检查证书过期时间
echo | openssl s_client -connect api.myapp.com:443 2>/dev/null | \
  openssl x509 -noout -enddate

# 批量检查证书过期
for domain in api.myapp.com app.myapp.com admin.myapp.com; do
  expiry=$(echo | openssl s_client -connect "$domain:443" 2>/dev/null | \
    openssl x509 -noout -enddate | cut -d= -f2)
  echo "$domain: $expiry"
done

# 计算剩余天数
echo | openssl s_client -connect api.myapp.com:443 2>/dev/null | \
  openssl x509 -noout -checkend 2592000
# 2592000 = 30 天的秒数
# 返回 0 = 证书在 30 天内不会过期
# 返回 1 = 证书将在 30 天内过期
```

### 2.4 续期与轮换

```
证书轮换策略：

方式一：原地替换
  1. 获取新证书
  2. 替换证书文件
  3. 重载服务（nginx -s reload）

方式二：蓝绿轮换
  1. 部署新版本（带新证书）
  2. 切换流量到新版本
  3. 下线旧版本

方式三：自动轮换（推荐）
  cert-manager / Istio / SPIRE 自动处理
```

### 2.5 吊销

```
证书吊销场景：
- 私钥泄露
- 证书信息错误
- 服务下线
- 安全事件

吊销方式：

CRL（Certificate Revocation List）：
  - CA 定期发布吊销列表
  - 客户端下载并缓存
  - 缺点：列表可能很大，更新不及时

OCSP（Online Certificate Status Protocol）：
  - 客户端实时查询证书状态
  - 缺点：隐私问题，CA 知道你访问了谁

OCSP Stapling：
  - 服务器定期获取 OCSP 响应
  - 在 TLS 握手时附带 OCSP 响应
  - 最佳方案 ✅
```

---

## 3. cert-manager 自动化证书管理

### 3.1 架构

```
┌─────────────────────────────────────────────────────────────┐
│                    cert-manager 架构                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                  cert-manager                         │  │
│  │                                                      │  │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐    │  │
│  │  │  Issuer    │  │ Certificate│  │  Challenge │    │  │
│  │  │  (签发者)   │  │ (证书资源) │  │  (验证方式) │    │  │
│  │  └────────────┘  └────────────┘  └────────────┘    │  │
│  │         │                                      │     │  │
│  │         ▼                                      ▼     │  │
│  │  ┌──────────────────────────────────────────────────┐│  │
│  │  │              CA / ACME 服务                      ││  │
│  │  │  - Let's Encrypt                                ││  │
│  │  │  - Google CAS                                   ││  │
│  │  │  - Vault PKI                                    ││  │
│  │  │  - 自建 CA                                      ││  │
│  │  └──────────────────────────────────────────────────┘│  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                  Kubernetes                           │  │
│  │  Secret ← cert-manager 自动创建和更新                 │  │
│  │  Ingress ← 自动配置 TLS                              │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 安装 cert-manager

```bash
# 安装 cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.yaml

# 验证安装
kubectl get pods -n cert-manager
```

### 3.3 配置 Let's Encrypt Issuer

```yaml
# ClusterIssuer（集群级别）
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@myapp.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            class: gce
---
# Staging Issuer（测试用，避免速率限制）
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: admin@myapp.com
    privateKeySecretRef:
      name: letsencrypt-staging
    solvers:
      - http01:
          ingress:
            class: gce
```

### 3.4 自动签发证书

```yaml
# 方式一：Ingress 注解自动签发
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-ingress
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  tls:
    - hosts:
        - api.myapp.com
      secretName: myapp-tls
  rules:
    - host: api.myapp.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: myapp
                port:
                  number: 80
---
# 方式二：Certificate 资源
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: myapp-cert
  namespace: myapp
spec:
  secretName: myapp-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - api.myapp.com
    - www.myapp.com
  duration: 2160h    # 90 天
  renewBefore: 360h  # 过期前 15 天续期
```

### 3.5 DNS 验证（通配符证书）

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-dns
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@myapp.com
    privateKeySecretRef:
      name: letsencrypt-dns
    solvers:
      - dns01:
          cloudDNS:
            project: myapp-prod
            serviceAccountSecretRef:
              name: cert-manager-dns01-sa
              key: key.json
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: myapp-wildcard
  namespace: myapp
spec:
  secretName: myapp-wildcard-tls
  issuerRef:
    name: letsencrypt-dns
    kind: ClusterIssuer
  dnsNames:
    - myapp.com
    - "*.myapp.com"
```

### 3.6 私有 CA Issuer

```yaml
# 创建 CA 私钥和证书的 Secret
apiVersion: v1
kind: Secret
metadata:
  name: ca-key-pair
  namespace: cert-manager
data:
  tls.crt: <base64-encoded-ca-cert>
  tls.key: <base64-encoded-ca-key>
---
# 创建 CA Issuer
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: myapp-ca
spec:
  ca:
    secretName: ca-key-pair
---
# 用私有 CA 签发证书
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: internal-service
  namespace: myapp
spec:
  secretName: internal-service-tls
  issuerRef:
    name: myapp-ca
    kind: ClusterIssuer
  dnsNames:
    - internal-service.myapp.svc.cluster.local
  duration: 720h    # 30 天
  renewBefore: 168h # 过期前 7 天续期
  usages:
    - server auth
    - client auth
```

---

## 4. 证书监控和告警

### 4.1 Prometheus 监控

```yaml
# cert-manager 已经暴露了 Prometheus 指标
# 关键指标：
# - certmanager_certificate_expiration_timestamp_seconds
# - certmanager_certificate_ready_status
# - certmanager_order_status

# PrometheusRule 告警
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: cert-manager-alerts
  namespace: cert-manager
spec:
  groups:
    - name: cert-manager
      rules:
        - alert: CertificateExpiringSoon
          expr: |
            (certmanager_certificate_expiration_timestamp_seconds - time()) / 86400 < 30
          for: 1h
          labels:
            severity: warning
          annotations:
            summary: "Certificate {{ $labels.name }} expiring in less than 30 days"
            
        - alert: CertificateExpiringCritical
          expr: |
            (certmanager_certificate_expiration_timestamp_seconds - time()) / 86400 < 7
          for: 1h
          labels:
            severity: critical
          annotations:
            summary: "Certificate {{ $labels.name }} expiring in less than 7 days"
            
        - alert: CertificateIssuanceFailed
          expr: |
            certmanager_certificate_ready_status{condition="Ready", status="False"} == 1
          for: 1h
          labels:
            severity: critical
          annotations:
            summary: "Certificate {{ $labels.name }} issuance failed"
```

### 4.2 外部检查脚本

```bash
#!/bin/bash
# scripts/check-cert-expiry.sh

DOMAINS=(
  "api.myapp.com"
  "app.myapp.com"
  "admin.myapp.com"
)

WARNING_DAYS=30
CRITICAL_DAYS=7

for domain in "${DOMAINS[@]}"; do
  expiry_epoch=$(echo | openssl s_client -connect "$domain:443" -servername "$domain" 2>/dev/null | \
    openssl x509 -noout -enddate | cut -d= -f2 | xargs -I{} date -d "{}" +%s)
  
  current_epoch=$(date +%s)
  days_left=$(( (expiry_epoch - current_epoch) / 86400 ))
  
  if [ "$days_left" -lt "$CRITICAL_DAYS" ]; then
    echo "🔴 CRITICAL: $domain expires in $days_left days"
  elif [ "$days_left" -lt "$WARNING_DAYS" ]; then
    echo "🟡 WARNING: $domain expires in $days_left days"
  else
    echo "🟢 OK: $domain expires in $days_left days"
  fi
done
```

---

## 5. 证书透明度（Certificate Transparency）

### 5.1 什么是 CT？

CT 是一个公开的证书日志系统，所有公开信任的 CA 签发的证书都必须记录在 CT 日志中。

```
目的：
1. 检测恶意签发的证书（CA 被入侵）
2. 检测未授权的证书（域名所有者不知道）
3. 审计 CA 行为

工作流程：
1. CA 签发证书
2. CA 将证书提交到 CT 日志
3. CT 日志返回 SCT（Signed Certificate Timestamp）
4. 服务器在 TLS 握手中附带 SCT
5. 浏览器验证 SCT
```

### 5.2 查询 CT 日志

```bash
# 使用 crt.sh 查询某个域名的所有证书
curl -s "https://crt.sh/?q=myapp.com&output=json" | jq '.[].name_value' | sort -u

# 检查是否有未授权的证书
curl -s "https://crt.sh/?q=%.myapp.com&output=json" | \
  jq -r '.[] | "\(.issuer_name) | \(.name_value) | \(.not_before)"' | sort
```

---

## 6. 合规和审计

### 6.1 证书策略

```yaml
# 证书策略示例
policies:
  public_certificates:
    max_validity: 398 days        # Apple/Chrome 要求
    min_key_size: 2048 bits       # RSA
    allowed_algorithms: [RSA, ECDSA]
    must_use_ct: true             # 必须提交 CT 日志
    must_staple_ocsp: true        # 必须 OCSP Stapling
    
  internal_certificates:
    max_validity: 90 days         # 内部证书更短
    min_key_size: 2048 bits
    allowed_algorithms: [ECDSA P-256, Ed25519]
    must_use_ct: false
    auto_rotation: true           # 必须自动轮换
    
  mtls_certificates:
    max_validity: 24 hours        # mTLS 证书极短寿命
    min_key_size: 256 bits (ECC)
    allowed_algorithms: [ECDSA P-256]
    auto_rotation: true
    private_key_in_memory_only: true
```

### 6.2 审计检查清单

```yaml
audit_checklist:
  quarterly:
    - 检查所有证书的有效期
    - 验证证书链完整性
    - 检查是否有未授权的证书（CT 日志）
    - 审查 CA 签发记录
    - 验证私钥保护措施
    
  annual:
    - 审查 PKI 策略
    - 评估 CA 安全性
    - 更新信任列表
    - 灾难恢复演练
    - 合规报告
```

---

## 7. 知识总结

### 证书管理成熟度模型

```
Level 1 - 手动管理
  └── 手动申请、部署、续期证书
  └── 容易遗漏、出错

Level 2 - 半自动
  └── 使用 cert-manager 自动签发
  └── 仍然需要手动监控

Level 3 - 全自动
  └── cert-manager + 自动续期 + 监控告警
  └── 证书生命周期完全自动化

Level 4 - 零信任
  └── SPIRE + 短寿命证书 + 自动轮换
  └── 证书完全透明，无需管理
```

### 自检清单

- [ ] 我理解 PKI 三层架构的设计原因
- [ ] 我知道证书生命周期的每个阶段
- [ ] 我能配置 cert-manager 自动签发证书
- [ ] 我知道如何监控证书过期
- [ ] 我理解证书吊销的三种方式
- [ ] 我知道证书透明度的作用

---

**上一篇**：[mTLS 双向认证 ←](04-mtls.md) | **下一篇**：[GCP/GKE 证书实践 →](06-gcp-gke-practice.md)
