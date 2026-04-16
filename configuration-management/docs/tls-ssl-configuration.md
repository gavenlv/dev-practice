# TLS/SSL 安全连接配置实践

## 概述

本文档详细说明如何在 GCP 环境中配置 TLS/SSL 安全连接，确保所有服务间通信和数据传输的安全性。

## TLS 连接架构

```
┌─────────────────────────────────────────────────────────────────────┐
│                        TLS 连接架构                                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌──────────┐     TLS 1.3      ┌──────────────┐                    │
│  │  Client  │ ◄──────────────► │  GKE Ingress │                    │
│  └──────────┘                  └──────┬───────┘                    │
│                                       │                             │
│                                       │ mTLS                        │
│                                       ▼                             │
│                          ┌────────────────────┐                    │
│                          │   GKE Cluster      │                    │
│                          │  ┌──────────────┐  │                    │
│                          │  │   Service A  │  │                    │
│                          │  └──────┬───────┘  │                    │
│                          │         │ TLS      │                    │
│                          │         ▼          │                    │
│                          │  ┌──────────────┐  │                    │
│                          │  │  Cloud SQL   │  │                    │
│                          │  └──────────────┘  │                    │
│                          └────────────────────┘                    │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                    GCP 服务 TLS 连接                          │  │
│  │  ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────────┐  │  │
│  │  │CloudSQL │   │ PubSub  │   │  GCS    │   │  Memorystore│  │  │
│  │  │  TLS    │   │  TLS    │   │  TLS    │   │    TLS      │  │  │
│  │  └─────────┘   └─────────┘   └─────────┘   └─────────────┘  │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## 证书管理

### 证书类型

| 类型 | 用途 | 管理方式 |
|------|------|----------|
| Google Managed | 公网域名 | GKE Managed Certificate |
| Self-signed | 内部服务 | cert-manager |
| CA Signed | 企业内部 | Private CA |

### Google Managed Certificates

```yaml
# kubernetes/overlays/prod/managed-certificate.yaml
apiVersion: networking.gke.io/v1
kind: ManagedCertificate
metadata:
  name: myapp-cert
  namespace: myapp
spec:
  domains:
    - api.myapp.com
    - app.myapp.com
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-ingress
  namespace: myapp
  annotations:
    networking.gke.io/managed-certificates: "myapp-cert"
    kubernetes.io/ingress.global-static-ip-name: "myapp-ip"
