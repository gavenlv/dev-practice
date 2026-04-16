#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PKI_DIR="${PROJECT_ROOT}/pki"

SERVER_NAME=${1:-"server.myapp.local"}
CA_DIR="${PKI_DIR}/root-ca"
SERVER_DIR="${PKI_DIR}/certs/server"

echo "=========================================="
echo "Creating Server Certificate: ${SERVER_NAME}"
echo "=========================================="
echo ""

if [ ! -f "${CA_DIR}/ca.crt" ]; then
    echo "❌ Root CA not found. Run generate-ca.sh first."
    exit 1
fi

mkdir -p "${SERVER_DIR}"

openssl genrsa -out "${SERVER_DIR}/${SERVER_NAME}.key" 2048

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

openssl req -new \
  -key "${SERVER_DIR}/${SERVER_NAME}.key" \
  -out "${SERVER_DIR}/${SERVER_NAME}.csr" \
  -subj "/C=CN/ST=Shanghai/L=Shanghai/O=MyApp/CN=${SERVER_NAME}"

openssl x509 -req \
  -in "${SERVER_DIR}/${SERVER_NAME}.csr" \
  -CA "${CA_DIR}/ca.crt" \
  -CAkey "${CA_DIR}/ca.key" \
  -CAcreateserial \
  -out "${SERVER_DIR}/${SERVER_NAME}.crt" \
  -days 365 -sha256 \
  -extfile "${SERVER_DIR}/${SERVER_NAME}.ext"

openssl verify -CAfile "${CA_DIR}/ca.crt" "${SERVER_DIR}/${SERVER_NAME}.crt"

cat "${SERVER_DIR}/${SERVER_NAME}.crt" "${CA_DIR}/ca.crt" > "${SERVER_DIR}/${SERVER_NAME}-fullchain.crt"

echo ""
echo "✅ Server certificate created!"
echo ""
echo "Files:"
echo "  Private Key:  ${SERVER_DIR}/${SERVER_NAME}.key"
echo "  Certificate:  ${SERVER_DIR}/${SERVER_NAME}.crt"
echo "  Full Chain:   ${SERVER_DIR}/${SERVER_NAME}-fullchain.crt"
echo ""
echo "Test with:"
echo "  openssl s_server -cert ${SERVER_DIR}/${SERVER_NAME}-fullchain.crt -key ${SERVER_DIR}/${SERVER_NAME}.key -accept 8443"
