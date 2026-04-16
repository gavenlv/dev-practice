# 01 — 密码学与证书基础

> **难度**：⭐ 入门 | **阅读时间**：20 分钟 | **实践时间**：15 分钟

## 你将学到什么

读完这篇，你会明白：
- 为什么需要加密？加密解决什么问题？
- 对称加密和非对称加密有什么区别？
- 什么是哈希？什么是数字签名？
- 证书到底是什么？为什么需要 CA？

---

## 1. 为什么需要加密？

### 一个日常场景

想象你给朋友寄一封信：

```
你 ──── 信件 ────> 邮递员 ──── 信件 ────> 朋友
```

问题来了：
1. **偷看**：邮递员可以拆开信看内容 → ❌ 不保密
2. **篡改**：邮递员可以改写内容 → ❌ 不完整
3. **冒充**：别人可以假装你写信 → ❌ 不可信

网络通信也是一样——数据经过无数路由器，任何中间人都可以偷看、篡改、冒充。

**加密就是解决这三个问题**：
- **保密性**（Confidentiality）：只有目标对象能看懂
- **完整性**（Integrity）：内容没被篡改
- **身份认证**（Authentication）：确认对方身份

---

## 2. 对称加密

### 生活中的类比

你和朋友有一把**相同的钥匙**，锁箱子用这把钥匙，开箱子也用这把钥匙。

```
加密：明文 + 密钥 → 密文
解密：密文 + 密钥 → 明文

     密钥 (相同)
你 ────────────── 朋友
     │               │
  加密箱 ────────→ 解密箱
```

### 常见算法

| 算法 | 密钥长度 | 状态 | 说明 |
|------|----------|------|------|
| DES | 56 位 | ❌ 已废弃 | 太短，可暴力破解 |
| 3DES | 168 位 | ⚠️ 淘汰中 | 三次 DES，性能差 |
| AES-128 | 128 位 | ✅ 安全 | 性能好 |
| AES-256 | 256 位 | ✅ 最安全 | 推荐使用 |
| ChaCha20 | 256 位 | ✅ 安全 | 移动端性能好 |

### 实践：用 OpenSSL 体验对称加密

```bash
# 加密文件
echo "Hello, this is a secret message!" > plaintext.txt
openssl enc -aes-256-cbc -salt -pbkdf2 -in plaintext.txt -out encrypted.bin
# 输入密码：mypassword

# 解密文件
openssl enc -aes-256-cbc -d -pbkdf2 -in encrypted.bin -out decrypted.txt
# 输入密码：mypassword

# 验证
cat decrypted.txt
# 输出：Hello, this is a secret message!
```

### 对称加密的问题

**密钥怎么给对方？**

```
你 ──── 密钥 ────> 邮递员 ──── 密钥 ────> 朋友
                     ↑
               邮递员拿到了密钥！
               之后所有加密对他都无效了
```

这就是**密钥分发问题**——怎么安全地把密钥给对方？  
非对称加密解决了这个问题。

---

## 3. 非对称加密

### 生活中的类比

想象一个**带投信口的箱子**：
- 投信口是公开的（公钥），任何人都可以把信投进去
- 箱子的钥匙只有你持有（私钥），只有你能打开读信

```
公钥（公开）    私钥（保密）
┌──────────┐    ┌──────────┐
│ 投信口    │    │ 开箱钥匙 │
│ 任何人可投│    │ 只有你有  │
└──────────┘    └──────────┘

加密：明文 + 公钥 → 密文    （任何人都能加密）
解密：密文 + 私钥 → 明文    （只有私钥持有者能解密）
```

### 关键规则

```
公钥加密 → 私钥解密    （加密通信）
私钥签名 → 公钥验证    （数字签名）
```

### 常见算法

| 算法 | 密钥长度 | 状态 | 说明 |
|------|----------|------|------|
| RSA-2048 | 2048 位 | ✅ 安全 | 最广泛使用 |
| RSA-4096 | 4096 位 | ✅ 最安全 | 更安全但更慢 |
| ECDSA P-256 | 256 位 | ✅ 安全 | 更短密钥，同等安全 |
| Ed25519 | 256 位 | ✅ 推荐 | 最快最安全 |

### 实践：生成密钥对