spec:
  rules:
    - host: api.myapp.com
      http:
        paths:
          - path: /*
            pathType: ImplementationSpecific
            backend:
              service:
                name: myapp-service
                port:
                  number: 8080
```

### cert-manager 配置

```yaml
# kubernetes/base/cert-manager.yaml
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
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: myapp-tls
  namespace: myapp
spec:
  secretName: myapp-tls-secret
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - api.myapp.com
    - app.myapp.com
```

## Cloud SQL TLS 连接

### 连接配置

```yaml
# Cloud SQL 连接配置
database:
  host: /cloudsql/myapp-prod:asia-east1:myapp-db
  port: 5432
  name: myapp
  user: myapp_user
  ssl_mode: require
```

### Go 连接示例

```go
package database

import (
    "context"
    "crypto/tls"
    "crypto/x509"
    "database/sql"
    "fmt"
    "io/ioutil"

    _ "github.com/lib/pq"
)

type DatabaseConfig struct {
    Host         string
    Port         int
    Name         string
    User         string
    Password     string
    SSLMode      string
    SSLCert      string
    SSLKey       string
    SSLRootCert  string
}

func NewConnection(cfg *DatabaseConfig) (*sql.DB, error) {
    dsn := fmt.Sprintf(
        "host=%s port=%d user=%s password=%s dbname=%s sslmode=%s",
        cfg.Host, cfg.Port, cfg.User, cfg.Password, cfg.Name, cfg.SSLMode,
    )
    
    if cfg.SSLMode == "verify-ca" || cfg.SSLMode == "verify-full" {
        dsn += fmt.Sprintf(" sslcert=%s sslkey=%s sslrootcert=%s",
            cfg.SSLCert, cfg.SSLKey, cfg.SSLRootCert)
    }
    
    db, err := sql.Open("postgres", dsn)
    if err != nil {
        return nil, fmt.Errorf("failed to open database: %w", err)
    }
    
    if err := db.Ping(); err != nil {
        return nil, fmt.Errorf("failed to ping database: %w", err)
    }
    
    return db, nil
}

func NewConnectionWithTLS(cfg *DatabaseConfig, certPEM, keyPEM, caPEM []byte) (*sql.DB, error) {
    tlsConfig := &tls.Config{
        InsecureSkipVerify: false,
        MinVersion:         tls.VersionTLS12,
    }
    
    if caPEM != nil {
        caCertPool := x509.NewCertPool()
        if !caCertPool.AppendCertsFromPEM(caPEM) {
            return nil, fmt.Errorf("failed to parse CA certificate")
        }
        tlsConfig.RootCAs = caCertPool
    }
    
    if certPEM != nil && keyPEM != nil {
        cert, err := tls.X509KeyPair(certPEM, keyPEM)
        if err != nil {
            return nil, fmt.Errorf("failed to parse client certificate: %w", err)
        }
        tlsConfig.Certificates = []tls.Certificate{cert}
    }
    
    return NewConnection(cfg)
}
```

### Python 连接示例

```python
import ssl
import psycopg2
from typing import Optional


class DatabaseConnection:
    def __init__(
        self,
        host: str,
        port: int,
        database: str,
        user: str,
        password: str,
        ssl_mode: str = "require",
        ssl_cert: Optional[str] = None,
        ssl_key: Optional[str] = None,
        ssl_root_cert: Optional[str] = None,
    ):
        self.config = {
            "host": host,
            "port": port,
            "database": database,
            "user": user,
            "password": password,
            "sslmode": ssl_mode,
        }
        
        if ssl_cert:
            self.config["sslcert"] = ssl_cert
        if ssl_key:
            self.config["sslkey"] = ssl_key
        if ssl_root_cert:
            self.config["sslrootcert"] = ssl_root_cert
    
    def connect(self):
        return psycopg2.connect(**self.config)
    
    def test_connection(self) -> bool:
        try:
            with self.connect() as conn:
                with conn.cursor() as cur:
                    cur.execute("SELECT 1")
                    return True
        except Exception as e:
            print(f"Connection test failed: {e}")
            return False


def create_tls_connection(
    host: str,
    port: int,
    database: str,
    user: str,
    password: str,
    ca_cert_path: str,
    client_cert_path: Optional[str] = None,
    client_key_path: Optional[str] = None,
):
    ssl_context = ssl.create_default_context(
        ssl.Purpose.SERVER_AUTH,
        cafile=ca_cert_path,
    )
    ssl_context.minimum_version = ssl.TLSVersion.TLSv1_2
    
    if client_cert_path and client_key_path:
        ssl_context.load_cert_chain(
            certfile=client_cert_path,
            keyfile=client_key_path,
        )
    
    return psycopg2.connect(
        host=host,
        port=port,
        database=database,
        user=user,
        password=password,
        sslmode="verify-full",
        sslcontext=ssl_context,
    )
```

### Node.js 连接示例

```javascript
const { Pool } = require('pg');
const fs = require('fs');
const tls = require('tls');

class DatabaseConnection {
    constructor(config) {
        this.config = {
            host: config.host,
            port: config.port,
            database: config.database,
            user: config.user,
            password: config.password,
            ssl: this.createSSLConfig(config),
        };
        this.pool = null;
    }
    
    createSSLConfig(config) {
        if (config.sslMode === 'disable') {
            return false;
        }
        
        const sslConfig = {
            rejectUnauthorized: config.sslMode === 'verify-full',
            minVersion: tls.constants.TLS1_2_VERSION,
        };
        
        if (config.sslRootCert) {
            sslConfig.ca = fs.readFileSync(config.sslRootCert).toString();
        }
        
        if (config.sslCert && config.sslKey) {
            sslConfig.cert = fs.readFileSync(config.sslCert).toString();
            sslConfig.key = fs.readFileSync(config.sslKey).toString();
        }
        
        return sslConfig;
    }
    
    getPool() {
        if (!this.pool) {
            this.pool = new Pool(this.config);
        }
        return this.pool;
    }
    
    async testConnection() {
        try {
            const client = await this.getPool().connect();
            await client.query('SELECT 1');
            client.release();
            return true;
        } catch (error) {
            console.error('Connection test failed:', error);
            return false;
        }
    }
}

module.exports = { DatabaseConnection };
```

## Cloud PubSub TLS 连接

### 配置

```go
package pubsub

import (
    "context"
    "crypto/tls"
    "crypto/x509"
    "fmt"
    "io/ioutil"
    
    "cloud.google.com/go/pubsub"
    "google.golang.org/api/option"
    "google.golang.org/grpc"
    "google.golang.org/grpc/credentials"
)

type PubSubConfig struct {
    ProjectID   string
    Endpoint    string
    TLSCertPath string
}

func NewClient(ctx context.Context, cfg *PubSubConfig) (*pubsub.Client, error) {
    opts := []option.ClientOption{}
    
    if cfg.Endpoint != "" {
        opts = append(opts, option.WithEndpoint(cfg.Endpoint))
    }
    
    if cfg.TLSCertPath != "" {
        tlsConfig, err := createTLSConfig(cfg.TLSCertPath)
        if err != nil {
            return nil, fmt.Errorf("failed to create TLS config: %w", err)
        }
        
        opts = append(opts, 
            option.WithGRPCDialOption(
                grpc.WithTransportCredentials(
                    credentials.NewTLS(tlsConfig),
                ),
            ),
        )
    }
    
    client, err := pubsub.NewClient(ctx, cfg.ProjectID, opts...)
    if err != nil {
        return nil, fmt.Errorf("failed to create pubsub client: %w", err)
    }
    
    return client, nil
}

func createTLSConfig(certPath string) (*tls.Config, error) {
    certPEM, err := ioutil.ReadFile(certPath)
    if err != nil {
        return nil, fmt.Errorf("failed to read cert file: %w", err)
    }
    
    certPool := x509.NewCertPool()
    if !certPool.AppendCertsFromPEM(certPEM) {
        return nil, fmt.Errorf("failed to parse certificate")
    }
    
    return &tls.Config{
        RootCAs:    certPool,
        MinVersion: tls.VersionTLS12,
    }, nil
}
```

## Redis (Memorystore) TLS 连接

### Go Redis 连接

```go
package redis

import (
    "crypto/tls"
    "crypto/x509"
    "fmt"
    "io/ioutil"
    
    "github.com/go-redis/redis/v8"
)

type RedisConfig struct {
    Host     string
    Port     int
    Password string
    DB       int
    TLS      *TLSConfig
}

type TLSConfig struct {
    Enabled    bool
    CertPath   string
    KeyPath    string
    CACertPath string
    SkipVerify bool
}

func NewClient(cfg *RedisConfig) (*redis.Client, error) {
    options := &redis.Options{
        Addr:     fmt.Sprintf("%s:%d", cfg.Host, cfg.Port),
        Password: cfg.Password,
        DB:       cfg.DB,
    }
    
    if cfg.TLS != nil && cfg.TLS.Enabled {
        tlsConfig, err := createRedisTLSConfig(cfg.TLS)
        if err != nil {
            return nil, fmt.Errorf("failed to create TLS config: %w", err)
        }
        options.TLSConfig = tlsConfig
    }
    
    return redis.NewClient(options), nil
}

func createRedisTLSConfig(cfg *TLSConfig) (*tls.Config, error) {
    tlsConfig := &tls.Config{
        MinVersion:         tls.VersionTLS12,
        InsecureSkipVerify: cfg.SkipVerify,
    }
    
    if cfg.CACertPath != "" {
        caCert, err := ioutil.ReadFile(cfg.CACertPath)
        if err != nil {
            return nil, fmt.Errorf("failed to read CA cert: %w", err)
        }
        
        certPool := x509.NewCertPool()
        if !certPool.AppendCertsFromPEM(caCert) {
            return nil, fmt.Errorf("failed to parse CA cert")
        }
        tlsConfig.RootCAs = certPool
    }
    
    if cfg.CertPath != "" && cfg.KeyPath != "" {
        cert, err := tls.LoadX509KeyPair(cfg.CertPath, cfg.KeyPath)
        if err != nil {
            return nil, fmt.Errorf("failed to load cert pair: %w", err)
        }
        tlsConfig.Certificates = []tls.Certificate{cert}
    }
    
    return tlsConfig, nil
}
```

### Python Redis 连接

```python
import redis
import ssl
from typing import Optional


class RedisConnection:
    def __init__(
        self,
        host: str,
        port: int = 6379,
        password: Optional[str] = None,
        db: int = 0,
        ssl_enabled: bool = True,
        ssl_ca_certs: Optional[str] = None,
        ssl_certfile: Optional[str] = None,
        ssl_keyfile: Optional[str] = None,
    ):
        self.config = {
            "host": host,
            "port": port,
            "password": password,
            "db": db,
            "ssl": ssl_enabled,
        }
        
        if ssl_enabled:
            self.config["ssl_ca_certs"] = ssl_ca_certs
            self.config["ssl_certfile"] = ssl_certfile
            self.config["ssl_keyfile"] = ssl_keyfile
            self.config["ssl_cert_reqs"] = ssl.CERT_REQUIRED
    
    def get_client(self) -> redis.Redis:
        return redis.Redis(**self.config)
    
    def test_connection(self) -> bool:
        try:
            client = self.get_client()
            return client.ping()
        except redis.ConnectionError as e:
            print(f"Redis connection test failed: {e}")
            return False
```

## GKE 内部 mTLS

### Istio mTLS 配置

```yaml
# kubernetes/base/istio-mtls.yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: myapp
spec:
  mtls:
    mode: STRICT
---
apiVersion: security.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: default
  namespace: myapp
spec:
  host: "*.myapp.svc.cluster.local"
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
```

### Service Mesh 配置

```yaml
# kubernetes/base/service-mesh.yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: myapp-db
  namespace: myapp
spec:
  host: myapp-db.myapp.svc.cluster.local
  trafficPolicy:
    tls:
      mode: SIMPLE
      clientCertificate: /etc/istio/ingressgateway-certs/tls.crt
      privateKey: /etc/istio/ingressgateway-certs/tls.key
      caCertificates: /etc/istio/ingressgateway-ca/ca.crt
```

## TLS 配置检查清单

### 部署前检查

```bash
#!/bin/bash
# scripts/check-tls.sh

echo "Checking TLS configuration..."

# 检查证书有效期
check_cert_expiry() {
    local cert_file=$1
    local domain=$2
    
    expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" | cut -d= -f2)
    expiry_epoch=$(date -d "$expiry_date" +%s)
    current_epoch=$(date +%s)
    days_left=$(( (expiry_epoch - current_epoch) / 86400 ))
    
    if [ $days_left -lt 30 ]; then
        echo "⚠️  Certificate for $domain expires in $days_left days"
    else
        echo "✅ Certificate for $domain valid for $days_left days"
    fi
}

# 检查 TLS 版本
check_tls_version() {
    local host=$1
    local port=$2
    
    echo "Checking TLS version for $host:$port..."
    
    if echo | openssl s_client -connect "$host:$port" -tls1_2 2>/dev/null | grep -q "Protocol"; then
        echo "✅ TLS 1.2 supported"
    else
        echo "❌ TLS 1.2 not supported"
    fi
    
    if echo | openssl s_client -connect "$host:$port" -tls1_3 2>/dev/null | grep -q "Protocol"; then
        echo "✅ TLS 1.3 supported"
    else
        echo "⚠️  TLS 1.3 not supported"
    fi
}

# 检查证书链
check_cert_chain() {
    local host=$1
    local port=$2
    
    echo "Checking certificate chain for $host:$port..."
    
    if echo | openssl s_client -connect "$host:$port" -showcerts 2>/dev/null | grep -q "verify return:1"; then
        echo "❌ Certificate chain incomplete"
    else
        echo "✅ Certificate chain valid"
    fi
}

# 执行检查
check_tls_version "api.myapp.com" "443"
check_cert_chain "api.myapp.com" "443"
```

### TLS 最佳实践

| 配置项 | 推荐值 | 说明 |
|--------|--------|------|
| TLS 版本 | 1.2+ | 禁用 TLS 1.0/1.1 |
| 密码套件 | ECDHE+AESGCM | 优先使用前向保密 |
| 证书类型 | ECC | 更高效、更安全 |
| 证书有效期 | ≤ 1 年 | 减少泄露风险 |
| HSTS | 启用 | 强制 HTTPS |

## 常见问题排查

### 证书验证失败

```bash
# 检查证书链
openssl s_client -connect api.myapp.com:443 -showcerts

# 验证证书
openssl verify -CAfile ca.crt server.crt

# 检查证书详情
openssl x509 -in server.crt -text -noout
```

### TLS 握手失败

```bash
# 详细 TLS 握手信息
openssl s_client -connect api.myapp.com:443 -debug

# 测试特定密码套件
openssl s_client -connect api.myapp.com:443 -cipher 'ECDHE-RSA-AES256-GCM-SHA384'
```

### 连接超时

```bash
# 测试端口连通性
nc -zv api.myapp.com 443

# 测试 TLS 连接
timeout 5 openssl s_client -connect api.myapp.com:443
```
