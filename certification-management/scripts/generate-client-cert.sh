#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PKI_DIR="${PROJECT_ROOT}/pki"

CLIENT_NAME=${1:-"client.myapp.local"}
CA_DIR="${PKI_DIR}/root-ca"
CLIENT_DIR="${PKI_DIR}/certs/client"

echo "=========================================="
echo "Creating Client Certificate: ${CLIENT_NAME}"
echo "=========================================="
echo ""

if [ ! -f "${CA_DIR}/ca.crt" ]; then
    echo "❌ Root CA not found. Run generate-ca.sh first."
    exit 1
fi

mkdir -p "${CLIENT_DIR}"

openssl genrsa -out "${CLIENT_DIR}/${CLIENT_NAME}.key" 2048

cat > "${CLIENT_DIR}/${CLIENT_NAME}.ext" << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
extendedKeyUsage = clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${CLIENT_NAME}
EOF

openssl req -new \
  -key "${CLIENT_DIR}/${CLIENT_NAME}.key" \
  -out "${CLIENT_DIR}/${CLIENT_NAME}.csr" \
  -subj "/C=CN/ST=Shanghai/L=Shanghai/O=MyApp/CN=${CLIENT_NAME}"

openssl x509 -req \
  -in "${CLIENT_DIR}/${CLIENT_NAME}.csr" \
  -CA "${CA_DIR}/ca.crt" \
  -CAkey "${CA_DIR}/ca.key" \
  -CAcreateserial \
  -out "${CLIENT_DIR}/${CLIENT_NAME}.crt" \
  -days 365 -sha256 \
  -extfile "${CLIENT_DIR}/${CLIENT_NAME}.ext"

openssl verify -CAfile "${CA_DIR}/ca.crt" "${CLIENT_DIR}/${CLIENT_NAME}.crt"

openssl pkcs12 -export \
  -out "${CLIENT_DIR}/${CLIENT_NAME}.p12" \
  -inkey "${CLIENT_DIR}/${CLIENT_NAME}.key" \
  -in "${CLIENT_DIR}/${CLIENT_NAME}.crt" \
  -certfile "${CA_DIR}/ca.crt" \
  -passout pass:

echo ""
echo "✅ Client certificate created!"
echo ""
echo "Files:"
echo "  Private Key:  ${CLIENT_DIR}/${CLIENT_NAME}.key"
echo "  Certificate:  ${CLIENT_DIR}/${CLIENT_NAME}.crt"
echo "  PKCS#12:      ${CLIENT_DIR}/${CLIENT_NAME}.p12"
echo ""
echo "Test mTLS with:"
echo "  curl --cacert ${CA_DIR}/ca.crt \\"
echo "       --cert ${CLIENT_DIR}/${CLIENT_NAME}.crt \\"
echo "       --key ${CLIENT_DIR}/${CLIENT_NAME}.key \\"
echo "       https://server.myapp.local:8443/"