```bash
# 生成 RSA 私钥
openssl genrsa -out private.key 2048

# 从私钥提取公钥
openssl rsa -in private.key -pubout -out public.key

# 查看私钥内容
cat private.key
# -----BEGIN RSA PRIVATE KEY-----
# ...（一堆乱码，这就是私钥）
# -----END RSA PRIVATE KEY-----

# 查看公钥内容
cat public.key
# -----BEGIN PUBLIC KEY-----
# ...（另一堆乱码，这就是公钥）
# -----END PUBLIC KEY-----
```

### 实践：用公钥加密、私钥解密

```bash
# 用公钥加密
echo "Top secret message" > message.txt
openssl rsautl -encrypt -pubin -inkey public.key -in message.txt -out message.encrypted

# 用私钥解密
openssl rsautl -decrypt -inkey private.key -in message.encrypted -out message.decrypted

# 验证
cat message.decrypted
# 输出：Top secret message
```

### 非对称加密的问题

**慢！** 比对称加密慢 100-1000 倍。

所以实际使用中，**两种加密结合**：
1. 用非对称加密安全地交换一个临时密钥
2. 用这个临时密钥做对称加密传输数据

**这就是 TLS 的核心思路！**

---

## 4. 哈希（Hash）

### 生活中的类比

哈希就像**指纹**：
- 每个人的指纹唯一
- 不能从指纹还原出人
- 同一个人的指纹永远一样

```
任意数据 ──→ 哈希函数 ──→ 固定长度的摘要

"Hello"     → SHA-256 → 185f8db32271fe25f561a6fc938b2e264306ec304eda518007d1764826381969
"Hello!"    → SHA-256 → 334d016f755cd6dc58c53a86e183882f8ec14f52fb05345887c8a5edd42c87b7
                                    ↑
                            只多了一个感叹号，结果完全不同
```

### 哈希的特性

| 特性 | 说明 |
|------|------|
| 单向性 | 无法从哈希值还原原始数据 |
| 唯一性 | 不同的数据几乎不可能产生相同的哈希 |
| 固定长度 | 无论输入多长，输出长度固定 |
| 雪崩效应 | 输入微小变化，输出完全不同 |

### 常见算法

| 算法 | 输出长度 | 状态 | 说明 |
|------|----------|------|------|
| MD5 | 128 位 | ❌ 已破解 | 可碰撞 |
| SHA-1 | 160 位 | ❌ 已破解 | 可碰撞 |
| SHA-256 | 256 位 | ✅ 安全 | TLS 1.2/1.3 使用 |
| SHA-384 | 384 位 | ✅ 安全 | 更安全 |
| BLAKE2b | 256/512 位 | ✅ 推荐 | 更快 |

### 实践：计算哈希

```bash
# 计算文件的 SHA-256 哈希
echo "Hello" > test.txt
sha256sum test.txt
# 185f8db32271fe25f561a6fc938b2e264306ec304eda518007d1764826381969  test.txt

# 修改一个字符
echo "Hello!" > test.txt
sha256sum test.txt
# 334d016f755cd6dc58c53a86e183882f8ec14f52fb05345887c8a5edd42c87b7  test.txt
# 完全不同！

# 用 OpenSSL 计算
openssl dgst -sha256 test.txt
```

### 哈希的用途

1. **验证完整性**：下载文件后比对哈希，确认没被篡改
2. **存储密码**：数据库存密码的哈希，不是明文
3. **数字签名**：对哈希签名，而不是对整个数据签名（更快）

---

## 5. 数字签名

### 生活中的类比

签名就像**公章**：
- 盖了章的文件，证明是某个组织发出的
- 别人无法伪造你的章
- 任何人都可以验证章的真伪

```
签名过程：
数据 → 哈希 → 用私钥加密哈希 → 签名

验证过程：
数据 → 哈希 → 用公钥解密签名 → 比对两个哈希
```

### 完整流程

```
发送方：                                    接收方：
┌────────────────────┐                  ┌────────────────────┐
│ 1. 对数据计算哈希   │                  │ 4. 对数据计算哈希   │
│ 2. 用私钥加密哈希   │ ─── 数据+签名 ──→│ 5. 用公钥解密签名   │
│ 3. 发送数据+签名   │                  │ 6. 比对两个哈希     │
└────────────────────┘                  └────────────────────┘
                                              │
                                         哈希一致？
                                         ✅ 数据完整且来源可信
                                         ❌ 数据被篡改或来源不可信
```

### 实践：数字签名

