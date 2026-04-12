#!/bin/bash

# Exit on error
set -e

# Colors for output
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
    echo "║       EasyShop Application Deploy        ║"
    echo "║          GitOps with ArgoCD              ║"
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

# Set project root directory
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)"

# Sync Git repository
sync_git_repo() {
    info "Synchronizing Git repository..."
    cd "${PROJECT_ROOT}"
    
    # Configure Git pull strategy
    git config pull.rebase false
    
    # Check if we have local changes
    if git status --porcelain | grep -q .; then
        warn "Local changes detected. Stashing changes..."
        git stash
    fi
    
    # Pull latest changes
    git pull origin tf-DevOps || {
        error "Failed to pull latest changes. Trying force reset..."
        git fetch origin
        git reset --hard origin/tf-DevOps
    }
    
    success "Repository synchronized successfully!"
}

# Create storage class for PVCs
setup_storage_class() {
    info "Setting up proper storage class for PVCs..."
    
    # Always use gp2 for AWS environments
    if ! kubectl get storageclass gp2 &>/dev/null; then
        info "Creating gp2 StorageClass..."
        kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp2
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
parameters:
  type: gp2
  fsType: ext4
reclaimPolicy: Delete
allowVolumeExpansion: true
EOF
    else
        info "StorageClass gp2 already exists, ensuring it's the default..."
    fi
    
    # Make it the default if no default exists
    if ! kubectl get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}' | grep -q .; then
        kubectl patch storageclass gp2 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
    fi
}

# Set up cluster autoscaler
setup_cluster_autoscaler() {
    info "Setting up Cluster Autoscaler..."
    
    # Get cluster name from context
    CLUSTER_NAME=$(kubectl config current-context | cut -d'/' -f2)
    
    # Check if already installed
    if kubectl get deployment -n kube-system cluster-autoscaler &>/dev/null; then
        info "Cluster Autoscaler already installed, updating configuration..."
        kubectl -n kube-system set env deployment/cluster-autoscaler CLUSTER_NAME=${CLUSTER_NAME}
    else
        info "Installing Cluster Autoscaler..."
        kubectl apply -f https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml
        
        # Update autoscaler with cluster name and AWS region
        sleep 5 # Wait for deployment to be created
        kubectl -n kube-system set env deployment/cluster-autoscaler CLUSTER_NAME=${CLUSTER_NAME}
        
        # Add proper annotations
        kubectl -n kube-system annotate deployment.apps/cluster-autoscaler cluster-autoscaler.kubernetes.io/safe-to-evict="false"
        
        # Restart the deployment to apply changes
        kubectl -n kube-system rollout restart deployment cluster-autoscaler
    fi
    
    info "Waiting for Cluster Autoscaler to be ready..."
    kubectl -n kube-system wait --for=condition=available deployment/cluster-autoscaler --timeout=60s || warn "Cluster Autoscaler not ready yet, but continuing..."
}

