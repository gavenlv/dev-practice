#!/bin/bash
set -euo pipefail

HOST=${1:-""}
PORT=${2:-"443"}

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ -z "$HOST" ]; then
    echo "Usage: $0 <host> [port]"
    echo ""
    echo "Examples:"
    echo "  $0 google.com"
    echo "  $0 api.myapp.com 8443"
    exit 1
fi

echo "=========================================="
echo "TLS Endpoint Check: ${HOST}:${PORT}"
echo "=========================================="
echo ""

echo -e "${YELLOW}1. TLS Version Support${NC}"
echo ""

for version in "ssl3:SSLv3" "tls1:TLS 1.0" "tls1_1:TLS 1.1" "tls1_2:TLS 1.2" "tls1_3:TLS 1.3"; do
    vflag="${version%%:*}"
    vname="${version##*:}"
    
    if echo | openssl s_client -connect "$HOST:$PORT" -"$vflag" 2>/dev/null | grep -q "Protocol"; then
        if [[ "$vname" == "SSLv3" || "$vname" == "TLS 1.0" || "$vname" == "TLS 1.1" ]]; then
            echo -e "  ${RED}❌ $vname: Supported (should be disabled)${NC}"
        else
            echo -e "  ${GREEN}✅ $vname: Supported${NC}"
        fi
    else
        if [[ "$vname" == "SSLv3" || "$vname" == "TLS 1.0" || "$vname" == "TLS 1.1" ]]; then
            echo -e "  ${GREEN}✅ $vname: Not supported (good)${NC}"
        else
            echo -e "  ${YELLOW}⚠️  $vname: Not supported${NC}"
        fi
    fi
done

echo ""
echo -e "${YELLOW}2. Certificate Information${NC}"
echo ""

cert_info=$(echo | openssl s_client -connect "$HOST:$PORT" -servername "$HOST" 2>/dev/null)

if echo "$cert_info" | openssl x509 -noout -subject 2>/dev/null; then
    echo ""
    echo "Issuer:"
    echo "$cert_info" | openssl x509 -noout -issuer 2>/dev/null
    echo ""
    echo "Validity:"
    echo "$cert_info" | openssl x509 -noout -dates 2>/dev/null
    
    expiry_date=$(echo "$cert_info" | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
    if [ -n "$expiry_date" ]; then
        expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$expiry_date" +%s 2>/dev/null || echo "0")
        current_epoch=$(date +%s)
        if [ "$expiry_epoch" -gt 0 ]; then
            days_left=$(( (expiry_epoch - current_epoch) / 86400 ))
            if [ "$days_left" -lt 7 ]; then
                echo -e "  ${RED}⚠️  Expires in $days_left days!${NC}"
            elif [ "$days_left" -lt 30 ]; then
                echo -e "  ${YELLOW}⚠️  Expires in $days_left days${NC}"
            else
                echo -e "  ${GREEN}✅ Expires in $days_left days${NC}"
            fi
        fi
    fi
    
    echo ""
    echo "SAN:"
    echo "$cert_info" | openssl x509 -noout -text 2>/dev/null | grep -A 1 "Subject Alternative Name" || echo "  Not available"
else
    echo -e "  ${RED}❌ Could not retrieve certificate${NC}"
fi

echo ""
echo -e "${YELLOW}3. Connection Details${NC}"
echo ""

negotiated_version=$(echo "$cert_info" | grep "Protocol  :" | awk '{print $NF}')
negotiated_cipher=$(echo "$cert_info" | grep "Cipher    :" | awk '{print $NF}')

if [ -n "$negotiated_version" ]; then
    echo "  Negotiated Protocol: $negotiated_version"
fi
if [ -n "$negotiated_cipher" ]; then
    echo "  Negotiated Cipher: $negotiated_cipher"
fi

echo ""
echo -e "${YELLOW}4. Security Check${NC}"
echo ""

if echo "$negotiated_cipher" | grep -qiE "CBC|RC4|3DES|NULL|EXPORT"; then
    echo -e "  ${RED}❌ Weak cipher detected: $negotiated_cipher${NC}"
else
    echo -e "  ${GREEN}✅ No weak cipher detected${NC}"
fi

echo ""
echo "=========================================="
echo "Check complete!"
echo "=========================================="
