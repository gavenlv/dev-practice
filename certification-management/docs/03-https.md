# 03 — HTTPS 实战

> **难度**：⭐⭐ 进阶 | **阅读时间**：20 分钟 | **实践时间**：30 分钟

## 你将学到什么

- HTTPS 的完整工作原理
- 如何正确配置 HTTPS（Nginx、Go、Python）
- 如何调试 HTTPS 问题
- HTTPS 性能优化
- HSTS 和安全头

---

## 1. HTTPS 是什么？

```
HTTP（明文）：
浏览器 ──── 明文 HTTP ────→ 服务器
         任何人都能看到内容

HTTPS = HTTP + TLS：
浏览器 ──── TLS 握手 ────→ 服务器
       ──── 加密 HTTP ────→ 服务器
         只有双方能看到内容
```

### HTTPS 提供的保护

| 保护 | 没有 HTTPS | 有 HTTPS |
|------|-----------|----------|
| 偷看 | ❌ 明文传输 | ✅ 加密传输 |
| 篡改 | ❌ 可修改 | ✅ 完整性校验 |
| 冒充 | ❌ 可冒充 | ✅ 证书验证 |
| SEO | ❌ 降权 | ✅ 排名提升 |

---

## 2. HTTPS 完整流程

```
┌─────────────────────────────────────────────────────────────────┐
│                      HTTPS 完整流程                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. DNS 解析                                                    │
│     浏览器 → DNS 服务器：api.myapp.com 的 IP 是什么？            │
│     DNS 服务器 → 浏览器：1.2.3.4                               │
│                                                                 │
│  2. TCP 三次握手                                                │
│     浏览器 → 服务器：SYN                                        │
│     服务器 → 浏览器：SYN+ACK                                    │
│     浏览器 → 服务器：ACK                                        │
│                                                                 │
│  3. TLS 握手（上一章学的）                                       │
│     协商加密参数、验证证书、建立安全通道                          │
│                                                                 │
│  4. HTTP 请求/响应（加密传输）                                   │
│     浏览器 → 服务器：加密的 HTTP 请求                            │
│     服务器 → 浏览器：加密的 HTTP 响应                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. 配置 HTTPS

### 3.1 Nginx 配置

```nginx
# /etc/nginx/conf.d/myapp.conf

# HTTP → HTTPS 重定向
server {
    listen 80;
    server_name api.myapp.com;
    return 301 https://$server_name$request_uri;
}

