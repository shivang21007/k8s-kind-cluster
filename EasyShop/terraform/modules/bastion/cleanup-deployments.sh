#!/bin/bash

# Exit on error
set -e

# Colors for output (Hacker-style)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Fancy banner
print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════╗"
    echo "║         EasyShop Cleanup Script          ║"
    echo "║        Safe Deployment Removal           ║"
    echo "╚══════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Logging functions with timestamps
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ${1}${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  WARNING: ${1}${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ ERROR: ${1}${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] ℹ️  ${1}${NC}"
}

success() {
    echo -e "${WHITE}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ ${1}${NC}"
}

# Function to check if kubectl is available
check_kubectl() {
    if ! command -v kubectl &>/dev/null; then
        error "kubectl is not installed!"
        exit 1
    fi
}

# Function to check cluster connection
check_cluster() {
    if ! kubectl get nodes &>/dev/null; then
        error "Cannot connect to Kubernetes cluster!"
        exit 1
    fi
}

# Function to delete a namespace safely
delete_namespace() {
    local namespace=$1
    info "Attempting to delete namespace: $namespace"
    
    # Delete the namespace
    if kubectl delete namespace "$namespace" --timeout=60s 2>/dev/null; then
        success "Successfully deleted namespace: $namespace"
    else
        warn "Could not delete namespace: $namespace normally, forcing deletion..."
        
        # Get namespace JSON for force deletion
        kubectl get namespace "$namespace" -o json > "$namespace.json"
        # Remove finalizers
        sed -i 's/"finalizers": \[[^]]*\]/"finalizers": []/' "$namespace.json"
        # Force delete namespace
        kubectl replace --raw "/api/v1/namespaces/$namespace/finalize" -f "$namespace.json"
        rm "$namespace.json"
        success "Forced deletion of namespace: $namespace"
    fi
}

# Function to delete Helm releases
delete_helm_releases() {
    local namespace=$1
    info "Checking for Helm releases in namespace: $namespace"
    
    if helm list -n "$namespace" 2>/dev/null | grep -q .; then
        warn "Found Helm releases in namespace: $namespace"
        helm list -n "$namespace" | tail -n +2 | awk '{print $1}' | while read -r release; do
            info "Uninstalling Helm release: $release"
            helm uninstall "$release" -n "$namespace" || true
        done
        success "Removed Helm releases from namespace: $namespace"
    fi
}

# Main cleanup function
cleanup() {
    print_banner
    
    # Check prerequisites
    log "Checking prerequisites..."
    check_kubectl
    check_cluster
    
    # Protected namespaces
    protected_namespaces=("kube-system" "kube-public" "kube-node-lease" "default")
    
    # Get all namespaces
    log "Getting list of namespaces..."
    namespaces=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}')
    
    # Process each namespace
    for namespace in $namespaces; do
        # Skip protected namespaces
        if [[ " ${protected_namespaces[@]} " =~ " ${namespace} " ]]; then
            info "Skipping protected namespace: $namespace"
            continue
        fi
        
        log "Processing namespace: $namespace"
        
        # Delete Helm releases first
        delete_helm_releases "$namespace"
        
        # Delete the namespace
        delete_namespace "$namespace"
    done
    
    # Final cleanup status
    success "Cleanup completed successfully!"
    info "Protected namespaces were preserved: ${protected_namespaces[*]}"
    info "You can now run './deploy-applications.sh' to redeploy applications"
    
    # Print remaining resources
    echo -e "\n${CYAN}Current Cluster Status:${NC}"
    echo -e "${YELLOW}===========================================${NC}"
    kubectl get namespaces
    echo -e "${YELLOW}===========================================${NC}"
}

# Run the cleanup
cleanup 