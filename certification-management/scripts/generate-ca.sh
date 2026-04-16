#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PKI_DIR="${PROJECT_ROOT}/pki"

CA_NAME=${1:-"myapp"}
CA_DIR="${PKI_DIR}/root-ca"

echo "=========================================="
echo "Creating Root CA: ${CA_NAME}"
echo "=========================================="
echo ""

mkdir -p "${CA_DIR}"

openssl genrsa -out "${CA_DIR}/ca.key" 4096

openssl req -x509 -new -nodes \
  -key "${CA_DIR}/ca.key" \
  -sha256 -days 3650 \
  -out "${CA_DIR}/ca.crt" \
  -subj "/C=CN/ST=Shanghai/L=Shanghai/O=${CA_NAME}/CN=${CA_NAME} Root CA"

cat > "${CA_DIR}/ca.cnf" << EOF
[ ca ]
default_ca = CA_default

[ CA_default ]
dir               = ${CA_DIR}
database          = \$dir/index.txt
new_certs_dir     = \$dir
serial            = \$dir/serial
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

touch "${CA_DIR}/index.txt"
echo "01" > "${CA_DIR}/serial"

echo ""
echo "✅ Root CA created successfully!"
echo ""
echo "Files:"
echo "  Private Key: ${CA_DIR}/ca.key"
echo "  Certificate: ${CA_DIR}/ca.crt"
echo ""
echo "⚠️  IMPORTANT: Keep ca.key secure!"
echo "   In production, store in HSM or encrypted storage."
echo ""
echo "Verify:"
echo "  openssl x509 -in ${CA_DIR}/ca.crt -text -noout"