# HTTPS 服务器
server {
    listen 443 ssl http2;
    server_name api.myapp.com;

    # ─── 证书配置 ───
    ssl_certificate     /etc/nginx/ssl/myapp.crt;
    ssl_certificate_key /etc/nginx/ssl/myapp.key;

    # ─── TLS 协议版本 ───
    ssl_protocols TLSv1.2 TLSv1.3;

    # ─── 密码套件 ───
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384';
    ssl_prefer_server_ciphers on;

    # ─── 会话恢复 ───
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    # ─── OCSP Stapling ───
    ssl_stapling on;
    ssl_stapling_verify on;
    resolver 8.8.8.8 8.8.4.4 valid=300s;
    resolver_timeout 5s;

    # ─── 安全头 ───
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;

    # ─── DH 参数（如果用 DHE）───
    # ssl_dhparam /etc/nginx/ssl/dhparam.pem;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### 3.2 Go HTTPS 服务器

```go
package main

import (
	"crypto/tls"
	"log"
	"net/http"
	"time"
)

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("Hello, HTTPS!"))
	})

	tlsConfig := &tls.Config{
		MinVersion: tls.VersionTLS12,
		CipherSuites: []uint16{
			tls.TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,
			tls.TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,
			tls.TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,
			tls.TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,
			tls.TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305,
			tls.TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305,
		},
		CurvePreferences: []tls.CurveID{
			tls.X25519,
			tls.CurveP256,
		},
		PreferServerCipherSuites: true,
		SessionTicketsDisabled:   false,
		SessionTimeout:           24 * time.Hour,
	}

	server := &http.Server{
		Addr:         ":443",
		Handler:      mux,
		TLSConfig:    tlsConfig,
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	log.Println("HTTPS server starting on :443")
	log.Fatal(server.ListenAndServeTLS("server.crt", "server.key"))
}
```

### 3.3 Python HTTPS 服务器

```python
import ssl
import http.server
import socketserver


class HTTPSHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-type", "text/html")
        self.send_header("Strict-Transport-Security", "max-age=63072000")
        self.end_headers()
        self.wfile.write(b"Hello, HTTPS!")


def create_https_server(port=4443):
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain("server.crt", "server.key")
    context.set_ciphers(
        "ECDHE+AESGCM:ECDHE+CHACHA20:!aNULL:!MD5:!DSS"
    )

    with socketserver.TCPServer(("", port), HTTPSHandler) as httpd:
        httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
        print(f"HTTPS server running on port {port}")
        httpd.serve_forever()


if __name__ == "__main__":
    create_https_server()
```

---

## 4. Let's Encrypt 自动化证书

### 4.1 使用 Certbot

```bash
# 安装 certbot
apt-get install certbot python3-certbot-nginx

# 获取证书（Nginx 插件，自动配置）
certbot --nginx -d api.myapp.com -d www.myapp.com

# 获取证书（standalone 模式，适合没有 web 服务器的场景）
certbot certonly --standalone -d api.myapp.com

# 获取证书（DNS 验证，适合内网/通配符证书）
certbot certonly --manual --preferred-challenges dns -d '*.myapp.com'

# 自动续期（certbot 已自动添加 cron）
certbot renew --dry-run

# 查看证书信息
certbot certificates
```

### 4.2 自动续期配置

```bash
# /etc/cron.d/certbot
0 */12 * * * root certbot renew --quiet --deploy-hook "systemctl reload nginx"
```

### 4.3 证书文件位置

```
/etc/letsencrypt/
├── live/
│   └── api.myapp.com/
│       ├── cert.pem        ← 服务器证书
│       ├── chain.pem       ← 中间 CA 证书
│       ├── fullchain.pem   ← 完整证书链（Nginx 用这个）
│       └── privkey.pem     ← 私钥
├── archive/                ← 历史版本
└── renewal/                ← 续期配置
```

---

## 5. 调试 HTTPS

### 5.1 常用调试命令

```bash
# 查看证书详情
echo | openssl s_client -connect api.myapp.com:443 2>/dev/null | \
  openssl x509 -noout -text

# 查看证书链
echo | openssl s_client -connect api.myapp.com:443 -showcerts 2>/dev/null

# 测试 TLS 版本
for version in ssl3 tls1 tls1_1 tls1_2 tls1_3; do
  echo -n "$version: "
  if echo | openssl s_client -connect api.myapp.com:443 -$version 2>/dev/null | grep -q "Protocol"; then
    echo "✅ Supported"
  else
    echo "❌ Not supported"
  fi
done

# 测试特定密码套件
openssl s_client -connect api.myapp.com:443 \
  -cipher 'ECDHE-RSA-AES128-GCM-SHA256' </dev/null

# 检查证书有效期
echo | openssl s_client -connect api.myapp.com:443 2>/dev/null | \
  openssl x509 -noout -enddate
# 输出：notAfter=Apr  8 07:59:59 2025 GMT

# 检查 OCSP
echo | openssl s_client -connect api.myapp.com:443 -status 2>/dev/null | \
  grep -A 2 "OCSP response"

# 检查 HSTS
curl -sI https://api.myapp.com | grep -i strict
```

### 5.2 在线工具

| 工具 | 网址 | 用途 |
|------|------|------|
| SSL Labs | ssllabs.com/ssltest/ | 全面评估 HTTPS 配置 |
| Censys | search.censys.io | 互联网扫描 |
| crt.sh | crt.sh | 证书透明度日志查询 |

### 5.3 常见错误排查

#### 证书域名不匹配

```
错误：NET::ERR_CERT_COMMON_NAME_INVALID

原因：证书的域名和访问的域名不一致
      证书是给 api.myapp.com 签的，但你访问的是 www.myapp.com

解决：
1. 检查证书的 CN 和 SAN
   openssl x509 -in cert.pem -noout -text | grep -A1 "Subject Alternative Name"
2. 确保证书包含所有需要的域名
3. 使用通配符证书 *.myapp.com
```

#### 证书过期

```
错误：NET::ERR_CERT_DATE_INVALID

原因：证书已过期或尚未生效

检查：
openssl x509 -in cert.pem -noout -dates
# notBefore=Jan 15 08:00:00 2024 GMT
# notAfter=Apr  8 07:59:59 2024 GMT

解决：续签证书
```

#### 证书链不完整

```
错误：NET::ERR_CERT_AUTHORITY_INVALID

原因：缺少中间 CA 证书

检查：
openssl s_client -connect api.myapp.com:443 2>/dev/null | grep "verify error"
# verify error:num=20:unable to get local issuer certificate

解决：
1. 下载中间 CA 证书
2. 合并证书链：cat server.crt intermediate.crt > fullchain.crt
3. Nginx 使用 ssl_certificate 指向 fullchain.crt
```

#### 混合内容

```
错误：Mixed Content（浏览器控制台警告）

原因：HTTPS 页面加载了 HTTP 资源

解决：
1. 所有资源使用 HTTPS
2. 使用相对协议 //example.com/resource.js
3. 设置 Content-Security-Policy: upgrade-insecure-requests
```

---

## 6. HTTPS 性能优化

### 6.1 性能开销分析

```
┌──────────────────────────────────────────────────────┐
│            HTTPS 性能开销                              │
├──────────────────────────────────────────────────────┤
│                                                      │
│  首次连接：                                           │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐           │
│  │ TCP 握手  │→│ TLS 握手  │→│ HTTP 请求 │           │
│  │  1-RTT   │  │  1-2 RTT │  │  1-RTT   │           │
│  └──────────┘  └──────────┘  └──────────┘           │
│                                                      │
│  恢复连接：                                           │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐           │
│  │ TCP 握手  │→│ TLS 恢复  │→│ HTTP 请求 │           │
│  │  1-RTT   │  │  0-1 RTT │  │  1-RTT   │           │
│  └──────────┘  └──────────┘  └──────────┘           │
│                                                      │
│  TLS 1.3 + TLS False Start:                          │
│  ┌──────────┐  ┌──────────────────────────┐          │
│  │ TCP 握手  │→│ TLS + HTTP 请求（合并）    │          │
│  │  1-RTT   │  │  1-RTT                   │          │
│  └──────────┘  └──────────────────────────┘          │
│                                                      │
└──────────────────────────────────────────────────────┘
```

### 6.2 优化措施

| 优化 | 效果 | 配置 |
|------|------|------|
| TLS 1.3 | 减少 1-RTT | `ssl_protocols TLSv1.3;` |
| Session Ticket | 恢复 0-RTT | `ssl_session_tickets on;` |
| OCSP Stapling | 减少客户端查询 | `ssl_stapling on;` |
| HTTP/2 | 多路复用 | `listen 443 ssl http2;` |
| 连接复用 | 避免 TCP 重建 | `keepalive_timeout 75s;` |
| ECC 证书 | 更小的密钥 | 使用 ECDSA 证书 |

### 6.3 Nginx 优化配置

```nginx
server {
    listen 443 ssl http2;

    # TLS 1.3 优先
    ssl_protocols TLSv1.3 TLSv1.2;

    # 会话缓存
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets on;

    # OCSP Stapling
    ssl_stapling on;
    ssl_stapling_verify on;

    # 连接复用
    keepalive_timeout 75s;

    # 0-RTT（TLS 1.3，谨慎使用）
    ssl_early_data on;

    # 代理连接复用
    location / {
        proxy_pass http://backend;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
    }
}
```

---

## 7. 安全头

### 7.1 HSTS（HTTP Strict Transport Security）

```
没有 HSTS：
1. 用户输入 myapp.com（没有 https://）
2. 浏览器访问 http://myapp.com
3. 服务器重定向到 https://myapp.com
4. ↑ 这一步是明文的！中间人可以拦截

有 HSTS：
1. 浏览器记住：myapp.com 必须用 HTTPS
2. 用户输入 myapp.com
3. 浏览器直接访问 https://myapp.com ← 没有明文环节
```

```nginx
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
```

| 参数 | 含义 |
|------|------|
| max-age=63072000 | 2 年内必须用 HTTPS |
| includeSubDomains | 所有子域名也必须用 HTTPS |
| preload | 允许加入浏览器内置 HSTS 列表 |

### 7.2 其他安全头

```nginx
# 禁止被 iframe 嵌入（防点击劫持）
add_header X-Frame-Options DENY always;

# 禁止 MIME 嗅探
add_header X-Content-Type-Options nosniff always;

# CSP（内容安全策略）
add_header Content-Security-Policy "default-src 'self'; script-src 'self'" always;

# 推荐人策略
add_header Referrer-Policy strict-origin-when-cross-origin always;

# 权限策略
add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;
```

---

## 8. 实践：搭建完整 HTTPS 环境

### 8.1 一键生成自签名证书（开发用）

```bash
#!/bin/bash
# 生成开发用自签名证书

DOMAIN="myapp.local"

# 生成私钥
openssl genrsa -out ${DOMAIN}.key 2048

# 生成证书（含 SAN）
cat > ${DOMAIN}.ext << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${DOMAIN}
DNS.2 = *.${DOMAIN}
IP.1 = 127.0.0.1
EOF

openssl req -new -key ${DOMAIN}.key -out ${DOMAIN}.csr \
  -subj "/C=CN/ST=Shanghai/L=Shanghai/O=Dev/CN=${DOMAIN}"

openssl x509 -req -in ${DOMAIN}.csr -signkey ${DOMAIN}.key \
  -out ${DOMAIN}.crt -days 365 -sha256 -extfile ${DOMAIN}.ext

echo "✅ Certificate generated:"
echo "   Key:  ${DOMAIN}.key"
echo "   Cert: ${DOMAIN}.crt"
```

### 8.2 测试 HTTPS 配置

```bash
# 使用 SSL Labs API 测试
curl -s "https://api.ssllabs.com/api/v3/analyze?host=api.myapp.com" | jq

# 本地快速测试
./scripts/check-tls-endpoint.sh api.myapp.com 443
```

---

## 9. 知识总结

### HTTPS 配置检查清单

- [ ] TLS 版本：只启用 TLS 1.2 和 1.3
- [ ] 密码套件：只使用 AEAD 密码套件
- [ ] 证书：来自可信 CA，域名匹配
- [ ] 证书链：包含完整中间 CA
- [ ] HSTS：已启用
- [ ] OCSP Stapling：已启用
- [ ] HTTP→HTTPS：自动重定向
- [ ] 混合内容：无
- [ ] 证书续期：自动化

---

**上一篇**：[SSL/TLS 协议详解 ←](02-ssl-tls-protocol.md) | **下一篇**：[mTLS 双向认证 →](04-mtls.md)
