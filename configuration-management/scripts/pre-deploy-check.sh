#!/bin/bash
set -euo pipefail

ENV=${1:-prod}
NAMESPACE="myapp-${ENV}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "Pre-deployment Check for ${ENV}"
echo "=========================================="
echo ""

errors=0

check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}✗ kubectl not installed${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ kubectl installed${NC}"
}

check_cluster_connection() {
    echo ""
    echo -e "${YELLOW}Checking cluster connection...${NC}"
    
    if ! kubectl cluster-info &>/dev/null; then
        echo -e "${RED}✗ Cannot connect to cluster${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Connected to cluster${NC}"
}

check_namespace() {
    echo ""
    echo -e "${YELLOW}Checking namespace...${NC}"
    
    if kubectl get namespace "$NAMESPACE" &>/dev/null; then
        echo -e "${GREEN}✓ Namespace exists: ${NAMESPACE}${NC}"
    else
        echo -e "${YELLOW}⚠ Namespace not found: ${NAMESPACE}${NC}"
        echo -e "${YELLOW}  Will be created during deployment${NC}"
    fi
}

check_configmap() {
    echo ""
    echo -e "${YELLOW}Checking ConfigMap...${NC}"
    
    if kubectl get configmap myapp-config -n "$NAMESPACE" &>/dev/null; then
        echo -e "${GREEN}✓ ConfigMap exists: myapp-config${NC}"
    else
        echo -e "${YELLOW}⚠ ConfigMap not found: myapp-config${NC}"
        echo -e "${YELLOW}  Will be created during deployment${NC}"
    fi
}

check_secrets() {
    echo ""
    echo -e "${YELLOW}Checking Secrets...${NC}"
    
    local secrets=("myapp-secrets" "myapp-tls-secret")
    
    for secret in "${secrets[@]}"; do
        if kubectl get secret "$secret" -n "$NAMESPACE" &>/dev/null; then
            echo -e "${GREEN}✓ Secret exists: ${secret}${NC}"
        else
            echo -e "${YELLOW}⚠ Secret not found: ${secret}${NC}"
            echo -e "${YELLOW}  Will be created by External Secrets Operator${NC}"
        fi
    done
}

check_service_account() {
    echo ""
    echo -e "${YELLOW}Checking Service Account...${NC}"
    
    if kubectl get serviceaccount myapp-sa -n "$NAMESPACE" &>/dev/null; then
        echo -e "${GREEN}✓ ServiceAccount exists: myapp-sa${NC}"
        
        local annotation
        annotation=$(kubectl get serviceaccount myapp-sa -n "$NAMESPACE" -o jsonpath='{.metadata.annotations.iam\.gke\.io/gcp-service-account}' 2>/dev/null || echo "")
        
        if [ -n "$annotation" ]; then
            echo -e "${GREEN}✓ Workload Identity configured: ${annotation}${NC}"
        else
            echo -e "${YELLOW}⚠ Workload Identity not configured${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ ServiceAccount not found: myapp-sa${NC}"
    fi
}

check_resource_quotas() {
    echo ""
    echo -e "${YELLOW}Checking resource quotas...${NC}"
    
    if kubectl get resourcequota -n "$NAMESPACE" &>/dev/null; then
        echo -e "${GREEN}✓ ResourceQuota exists${NC}"
        kubectl get resourcequota -n "$NAMESPACE" -o custom-columns=NAME:.metadata.name,CPU\ REQUESTS:.status.hard.requests\.cpu,MEMORY\ REQUESTS:.status.hard.requests\.memory
    else
        echo -e "${YELLOW}⚠ No ResourceQuota found${NC}"
    fi
}

check_pdb() {
    echo ""
    echo -e "${YELLOW}Checking Pod Disruption Budget...${NC}"
    
    if kubectl get pdb myapp-pdb -n "$NAMESPACE" &>/dev/null; then
        echo -e "${GREEN}✓ PDB exists: myapp-pdb${NC}"
    else
        if [ "$ENV" == "prod" ]; then
            echo -e "${YELLOW}⚠ PDB not found for production${NC}"
        else
            echo -e "${GREEN}✓ PDB not required for non-production${NC}"
        fi
    fi
}

print_summary() {
    echo ""
    echo "=========================================="
    echo "Pre-deployment Check Summary"
    echo "=========================================="
    echo ""
    
    if [ $errors -gt 0 ]; then
        echo -e "${RED}✗ Found ${errors} error(s)${NC}"
        exit 1
    else
        echo -e "${GREEN}✓ Ready for deployment${NC}"
        echo ""
        echo "To deploy, run:"
        echo "  kubectl apply -k kubernetes/overlays/${ENV}"
    fi
}

main() {
    check_kubectl
    check_cluster_connection
    check_namespace
    check_configmap
    check_secrets
    check_service_account
    check_resource_quotas
    check_pdb
    print_summary
}

main
