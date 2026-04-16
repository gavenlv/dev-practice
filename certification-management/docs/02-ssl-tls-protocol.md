# 02 — SSL/TLS 协议详解

> **难度**：⭐⭐ 进阶 | **阅读时间**：25 分钟 | **实践时间**：20 分钟

## 你将学到什么

- TLS 握手的完整过程（每一步在做什么）
- TLS 1.2 和 TLS 1.3 的区别（为什么 1.3 更快更安全）
- 密码套件是什么，怎么选
- 证书链验证的完整过程
- 常见攻击和防护

---

## 1. SSL vs TLS — 名字的故事

```
时间线：

1994  SSL 2.0   Netscape 发明，有严重漏洞
  │
1995  SSL 3.0   修复了一些问题，但仍有漏洞
  │
1999  TLS 1.0   标准化组织接手，改名 TLS（实质是 SSL 3.1）
  │               从此叫 TLS，但大家习惯还叫 SSL
2006  TLS 1.1   小改进
  │
2008  TLS 1.2   现代加密算法支持，目前最广泛使用
  │
2018  TLS 1.3   大幅简化，更快更安全
  │
2021  SSL 3.0 / TLS 1.0 / 1.1 正式废弃
```

**关键点**：SSL 已经完全淘汰，现在说的"SSL 证书"其实就是 TLS 证书。只是习惯上还叫 SSL。

---

## 2. TLS 的位置

```
┌─────────────────────────────────────────────┐
│              应用层 (HTTP)                   │
├─────────────────────────────────────────────┤
│              TLS 层                          │  ← TLS 在这里
├─────────────────────────────────────────────┤
│              TCP 层                          │
├─────────────────────────────────────────────┤
│              IP 层                           │
└─────────────────────────────────────────────┘

HTTP + TLS = HTTPS
SMTP + TLS = SMTPS
LDAP + TLS = LDAPS
```

TLS 是一个**独立的安全层**，可以给任何 TCP 协议加安全。

---

## 3. TLS 1.2 握手（完整版）

这是最经典的握手过程，理解了它，TLS 的核心就懂了。

### 3.1 全景图

```
客户端 (浏览器)                              服务器
    │                                          │
    │  ① ClientHello                           │
    │  ──────────────────────────────────────→ │
    │    支持的TLS版本、密码套件列表、           │
    │    随机数(ClientRandom)                   │
    │                                          │
    │  ② ServerHello                           │
    │  ←────────────────────────────────────── │
    │    选定的TLS版本、密码套件、               │
    │    随机数(ServerRandom)                   │
    │                                          │
    │  ③ Certificate                           │
    │  ←────────────────────────────────────── │
    │    服务器证书链                            │
    │                                          │
    │  ④ ServerKeyExchange (可选)              │
    │  ←────────────────────────────────────── │
    │    DH 参数（如果用 ECDHE）                │
    │                                          │
    │  ⑤ ServerHelloDone                       │
    │  ←────────────────────────────────────── │
    │                                          │
    │  ⑥ 验证证书                              │
    │  ── 检查证书链、有效期、域名 ──           │
    │                                          │
    │  ⑦ ClientKeyExchange                     │
    │  ──────────────────────────────────────→ │
    │    预主密钥(用服务器公钥加密)              │
    │    或 DH 公钥                             │
    │                                          │
    │  ⑧ 双方计算主密钥                         │
    │  ── ClientRandom + ServerRandom           │
    │     + PreMasterSecret → MasterSecret      │
    │                                          │
    │  ⑨ ChangeCipherSpec                      │
    │  ──────────────────────────────────────→ │
    │    "从现在开始我用对称密钥加密了"           │
    │                                          │
    │  ⑩ Finished                              │
    │  ──────────────────────────────────────→ │
    │    加密的握手验证消息                      │
    │                                          │
    │  ⑪ ChangeCipherSpec                      │
    │  ←────────────────────────────────────── │
    │    "我也开始用对称密钥加密了"              │
    │                                          │
    │  ⑫ Finished                              │
    │  ←────────────────────────────────────── │
    │    加密的握手验证消息                      │
    │                                          │
    │  ══════ 安全通道建立 ══════               │
    │                                          │
    │  ⑬ Application Data                      │
    │  ←─────────────────────────────────────→ │
    │    加密的 HTTP 请求/响应                   │
```