# Fix ingress TLS configuration
fix_ingress_tls() {
    info "Fixing ingress TLS configuration..."
    
    # Wait for cert-manager to be ready
    if kubectl get deployment -n cert-manager cert-manager &>/dev/null; then
        info "Waiting for cert-manager to be ready..."
        kubectl -n cert-manager wait --for=condition=available deployment/cert-manager --timeout=60s || warn "cert-manager not ready yet, but continuing..."
    fi
    
    # Apply certificate issuer if not exists
    if ! kubectl get clusterissuer selfsigned-issuer &>/dev/null; then
        info "Creating self-signed certificate issuer..."
        kubectl apply -f "${PROJECT_ROOT}/kubernetes/selfsigned-issuer.yaml"
        sleep 5
    fi
    
    # Delete any existing certificates and secrets to ensure clean recreation
    info "Cleaning up existing certificates..."
    kubectl delete certificate easyshop-tls -n easyshop --ignore-not-found=true
    kubectl delete secret easyshop-tls -n easyshop --ignore-not-found=true
    sleep 2
    
    # Apply our explicit certificate manifest
    info "Applying explicit certificate manifest..."
    kubectl apply -f "${PROJECT_ROOT}/kubernetes/easyshop-certificate.yaml"
    
    # Patch ingress with additional annotations for TLS
    info "Patching ingress with better TLS configuration..."
    kubectl patch ingress easyshop-ingress -n easyshop --type=merge -p '{"metadata":{"annotations":{"cert-manager.io/cluster-issuer":"selfsigned-issuer", "nginx.ingress.kubernetes.io/ssl-redirect":"true", "nginx.ingress.kubernetes.io/force-ssl-redirect":"true", "nginx.ingress.kubernetes.io/ssl-verify":"false", "nginx.ingress.kubernetes.io/hsts":"false"}}}' || warn "Could not patch ingress, it may not exist yet"
    
    # Wait for certificate to be issued
    info "Waiting for certificate to be issued..."
    for i in {1..30}; do
        CERT_READY=$(kubectl get certificate easyshop-tls -n easyshop -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
        if [ "$CERT_READY" == "True" ]; then
            success "Certificate successfully issued!"
            break
        fi
        info "Certificate not ready yet, waiting... ($i/30)"
        sleep 5
    done
}

# Fix ArgoCD resource tracking
fix_argocd_application() {
    info "Fixing ArgoCD resource tracking issues..."
    
    # Check if application exists
    if kubectl get application easyshop -n argocd &>/dev/null; then
        info "Temporarily disabling sync policy..."
        kubectl patch application easyshop -n argocd --type=merge -p '{"spec":{"syncPolicy":{"automated":{"prune":false,"selfHeal":false}}}}' || warn "Failed to patch application, might be first install"
        
        # Recreate application to clear any stale resource tracking
        info "Recreating ArgoCD application..."
        kubectl delete application easyshop -n argocd --ignore-not-found=true
        sleep 2
    fi
    
    # Apply fresh ArgoCD application
    info "Applying fresh ArgoCD application..."
    kubectl apply -f "${PROJECT_ROOT}/kubernetes/argocd/application.yaml"
    
    # Re-enable automated sync after a delay
    info "Waiting for application to be created..."
    sleep 10
    
    info "Re-enabling automated sync..."
    kubectl patch application easyshop -n argocd --type=merge -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}' || warn "Failed to re-enable sync, check ArgoCD dashboard"
}

# Clean up any problematic PVCs
cleanup_pvcs() {
    info "Cleaning up any problematic PVCs..."
    
    # Check for standalone mongodb-pvc that might conflict with StatefulSet's PVCs
    if kubectl get pvc mongodb-pvc -n easyshop &>/dev/null; then
        warn "Found standalone mongodb-pvc that may conflict with StatefulSet, deleting..."
        kubectl delete pvc mongodb-pvc -n easyshop
    fi
    
    # Check for any PVCs in bad state
    STUCK_PVCS=$(kubectl get pvc -n easyshop -o json | jq -r '.items[] | select(.status.phase=="Pending" or .status.phase=="Failed") | .metadata.name')
    if [ -n "$STUCK_PVCS" ]; then
        warn "Found stuck PVCs, deleting: $STUCK_PVCS"
        echo "$STUCK_PVCS" | xargs -I{} kubectl delete pvc {} -n easyshop
    fi
}