```bash
# 1. 准备文件
echo "Important document content" > document.txt

# 2. 用私钥签名
openssl dgst -sha256 -sign private.key -out document.sig document.txt

# 3. 用公钥验证
openssl dgst -sha256 -verify public.key -signature document.sig document.txt
# 输出：Verified OK

# 4. 篡改文件后再验证
echo "Tampered content" > document.txt
openssl dgst -sha256 -verify public.key -signature document.sig document.txt
# 输出：Verification Failure
```

---

## 6. 数字证书

### 为什么需要证书？

非对称加密有一个致命问题：

```
你 ──── 公钥 ────> 邮递员 ──── 邮递员的公钥 ────> 朋友
                     ↑
              邮递员把你的公钥
              替换成了自己的公钥！
              这就是"中间人攻击"
```

**问题**：你怎么确认收到的公钥真的是对方的？

**答案**：证书！证书 = 公钥 + 身份信息 + 权威机构签名

### 证书是什么？

把证书想象成**身份证**：

```
┌─────────────────────────────────────────┐
│            数字证书 (X.509)              │
├─────────────────────────────────────────┤
│                                         │
│  持有者信息：                            │
│    姓名/域名：api.myapp.com             │
│    组织：MyApp Inc.                     │
│    国家：CN                             │
│                                         │
│  公钥：                                 │
│    MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A... │
│                                         │
│  签发者：                                │
│    DigiCert Global Root CA              │
│                                         │
│  有效期：                                │
│    2024-01-01 至 2025-01-01             │
│                                         │
│  签名：                                 │
│    CA 用私钥对本证书的哈希签名            │
│    3045022100f3e4d5...                  │
│                                         │
└─────────────────────────────────────────┘
```

### 证书链

证书不是凭空信任的，它有一条**信任链**：

```
根 CA 证书（预装在浏览器/操作系统中，天然信任）
  │
  │ 签名
  ▼
中间 CA 证书（根 CA 签发）
  │
  │ 签名
  ▼
服务器证书（中间 CA 签发）
```

就像：
- **根 CA** = 公安部（最高权威）
- **中间 CA** = 地方公安局（根 CA 授权）
- **服务器证书** = 你的身份证（地方公安局签发）

验证过程：
1. 浏览器收到服务器证书
2. 用中间 CA 的公钥验证服务器证书的签名 → ✅
3. 用根 CA 的公钥验证中间 CA 证书的签名 → ✅
4. 根 CA 证书在浏览器信任列表中 → ✅
5. 信任建立！

### 实践：查看证书

```bash
# 查看网站的完整证书链
echo | openssl s_client -connect google.com:443 -showcerts 2>/dev/null | \
  awk '/BEGIN CERT/,/END CERT/' | while read line; do echo "$line"; done

# 查看证书详细信息
echo | openssl s_client -connect google.com:443 2>/dev/null | \
  openssl x509 -noout -text

# 只看关键信息
echo | openssl s_client -connect google.com:443 2>/dev/null | \
  openssl x509 -noout -subject -issuer -dates
# 输出类似：
# subject=CN = *.google.com
# issuer=C = US, O = Google Trust Services LLC, CN = GTS CA 1C3
# notBefore=Jan 15 08:00:00 2024 GMT
# notAfter=Apr  8 07:59:59 2024 GMT
```

---

## 7. CA（证书颁发机构）

### CA 的角色

```
┌──────────────────────────────────────────────────┐
│                   CA 的角色                       │
├──────────────────────────────────────────────────┤
│                                                  │
│  1. 验证申请者身份                                │
│     - 域名验证（DV）：证明你控制这个域名           │
│     - 组织验证（OV）：验证组织身份                 │
│     - 扩展验证（EV）：最严格的身份验证             │
│                                                  │
│  2. 签发证书                                      │
│     - 用 CA 私钥对证书签名                        │
│                                                  │
│  3. 维护证书状态                                  │
│     - 吊销证书（CRL/OCSP）                       │
│     - 记录审计日志                                │
│                                                  │
└──────────────────────────────────────────────────┘
```

### 证书类型

| 类型 | 验证级别 | 适用场景 | 价格 |
|------|----------|----------|------|
| DV | 域名验证 | 个人网站、测试 | 免费（Let's Encrypt） |
| OV | 组织验证 | 企业网站 | 付费 |
| EV | 扩展验证 | 银行、金融 | 昂贵 |
| 自签名 | 无验证 | 本地开发 | 免费 |