### 3.2 逐步详解

#### ① ClientHello — 客户端打招呼

```
客户端告诉服务器：
- 我支持 TLS 1.2 和 TLS 1.3
- 我支持这些密码套件：[TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256, ...]
- 这是我的随机数：ClientRandom（32字节）
- 我支持这些扩展：SNI, ALPN, ...
```

**SNI（Server Name Indication）** 很重要：告诉服务器你要访问哪个域名，这样服务器才能返回正确的证书（一个 IP 可能托管多个域名）。

#### ② ServerHello — 服务器回应

```
服务器告诉客户端：
- 我们用 TLS 1.2
- 我们用这个密码套件：TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
- 这是我的随机数：ServerRandom（32字节）
```

#### ③ Certificate — 服务器亮身份证

```
服务器发送证书链：
- 服务器证书（包含公钥和域名信息）
- 中间 CA 证书
- （根 CA 证书通常不发送，因为客户端已经有了）
```

#### ⑥ 验证证书 — 客户端查验身份证

```
客户端验证：
1. 证书是否在有效期内？
2. 证书的域名是否匹配？
3. 证书是否被吊销？（CRL/OCSP）
4. 证书链是否完整？
5. 根 CA 是否在信任列表中？
6. 签名是否有效？
```

#### ⑦⑧ 密钥交换 — 生成会话密钥

这是最关键的一步。有两种方式：

**方式一：RSA 密钥交换（传统，不推荐）**

```
客户端                                    服务器
  │                                         │
  │  生成随机预主密钥                        │
  │  用服务器公钥加密预主密钥                │
  │  ─────────────────────────────────────→ │
  │                                         │  用私钥解密得到预主密钥
  │                                         │
  │  双方用相同公式计算：                     │
  │  MasterSecret = PRF(PreMasterSecret,    │
  │    "master secret", ClientRandom +      │
  │    ServerRandom)                        │
```

问题：如果服务器私钥泄露，所有历史通信都可以被解密（没有前向保密）。

**方式二：ECDHE 密钥交换（推荐，有前向保密）**

```
客户端                                    服务器
  │                                         │
  │  生成临时私钥 a                         │  生成临时私钥 b
  │  计算公钥 A = g^a                       │  计算公钥 B = g^b
  │                                         │
  │  ─────────── A ──────────────────────→  │
  │  ←─────────── B ──────────────────────  │
  │                                         │
  │  计算共享密钥：S = B^a                  │  计算共享密钥：S = A^b
  │  （数学保证 B^a = A^b = g^(ab)）        │
  │                                         │
  │  双方得到相同的共享密钥，但没人能算出来    │
  │  即使长期私钥泄露，临时密钥已销毁，       │
  │  历史通信仍然安全 ✅                     │
```

### 3.3 实践：抓包看 TLS 握手

```bash
# 用 openssl 查看握手过程
openssl s_client -connect google.com:443 -tls1_2 -msg 2>&1 | head -80

# 输出中你会看到：
# >>> TLS 1.2 Handshake [length 0xxx], ClientHello
# <<< TLS 1.2 Handshake [length 0xxx], ServerHello
# <<< TLS 1.2 Handshake [length 0xxx], Certificate
# >>> TLS 1.2 Handshake [length 0xxx], ClientKeyExchange
# >>> TLS 1.2 ChangeCipherSpec [length 0001]
# >>> TLS 1.2 Handshake [length 0010], Finished
# <<< TLS 1.2 ChangeCipherSpec [length 0001]
# <<< TLS 1.2 Handshake [length 0010], Finished
```

---

## 4. TLS 1.3 握手（更快更安全）

