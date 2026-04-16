#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PKI_DIR="${PROJECT_ROOT}/pki"

CERT_FILE=${1:-""}
CA_FILE=${2:-"${PKI_DIR}/root-ca/ca.crt"}

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "Certificate Chain Verification"
echo "=========================================="
echo ""

if [ -z "$CERT_FILE" ]; then
    echo "Usage: $0 <cert-file> [ca-cert-file]"
    echo ""
    echo "Examples:"
    echo "  $0 pki/certs/server/server.myapp.local.crt"
    echo "  $0 pki/certs/server/server.myapp.local.crt pki/root-ca/ca.crt"
    exit 1
fi

if [ ! -f "$CERT_FILE" ]; then
    echo -e "${RED}❌ Certificate file not found: $CERT_FILE${NC}"
    exit 1
fi

echo -e "${YELLOW}Certificate Details:${NC}"
echo ""

openssl x509 -in "$CERT_FILE" -noout -subject -issuer -dates -serial

echo ""
echo -e "${YELLOW}Certificate Chain Verification:${NC}"
echo ""

if [ -f "$CA_FILE" ]; then
    if openssl verify -CAfile "$CA_FILE" "$CERT_FILE"; then
        echo ""
        echo -e "${GREEN}✅ Certificate chain is valid!${NC}"
    else
        echo ""
        echo -e "${RED}❌ Certificate chain verification failed!${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}⚠️  CA file not found: $CA_FILE${NC}"
    echo "Skipping chain verification."
fi

echo ""
echo -e "${YELLOW}Certificate Extensions:${NC}"
echo ""

openssl x509 -in "$CERT_FILE" -noout -text | grep -A 3 "Subject Alternative Name" || echo "No SAN found"

echo ""
echo -e "${YELLOW}Key Usage:${NC}"
echo ""

openssl x509 -in "$CERT_FILE" -noout -text | grep -A 5 "Key Usage" || echo "No Key Usage found"

echo ""
echo -e "${YELLOW}Extended Key Usage:${NC}"
echo ""

openssl x509 -in "$CERT_FILE" -noout -text | grep -A 3 "Extended Key Usage" || echo "No Extended Key Usage found"
