#!/bin/bash
set -euo pipefail

ENV=${1:-prod}
NAMESPACE="myapp-${ENV}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "Post-deployment Check for ${ENV}"
echo "=========================================="
echo ""

errors=0

check_deployment() {
    echo -e "${YELLOW}Checking deployment status...${NC}"
    
    local ready_replicas
    ready_replicas=$(kubectl get deployment myapp -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    
    local desired_replicas
    desired_replicas=$(kubectl get deployment myapp -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    
    if [ "$ready_replicas" == "$desired_replicas" ] && [ "$ready_replicas" -gt 0 ]; then
        echo -e "${GREEN}✓ All replicas ready: ${ready_replicas}/${desired_replicas}${NC}"
    else
        echo -e "${YELLOW}⚠ Replicas not ready: ${ready_replicas}/${desired_replicas}${NC}"
    fi
    
    kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=myapp
}

check_pod_status() {
    echo ""
    echo -e "${YELLOW}Checking pod status...${NC}"
    
    local pods
    pods=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=myapp -o jsonpath='{.items[*].metadata.name}')
    
    for pod in $pods; do
        local status
        status=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
        
        if [ "$status" == "Running" ]; then
            echo -e "${GREEN}✓ Pod ${pod}: ${status}${NC}"
        else
            echo -e "${RED}✗ Pod ${pod}: ${status}${NC}"
            ((errors++))
        fi
    done
}

check_logs() {
    echo ""
    echo -e "${YELLOW}Checking for errors in logs...${NC}"
    
    local error_count
    error_count=$(kubectl logs -l app.kubernetes.io/name=myapp -n "$NAMESPACE" --tail=100 2>/dev/null | grep -ci "error" || echo "0")
    
    if [ "$error_count" -gt 0 ]; then
        echo -e "${YELLOW}⚠ Found ${error_count} error(s) in recent logs${NC}"
    else
        echo -e "${GREEN}✓ No errors in recent logs${NC}"
    fi
}

check_service() {
    echo ""
    echo -e "${YELLOW}Checking service...${NC}"
    
    if kubectl get service myapp -n "$NAMESPACE" &>/dev/null; then
        echo -e "${GREEN}✓ Service exists: myapp${NC}"
        
        local cluster_ip
        cluster_ip=$(kubectl get service myapp -n "$NAMESPACE" -o jsonpath='{.spec.clusterIP}')
        echo -e "  ClusterIP: ${cluster_ip}"
    else
        echo -e "${RED}✗ Service not found: myapp${NC}"
        ((errors++))
    fi
}

check_health() {
    echo ""
    echo -e "${YELLOW}Checking application health...${NC}"
    
    local pod
    pod=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=myapp -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -n "$pod" ]; then
        if kubectl exec -n "$NAMESPACE" "$pod" -- curl -sf http://localhost:8080/health &>/dev/null; then
            echo -e "${GREEN}✓ Health check passed${NC}"
        else
            echo -e "${RED}✗ Health check failed${NC}"
            ((errors++))
        fi
        
        if kubectl exec -n "$NAMESPACE" "$pod" -- curl -sf http://localhost:8080/ready &>/dev/null; then
            echo -e "${GREEN}✓ Readiness check passed${NC}"
        else
            echo -e "${RED}✗ Readiness check failed${NC}"
            ((errors++))
        fi
    fi
}

check_tls() {
    echo ""
    echo -e "${YELLOW}Checking TLS configuration...${NC}"
    
    if [ "$ENV" == "prod" ]; then
        if kubectl get managedcertificate myapp-prod-cert -n "$NAMESPACE" &>/dev/null; then
            local cert_status
            cert_status=$(kubectl get managedcertificate myapp-prod-cert -n "$NAMESPACE" -o jsonpath='{.status.certificateStatus}' 2>/dev/null || echo "")
            
            if [ "$cert_status" == "Active" ]; then
                echo -e "${GREEN}✓ Managed certificate is active${NC}"
            else
                echo -e "${YELLOW}⚠ Managed certificate status: ${cert_status}${NC}"
            fi
        fi
    fi
}

print_summary() {
    echo ""
    echo "=========================================="
    echo "Post-deployment Check Summary"
    echo "=========================================="
    echo ""
    
    if [ $errors -gt 0 ]; then
        echo -e "${RED}✗ Found ${errors} error(s)${NC}"
        echo ""
        echo "Check the following:"
        echo "  kubectl logs -l app.kubernetes.io/name=myapp -n ${NAMESPACE}"
        echo "  kubectl describe pods -l app.kubernetes.io/name=myapp -n ${NAMESPACE}"
        exit 1
    else
        echo -e "${GREEN}✓ Deployment successful${NC}"
    fi
}

main() {
    check_deployment
    check_pod_status
    check_logs
    check_service
    check_health
    check_tls
    print_summary
}

main