TLS 1.3 做了大幅简化：**2-RTT → 1-RTT**，甚至可以 **0-RTT**。

### 4.1 对比

```
TLS 1.2（2-RTT）：
Client ── ClientHello ──────────────→ Server
Client ←── ServerHello + Cert ──────── Server
Client ── KeyExchange + Finished ──→ Server    ← 第1个RTT
Client ←── Finished ──────────────── Server    ← 第2个RTT
Client ── [加密数据] ──────────────→ Server    ← 终于可以发数据了

TLS 1.3（1-RTT）：
Client ── ClientHello + KeyShare ──→ Server    ← 客户端直接发送密钥材料
Client ←── ServerHello + KeyShare  ── Server    ← 服务器直接回应密钥材料
         + Cert + Finished
Client ── [加密数据] ──────────────→ Server    ← 就可以发数据了！
```

### 4.2 TLS 1.3 的关键改进

| 改进 | TLS 1.2 | TLS 1.3 |
|------|---------|---------|
| 握手延迟 | 2-RTT | 1-RTT（首次）/ 0-RTT（恢复） |
| 密码套件 | 很多，有些不安全 | 只有 5 个，全部安全 |
| 密钥交换 | RSA/ECDHE | 只用 ECDHE（强制前向保密） |
| 加密算法 | AES-CBC（有漏洞） | 只用 AEAD（AES-GCM/ChaCha20） |
| 压缩 | 支持（CRIME 攻击） | 不支持 |
| 协商重试 | 支持（降级攻击） | 不支持 |

### 4.3 TLS 1.3 的 5 个密码套件

```
TLS_AES_128_GCM_SHA256          ← 推荐，性能最好
TLS_AES_256_GCM_SHA384          ← 更安全，稍慢
TLS_CHACHA20_POLY1305_SHA256    ← 移动端推荐
TLS_AES_128_CCM_SHA256          ← IoT 设备
TLS_AES_128_CCM_8_SHA256        ← 极低带宽
```

注意 TLS 1.3 的密码套件命名和 1.2 不同——只指定了加密算法和哈希，因为密钥交换和认证方式是固定的（ECDHE + 证书签名）。

### 4.4 0-RTT（零往返恢复）

```
首次连接（1-RTT）：
Client ── ClientHello + KeyShare ──→ Server
Client ←── ServerHello + KeyShare ─── Server
         + Finished + NewSessionTicket
Client 保存 Session Ticket

恢复连接（0-RTT）：
Client ── ClientHello + KeyShare ──→ Server
         + EarlyData (加密的请求!)     ← 数据和握手一起发！
Client ←── ServerHello ────────────── Server
         + Finished + EarlyData响应
```

**0-RTT 的风险**：重放攻击。攻击者可以重放 0-RTT 数据。所以 0-RTT 只适合幂等请求。

---

## 5. 密码套件详解

### 5.1 TLS 1.2 密码套件命名

```
TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
 │     │    │       │       │     │
 │     │    │       │       │     └── 哈希算法（用于PRF和HMAC）
 │     │    │       │       └── 加密模式（GCM = AEAD）
 │     │    │       └── 加密算法 + 密钥长度
 │     │    └── 服务器证书签名算法
 │     └── 密钥交换算法（ECDHE = 前向保密）
 └── 协议标识
```

### 5.2 各组件安全性

| 组件 | ✅ 推荐 | ❌ 避免 | 原因 |
|------|---------|---------|------|
| 密钥交换 | ECDHE | RSA, DH | 前向保密 |
| 认证 | RSA, ECDSA | DSS | 安全性 |
| 加密 | AES-GCM, ChaCha20 | AES-CBC, RC4 | AEAD vs 有漏洞 |
| 哈希 | SHA-256, SHA-384 | MD5, SHA-1 | 已破解 |

### 5.3 推荐配置

**TLS 1.2 推荐密码套件（按优先级）：**

```
TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256
TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384
TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256
TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256
```

### 5.4 实践：测试密码套件

