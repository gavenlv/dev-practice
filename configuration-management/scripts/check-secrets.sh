#!/bin/bash
set -euo pipefail

ENV=${1:-prod}
PROJECT_ID="myapp-${ENV}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "Secret Manager Check for ${ENV}"
echo "=========================================="
echo ""

errors=0

check_gcloud() {
    if ! command -v gcloud &> /dev/null; then
        echo -e "${RED}✗ gcloud CLI not installed${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ gcloud CLI installed${NC}"
}

check_project() {
    echo ""
    echo -e "${YELLOW}Checking GCP project...${NC}"
    
    if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        echo -e "${RED}✗ Project not found: ${PROJECT_ID}${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Project found: ${PROJECT_ID}${NC}"
}

check_secrets() {
    echo ""
    echo -e "${YELLOW}Checking required secrets...${NC}"
    
    local required_secrets=(
        "${ENV}/myapp/database/password"
        "${ENV}/myapp/database/host"
        "${ENV}/myapp/database/user"
        "${ENV}/myapp/redis/password"
    )
    
    local missing_secrets=()
    
    for secret in "${required_secrets[@]}"; do
        if gcloud secrets describe "$secret" --project="$PROJECT_ID" &>/dev/null; then
            echo -e "${GREEN}✓ Secret found: ${secret}${NC}"
        else
            echo -e "${RED}✗ Secret missing: ${secret}${NC}"
            missing_secrets+=("$secret")
            ((errors++))
        fi
    done
    
    if [ ${#missing_secrets[@]} -gt 0 ]; then
        echo ""
        echo -e "${YELLOW}Missing secrets:${NC}"
        for secret in "${missing_secrets[@]}"; do
            echo "  - $secret"
        done
    fi
}

check_secret_versions() {
    echo ""
    echo -e "${YELLOW}Checking secret versions...${NC}"
    
    local secrets=(
        "${ENV}/myapp/database/password"
        "${ENV}/myapp/redis/password"
    )
    
    for secret in "${secrets[@]}"; do
        if gcloud secrets describe "$secret" --project="$PROJECT_ID" &>/dev/null; then
            local version_count
            version_count=$(gcloud secrets versions list "$secret" --project="$PROJECT_ID" --filter="state:ENABLED" --format="value(name)" | wc -l)
            
            if [ "$version_count" -gt 0 ]; then
                echo -e "${GREEN}✓ ${secret}: ${version_count} enabled version(s)${NC}"
            else
                echo -e "${RED}✗ ${secret}: No enabled versions${NC}"
                ((errors++))
            fi
        fi
    done
}

check_iam_permissions() {
    echo ""
    echo -e "${YELLOW}Checking IAM permissions...${NC}"
    
    local service_account="myapp-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    
    if gcloud iam service-accounts describe "$service_account" --project="$PROJECT_ID" &>/dev/null; then
        echo -e "${GREEN}✓ Service account found: ${service_account}${NC}"
        
        local has_secret_access
        has_secret_access=$(gcloud projects get-iam-policy "$PROJECT_ID" \
            --flatten="bindings[].members" \
            --filter="bindings.members:serviceAccount:${service_account} AND bindings.role:roles/secretmanager.secretAccessor" \
            --format="value(bindings.role)" 2>/dev/null || echo "")
        
        if [ -n "$has_secret_access" ]; then
            echo -e "${GREEN}✓ Service account has secret accessor role${NC}"
        else
            echo -e "${YELLOW}⚠ Service account may not have secret accessor role${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ Service account not found: ${service_account}${NC}"
    fi
}

print_summary() {
    echo ""
    echo "=========================================="
    echo "Secret Check Summary"
    echo "=========================================="
    echo ""
    
    if [ $errors -gt 0 ]; then
        echo -e "${RED}✗ Found ${errors} error(s)${NC}"
        echo ""
        echo "Please create missing secrets before deployment."
        exit 1
    else
        echo -e "${GREEN}✓ All secrets are properly configured${NC}"
    fi
}

main() {
    check_gcloud
    check_project
    check_secrets
    check_secret_versions
    check_iam_permissions
    print_summary
}

main