### 公共 CA vs 私有 CA

| | 公共 CA | 私有 CA |
|---|---------|---------|
| 信任范围 | 全球（浏览器信任） | 组织内部 |
| 示例 | Let's Encrypt, DigiCert | 自建 CA, HashiCorp Vault |
| 费用 | 免费/付费 | 自建免费 |
| 适用 | 公网服务 | 内部服务、mTLS |

---

## 8. 证书格式

### 常见格式

| 格式 | 扩展名 | 编码 | 说明 |
|------|--------|------|------|
| PEM | .pem, .crt, .key | Base64 | 最常见，文本格式 |
| DER | .der, .cer | 二进制 | Windows 常用 |
| PKCS#7 | .p7b, .p7c | Base64/二进制 | 证书链 |
| PKCS#12 | .p12, .pfx | 二进制 | 含私钥+证书，有密码保护 |

### 实践：格式转换

```bash
# PEM → DER
openssl x509 -in cert.pem -outform DER -out cert.der

# DER → PEM
openssl x509 -in cert.der -inform DER -outform PEM -out cert.pem

# PEM → PKCS#12（含私钥）
openssl pkcs12 -export -out cert.pfx -inkey private.key -in cert.pem

# PKCS#12 → PEM（提取证书）
openssl pkcs12 -in cert.pfx -clcerts -nokeys -out cert.pem

# PKCS#12 → PEM（提取私钥）
openssl pkcs12 -in cert.pfx -nocerts -out private.key
```

---

## 9. 证书签名请求（CSR）

### 什么是 CSR？

CSR 就像**身份证申请表**——你填好信息，交给 CA 去签发证书。

```
┌─────────────────────────────────────┐
│         CSR (Certificate Signing    │
│              Request)               │
├─────────────────────────────────────┤
│  你的公钥                           │
│  你的身份信息（域名、组织等）        │
│  你的签名（证明你持有对应私钥）      │
└─────────────────────────────────────┘
          │
          ▼ 交给 CA
┌─────────────────────────────────────┐
│         CA 验证身份后                │
│         用 CA 私钥签名               │
│         生成正式证书                  │
└─────────────────────────────────────┘
```

### 实践：生成 CSR 并签发证书

```bash
# 步骤 1：生成私钥
openssl genrsa -out myapp.key 2048

# 步骤 2：生成 CSR
openssl req -new -key myapp.key -out myapp.csr \
  -subj "/C=CN/ST=Shanghai/L=Shanghai/O=MyApp/CN=myapp.local"

# 步骤 3：查看 CSR 内容
openssl req -in myapp.csr -text -noout

# 步骤 4：用 CA 签发证书（或自签名）
openssl x509 -req -in myapp.csr -signkey myapp.key -out myapp.crt -days 365

# 步骤 5：验证证书
openssl x509 -in myapp.crt -text -noout
```

---

## 10. 知识总结

### 三大加密技术各司其职

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  对称加密（AES/ChaCha20）                                   │
│  └── 解决：数据保密传输（快速）                              │
│                                                             │
│  非对称加密（RSA/ECC）                                      │
│  └── 解决：密钥交换 + 身份认证                              │
│                                                             │
│  哈希（SHA-256）                                            │
│  └── 解决：数据完整性验证                                    │
│                                                             │
│  数字签名 = 非对称加密 + 哈希                               │
│  └── 解决：身份认证 + 完整性                                │
│                                                             │
│  数字证书 = 公钥 + 身份 + CA签名                            │
│  └── 解决：公钥的信任问题                                    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### TLS 使用的完整组合

```
TLS = 非对称加密（握手阶段交换密钥）
    + 对称加密（数据传输阶段加密数据）
    + 哈希（验证完整性）
    + 数字签名（验证身份）
    + 证书（建立信任链）
```

### 自检清单

- [ ] 我能解释对称加密和非对称加密的区别
- [ ] 我知道为什么两种加密要结合使用
- [ ] 我理解哈希的特性和用途
- [ ] 我能解释数字签名的原理
- [ ] 我知道证书解决了什么问题
- [ ] 我理解证书链的验证过程
- [ ] 我能用 OpenSSL 生成密钥和证书

---

**下一篇**：[SSL/TLS 协议详解 →](02-ssl-tls-protocol.md)