```bash
# 查看服务器支持的密码套件
nmap --script ssl-enum-ciphers -p 443 google.com

# 用 openssl 测试特定密码套件
openssl s_client -connect google.com:443 \
  -cipher 'ECDHE-RSA-AES128-GCM-SHA256'

# 列出 openssl 支持的所有密码套件
openssl ciphers -v | column -t
```

---

## 6. 证书链验证详解

### 6.1 完整验证流程

```
浏览器收到证书链：
┌────────────────────┐
│ 服务器证书 (leaf)   │ ← 包含域名和公钥
│ 签发者：中间 CA     │
├────────────────────┤
│ 中间 CA 证书        │ ← 包含中间 CA 的公钥
│ 签发者：根 CA       │
├────────────────────┤
│ 根 CA 证书          │ ← 浏览器内置，天然信任
└────────────────────┘

验证步骤：
1. 找到根 CA 证书在信任列表中 → ✅ 根 CA 可信
2. 用根 CA 公钥验证中间 CA 证书签名 → ✅ 中间 CA 可信
3. 用中间 CA 公钥验证服务器证书签名 → ✅ 服务器证书可信
4. 检查服务器证书的域名是否匹配 → ✅ 域名正确
5. 检查证书是否在有效期内 → ✅ 未过期
6. 检查证书是否被吊销 → ✅ 未吊销
```

### 6.2 证书吊销检查

| 方式 | 原理 | 优缺点 |
|------|------|--------|
| CRL | 下载吊销列表 | 列表可能很大，更新不及时 |
| OCSP | 实时查询吊销状态 | 隐私问题（CA 知道你访问了谁） |
| OCSP Stapling | 服务器附带 OCSP 响应 | 最佳方案 |

### 6.3 实践：验证证书链

```bash
# 下载证书链
echo | openssl s_client -connect google.com:443 -showcerts 2>/dev/null | \
  sed -n '/BEGIN CERT/,/END CERT/p' > chain.pem

# 分离证书
csplit -s -z -f cert_ chain.pem '/-----BEGIN CERTIFICATE-----/' '{*}'

# 验证证书链
for f in cert_*; do
  echo "=== $f ==="
  openssl x509 -in "$f" -noout -subject -issuer
done

# 验证完整链
openssl verify -CAfile /etc/ssl/certs/ca-certificates.crt chain.pem
```

---

## 7. 常见攻击与防护

### 7.1 攻击一览

| 攻击 | 目标 | 影响 | 防护 |
|------|------|------|------|
| **BEAST** | TLS 1.0 CBC | 解密数据 | 使用 TLS 1.2+ |
| **POODLE** | SSL 3.0 | 降级攻击 | 禁用 SSL 3.0 |
| **Heartbleed** | OpenSSL 漏洞 | 内存泄露 | 更新 OpenSSL |
| **CRIME** | TLS 压缩 | 会话劫持 | 禁用 TLS 压缩 |
| **Logjam** | DH 密钥交换 | 降级到弱 DH | 使用 ECDHE，≥2048位 |
| **SWEET32** | 3DES | 生日攻击 | 禁用 3DES |
| **ROBOT** | RSA PKCS#1 | 解密数据 | 禁用 RSA 密钥交换 |
| **降级攻击** | 协议协商 | 强制使用弱版本 | TLS 1.3 降级保护 |

### 7.2 降级攻击

```
攻击者拦截握手，假装双方都不支持高版本：

客户端：我支持 TLS 1.2, 1.1, 1.0
攻击者：→ 改为：我支持 TLS 1.0
服务器：好吧，用 TLS 1.0
攻击者：→ 利用 TLS 1.0 的漏洞

TLS 1.3 的防护：
- 删除了版本协商机制
- 服务器如果支持 1.3 但收到 1.2 ClientHello，
  会在 ServerHello 中放入降级检测值
- 客户端可以检测到被降级
```

### 7.3 实践：安全扫描