# Main function
main() {
    print_banner
    
    log "Starting EasyShop application deployment with ArgoCD..."
    
    # 0. Sync Git repository
    sync_git_repo
    
    # 1. Create the easyshop namespace first
    info "Creating easyshop namespace..."
    kubectl apply -f "${PROJECT_ROOT}/kubernetes/01-namespace.yaml"
    
    info "Waiting for namespace to be fully created..."
    sleep 5
    
    # 2. Set up proper storage class for PVCs
    setup_storage_class
    
    # 3. Set up cluster autoscaler
    setup_cluster_autoscaler
    
    # 4. Apply PriorityClass
    info "Applying PriorityClass for critical jobs..."
    kubectl apply -f "${PROJECT_ROOT}/kubernetes/00-priority-class.yaml"
    
    # 5. Apply the self-signed issuer for certificates
    info "Applying self-signed certificate issuer..."
    kubectl apply -f "${PROJECT_ROOT}/kubernetes/selfsigned-issuer.yaml"
    
    # 6. Fix ArgoCD application 
    fix_argocd_application
    
    # 7. Clean up any problematic PVCs
    cleanup_pvcs
    
    # 8. Scale down monitoring components to reduce resource conflicts
    info "Scaling down monitoring components to free up resources..."
    kubectl -n monitoring scale deployment --all --replicas=0 || warn "No monitoring deployments found, continuing..."
    
    # 9. Delete existing pending migration jobs if they exist
    info "Cleaning up any stuck migration jobs..."
    kubectl delete jobs --all -n easyshop --ignore-not-found=true
    
    # Wait to ensure jobs are fully deleted
    sleep 5
    
    # 10. Apply MongoDB StatefulSet directly to fix readiness probe
    info "Applying MongoDB StatefulSet with fixed readiness probe and reduced resources..."
    kubectl apply -f "${PROJECT_ROOT}/kubernetes/07-mongodb-statefulset.yaml"
    
    # 11. Wait for MongoDB to be ready - increased timeout to 5 minutes
    info "Waiting for MongoDB to become ready..."
    kubectl wait --for=condition=ready pod mongodb-0 -n easyshop --timeout=300s || {
        warn "MongoDB pod is not ready after 5 minutes, checking status..."
        kubectl describe pod mongodb-0 -n easyshop
        warn "Continuing with deployment anyway..."
    }
    
    # 12. Fix ingress TLS configuration
    fix_ingress_tls
    
    # 13. Apply migration job directly (not through ArgoCD)
    info "Applying migration job with scheduling priority..."
    JOB_NAME="easyshop-migration-$(date +%s)"
    cat "${PROJECT_ROOT}/kubernetes/12-migration-job.yaml" | \
        sed "s|name: easyshop-migration|name: ${JOB_NAME}|g" | \
        kubectl apply -f -
    
    # Add a label for easier management
    kubectl label job ${JOB_NAME} -n easyshop app=easyshop-migration
    
    info "Waiting for migration job to complete..."
    # Increased timeout to 5 minutes for migration job
    kubectl wait --for=condition=complete job/${JOB_NAME} -n easyshop --timeout=300s || {
        warn "Migration job not completed within timeout, checking logs..."
        POD_NAME=$(kubectl get pods -n easyshop -l job-name=${JOB_NAME} -o jsonpath='{.items[0].metadata.name}')
        if [ -n "$POD_NAME" ]; then
            kubectl logs ${POD_NAME} -n easyshop
        fi
        warn "Continuing with deployment..."
    }
    
    # 14. Wait for Application to sync
    info "Waiting for EasyShop application to sync..."
    kubectl wait --for=condition=ready pods -l app=easyshop -n easyshop --timeout=300s || warn "Not all EasyShop pods are ready yet, but continuing..."
    
    # 15. Get Ingress URL
    info "Getting EasyShop access URL..."
    EASYSHOP_URL=$(kubectl get ingress -n easyshop -o jsonpath='{.items[*].spec.rules[*].host}')
    
    # 16. Print success message
    success "EasyShop deployment initiated successfully!"
    echo -e "\n${CYAN}EasyShop Application Information${NC}"
    echo -e "${YELLOW}=======================================================${NC}"
    echo -e "Access URL: ${GREEN}https://${EASYSHOP_URL}${NC}"
    echo -e "ArgoCD Dashboard: ${GREEN}https://argocd.letsdeployit.com${NC}"
    echo -e "Grafana Dashboard: ${GREEN}https://grafana.letsdeployit.com${NC}"
    echo -e "${YELLOW}=======================================================${NC}"
    
    info "Note: It might take a few minutes for all resources to be fully deployed and ready."
    info "You can monitor the deployment in the ArgoCD dashboard."
    info "NOTE: Monitoring components were scaled down to save resources. Scale them up when needed."
    info "TIP: Accept the self-signed certificate in your browser to access the application."
    
    # Check final application status
    info "Checking final application status..."
    kubectl get pods -n easyshop
    kubectl get certificate -n easyshop
    kubectl get ingress -n easyshop
    kubectl get pvc -n easyshop
    
    # Add instructions for browser certificate acceptance
    echo -e "\n${YELLOW}IMPORTANT: Your application uses a self-signed certificate${NC}"
    echo -e "To access in Chrome/Edge: Click Advanced → Proceed to ${EASYSHOP_URL} (unsafe)"
    echo -e "To access in Firefox: Click Advanced → Accept Risk and Continue"
    echo -e "This warning appears because you're using a self-signed certificate for development."
}

# Run main function
main
