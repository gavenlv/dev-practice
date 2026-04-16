#!/bin/bash
set -euo pipefail

ENV=${1:-local}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_DIR="${PROJECT_ROOT}/config"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "Configuration Validation for ${ENV}"
echo "=========================================="
echo ""

errors=0
warnings=0

check_config_file() {
    local config_file="${CONFIG_DIR}/config.${ENV}.yaml"
    
    echo -e "${YELLOW}Checking configuration file...${NC}"
    
    if [ ! -f "$config_file" ]; then
        echo -e "${YELLOW}⚠ Config file not found: ${config_file}${NC}"
        echo -e "${YELLOW}  Using default configuration only${NC}"
        return 0
    fi
    
    echo -e "${GREEN}✓ Config file found: ${config_file}${NC}"
    
    if ! command -v yq &> /dev/null; then
        echo -e "${YELLOW}⚠ yq not installed, skipping YAML validation${NC}"
        return 0
    fi
    
    if ! yq eval '.' "$config_file" > /dev/null 2>&1; then
        echo -e "${RED}✗ Invalid YAML syntax in ${config_file}${NC}"
        ((errors++))
        return 1
    fi
    
    echo -e "${GREEN}✓ Valid YAML syntax${NC}"
}

check_required_fields() {
    echo ""
    echo -e "${YELLOW}Checking required configuration fields...${NC}"
    
    local required_fields=(
        "database.host"
        "database.name"
        "redis.host"
    )
    
    local config_file="${CONFIG_DIR}/config.${ENV}.yaml"
    
    if [ ! -f "$config_file" ]; then
        echo -e "${YELLOW}⚠ Skipping field check (no config file)${NC}"
        return 0
    fi
    
    for field in "${required_fields[@]}"; do
        if command -v yq &> /dev/null; then
            value=$(yq eval ".${field}" "$config_file" 2>/dev/null || echo "")
            if [ -z "$value" ] || [ "$value" == "null" ]; then
                echo -e "${RED}✗ Missing required field: ${field}${NC}"
                ((errors++))
            else
                echo -e "${GREEN}✓ Field present: ${field}${NC}"
            fi
        fi
    done
}

check_sensitive_data() {
    echo ""
    echo -e "${YELLOW}Checking for sensitive data in config files...${NC}"
    
    local config_file="${CONFIG_DIR}/config.${ENV}.yaml"
    
    if [ ! -f "$config_file" ]; then
        return 0
    fi
    
    local sensitive_patterns=(
        "password"
        "secret"
        "api_key"
        "apikey"
        "token"
        "credential"
    )
    
    for pattern in "${sensitive_patterns[@]}"; do
        if grep -iE "^\s*${pattern}\s*:" "$config_file" | grep -v "^\s*#" | grep -q ":"; then
            echo -e "${RED}✗ Possible sensitive data found: ${pattern}${NC}"
            echo -e "${RED}  Consider using Secret Manager instead${NC}"
            ((warnings++))
        fi
    done
    
    if [ $warnings -eq 0 ]; then
        echo -e "${GREEN}✓ No sensitive data found in config file${NC}"
    fi
}

check_ssl_config() {
    echo ""
    echo -e "${YELLOW}Checking SSL/TLS configuration...${NC}"
    
    local config_file="${CONFIG_DIR}/config.${ENV}.yaml"
    
    if [ ! -f "$config_file" ]; then
        return 0
    fi
    
    if command -v yq &> /dev/null; then
        local ssl_mode
        ssl_mode=$(yq eval '.database.ssl_mode // "require"' "$config_file")
        
        local valid_modes=("disable" "require" "verify-ca" "verify-full")
        local ssl_valid=false
        
        for mode in "${valid_modes[@]}"; do
            if [ "$ssl_mode" == "$mode" ]; then
                ssl_valid=true
                break
            fi
        done
        
        if [ "$ssl_valid" = true ]; then
            echo -e "${GREEN}✓ Database SSL mode: ${ssl_mode}${NC}"
        else
            echo -e "${RED}✗ Invalid database SSL mode: ${ssl_mode}${NC}"
            ((errors++))
        fi
        
        local redis_ssl
        redis_ssl=$(yq eval '.redis.ssl // true' "$config_file")
        
        if [ "$redis_ssl" = "true" ] || [ "$redis_ssl" = true ]; then
            echo -e "${GREEN}✓ Redis SSL enabled${NC}"
        else
            echo -e "${YELLOW}⚠ Redis SSL disabled${NC}"
            ((warnings++))
        fi
    fi
}

check_env_file() {
    echo ""
    echo -e "${YELLOW}Checking .env file...${NC}"
    
    local env_file="${PROJECT_ROOT}/.env.${ENV}"
    
    if [ "$ENV" == "local" ]; then
        if [ -f "${PROJECT_ROOT}/.env.local" ]; then
            echo -e "${GREEN}✓ Local .env file found${NC}"
        else
            echo -e "${YELLOW}⚠ No .env.local file found${NC}"
            echo -e "${YELLOW}  Consider creating one from template${NC}"
            ((warnings++))
        fi
    fi
}

print_summary() {
    echo ""
    echo "=========================================="
    echo "Validation Summary"
    echo "=========================================="
    echo ""
    
    if [ $errors -gt 0 ]; then
        echo -e "${RED}✗ Found ${errors} error(s)${NC}"
    else
        echo -e "${GREEN}✓ No errors found${NC}"
    fi
    
    if [ $warnings -gt 0 ]; then
        echo -e "${YELLOW}⚠ Found ${warnings} warning(s)${NC}"
    fi
    
    echo ""
    
    if [ $errors -gt 0 ]; then
        exit 1
    fi
}

main() {
    check_config_file
    check_required_fields
    check_sensitive_data
    check_ssl_config
    check_env_file
    print_summary
}

main