```bash
# 使用 testssl.sh 扫描（推荐工具）
# 安装：git clone https://github.com/drwetter/testssl.sh.git
cd testssl.sh
./testssl.sh https://google.com

# 使用 nmap 扫描
nmap --script ssl-heartbleed -p 443 target
nmap --script ssl-poodle -p 443 target

# 使用 openssl 检查
# 检查是否支持 SSLv3（不应该）
openssl s_client -connect target:443 -ssl3
# 如果连接成功 = ❌ 不安全

# 检查是否支持 TLS 1.0（不应该）
openssl s_client -connect target:443 -tls1
# 如果连接成功 = ⚠️ 不推荐
```

---

## 8. TLS 会话恢复

### 8.1 为什么需要会话恢复？

完整握手需要 2-RTT（TLS 1.2），对于短连接开销很大。会话恢复可以复用之前的协商结果。

### 8.2 两种机制

**Session ID**

```
首次连接：
Client ── ClientHello ──────────→ Server
Client ←── ServerHello + SessionID ─ Server
         （服务器保存会话状态）

恢复连接：
Client ── ClientHello + SessionID → Server
Client ←── ServerHello ──────────── Server    ← 1-RTT！
         （服务器找到保存的状态）
```

**Session Ticket**

```
首次连接：
Client ── ClientHello ──────────────→ Server
Client ←── ServerHello + NewSessionTicket ─ Server
         （服务器把状态加密后发给客户端保存）

恢复连接：
Client ── ClientHello + SessionTicket → Server
Client ←── ServerHello ──────────────── Server    ← 1-RTT！
         （服务器解密 Ticket 恢复状态）
```

Session Ticket 更好：服务器不需要保存状态（无状态），适合大规模部署。

---

## 9. ALPN 与 SNI

### 9.1 SNI（Server Name Indication）

```
没有 SNI 的问题：
一个 IP 地址托管多个网站（虚拟主机）
服务器不知道客户端要访问哪个网站
无法返回正确的证书

SNI 解决方案：
客户端在 ClientHello 中带上目标域名
服务器根据域名返回对应证书

ClientHello:
  ...
  SNI: api.myapp.com    ← 告诉服务器我要访问的域名
  ...
```

### 9.2 ALPN（Application-Layer Protocol Negotiation）

```
客户端在握手时告诉服务器想用的应用协议：

ClientHello:
  ...
  ALPN: h2, http/1.1    ← 我支持 HTTP/2 和 HTTP/1.1

ServerHello:
  ...
  ALPN: h2              ← 我们用 HTTP/2

好处：不需要额外的协商往返
```

### 9.3 加密 SNI（ESNI / ECH）

```
SNI 是明文的！ISP 可以看到你访问了哪个网站。

ECH (Encrypted Client Hello) 解决方案：
- 用公开密钥加密 SNI 和其他扩展
- 中间人只能看到 IP 地址，看不到域名

TLS 1.3 扩展，目前逐步部署中。
```

---

## 10. 知识总结

### TLS 1.2 vs 1.3 速查

| | TLS 1.2 | TLS 1.3 |
|---|---------|---------|
| 握手 | 2-RTT | 1-RTT / 0-RTT |
| 密码套件 | 37+ 个 | 5 个 |
| 前向保密 | 可选 | 强制 |
| RSA 密钥交换 | 支持 | 不支持 |
| CBC 模式 | 支持 | 不支持 |
| 压缩 | 支持 | 不支持 |
| 重协商 | 支持 | 不支持 |

### 自检清单

- [ ] 我能画出 TLS 1.2 握手的完整流程
- [ ] 我理解 ECDHE 为什么能提供前向保密
- [ ] 我知道 TLS 1.3 比 1.2 快在哪里
- [ ] 我能解读密码套件的每个部分
- [ ] 我理解证书链验证的完整过程
- [ ] 我知道常见的 TLS 攻击和防护方法

---

**上一篇**：[密码学与证书基础 ←](01-fundamentals.md) | **下一篇**：[HTTPS 实战 →](03-https.md)
