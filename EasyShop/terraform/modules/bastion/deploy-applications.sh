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
    echo "║       EasyShop Deployment Script         ║"
    echo "║      Application Stack Installer         ║"
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

# Function to check if kubectl is available and connected
check_kubernetes_connection() {
    if ! command -v kubectl &>/dev/null; then
        error "kubectl is not installed"
        return 1
    fi

    if ! kubectl get nodes &>/dev/null; then
        error "Cannot connect to Kubernetes cluster"
        return 1
    fi
    success "Kubernetes connection verified"
}

# Function to check if helm is available
check_helm() {
    if ! command -v helm &>/dev/null; then
        error "helm is not installed"
        return 1
    fi
    success "Helm installation verified"
}

# Function to cleanup ingress-nginx resources
cleanup_ingress_nginx() {
    warn "Cleaning up existing ingress-nginx resources..."
    
    # Delete the deployment in default namespace
    kubectl delete deployment ingress-nginx-controller -n default 2>/dev/null || true
    
    # Delete the service in default namespace
    kubectl delete service ingress-nginx-controller -n default 2>/dev/null || true
    
    # Delete ClusterRole and ClusterRoleBinding
    kubectl delete clusterrole ingress-nginx 2>/dev/null || true
    kubectl delete clusterrolebinding ingress-nginx 2>/dev/null || true
    
    # Delete the namespace if it exists
    kubectl delete namespace ingress-nginx --timeout=60s 2>/dev/null || true
    
    # Wait for namespace deletion if it exists
    if kubectl get namespace ingress-nginx &>/dev/null; then
        info "Waiting for ingress-nginx namespace deletion..."
        while kubectl get namespace ingress-nginx &>/dev/null; do
            sleep 2
        done
    fi
    
    # Delete any remaining Helm release
    helm uninstall ingress-nginx -n ingress-nginx 2>/dev/null || true
    helm uninstall ingress-nginx -n default 2>/dev/null || true
    
    success "Cleaned up ingress-nginx resources"
}

# Function to install Helm chart with cleanup
install_helm_chart() {
    local name=$1
    local repo_name=$2
    local repo_url=$3
    local chart=$4
    local namespace=$5
    shift 5
    local args=("$@")

    info "Starting installation of ${name}..."

    # Add Helm repository if not exists
    if ! helm repo list | grep -q "^$repo_name"; then
        log "Adding Helm repository: $repo_name"
        helm repo add "$repo_name" "$repo_url"
    fi

    # Update Helm repositories
    info "Updating Helm repositories..."
    helm repo update

    # Special handling for ingress-nginx
    if [ "$name" = "ingress-nginx" ]; then
        cleanup_ingress_nginx
    fi

    # Install the chart
    info "Installing $name in namespace $namespace..."
    if ! helm install "$name" "$repo_name/$chart" \
        --namespace "$namespace" \
        --create-namespace \
        "${args[@]}"; then
        error "Failed to install $name"
        return 1
    fi

    success "Successfully installed $name"
}

# Function to wait for ingress controller to be ready
wait_for_ingress_controller() {
    info "Waiting for ingress-nginx controller to be ready..."
    kubectl wait --namespace ingress-nginx \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=180s || return 1
    
    # Wait for admission webhook
    info "Waiting for admission webhook to be ready..."
    local retries=0
    local max_retries=30
    while ! kubectl get validatingwebhookconfigurations ingress-nginx-admission >/dev/null 2>&1; do
        if [ $retries -eq $max_retries ]; then
            error "Timeout waiting for admission webhook"
            return 1
        fi
        info "Waiting for admission webhook (attempt $((retries+1))/$max_retries)..."
        sleep 5
        retries=$((retries+1))
    done
    success "Ingress controller is ready"
}

# Function to wait for cert-manager to be ready
wait_for_cert_manager() {
    info "Waiting for cert-manager to be ready..."
    kubectl wait --namespace cert-manager \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/instance=cert-manager \
        --timeout=180s || return 1
    success "Cert-manager is ready"
}

# Main deployment function
main() {
    print_banner
    
    log "Starting EasyShop deployment..."

    # Check prerequisites
    info "Checking prerequisites..."
    check_kubernetes_connection || exit 1
    check_helm || exit 1

    # 1. Install cert-manager
    info "Installing Certificate Manager..."
    install_helm_chart "cert-manager" "jetstack" "https://charts.jetstack.io" "cert-manager" "cert-manager" \
        --version v1.13.0 \
        --set installCRDs=true \
        --wait

    # Create ClusterIssuer for self-signed certificates
    info "Creating ClusterIssuer for SSL certificates..."
    cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
EOF

    wait_for_cert_manager || exit 1

    # 2. Install ingress-nginx
    info "Installing NGINX Ingress Controller..."
    install_helm_chart "ingress-nginx" "ingress-nginx" "https://kubernetes.github.io/ingress-nginx" "ingress-nginx" "ingress-nginx" \
        --set controller.service.type=LoadBalancer \
        --set controller.metrics.enabled=true \
        --set controller.podAnnotations."prometheus\.io/scrape"="true" \
        --set controller.podAnnotations."prometheus\.io/port"="10254" \
        --set controller.extraArgs.enable-ssl-passthrough="" \
        --wait

    wait_for_ingress_controller || exit 1

    # 3. Install ArgoCD
    info "Installing ArgoCD..."
    install_helm_chart "argocd" "argo" "https://argoproj.github.io/argo-helm" "argo-cd" "argocd" \
        --set server.ingress.enabled=false \
        --set server.extraArgs[0]="--insecure" \
        --set server.certificate.enabled=true \
        --set server.certificate.domain=argocd.letsdeployit.com \
        --set server.certificate.secretName=argocd-server-tls \
        --set server.certificate.issuer.name=selfsigned-issuer \
        --set server.certificate.issuer.kind=ClusterIssuer \
        --set server.certificate.issuer.group="" \
        --set server.service.type=ClusterIP \
        --set configs.params."server\.insecure"=true \
        --wait

    # Create Certificate for ArgoCD
    info "Creating SSL certificate for ArgoCD..."
    cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: argocd-server-tls
  namespace: argocd
spec:
  secretName: argocd-server-tls
  dnsNames:
  - argocd.letsdeployit.com
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
  commonName: argocd.letsdeployit.com
EOF

    # Apply custom ingress
    info "Applying ArgoCD custom ingress..."
    kubectl apply -f ../../../kubernetes/argocd/ingress.yaml

    # Wait for ArgoCD to be ready
    info "Waiting for ArgoCD to be ready..."
    kubectl wait --namespace argocd \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/name=argocd-server \
        --timeout=180s || warn "ArgoCD server pod not ready, but continuing..."

    # Get ArgoCD admin password
    info "Retrieving ArgoCD admin password..."
    ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

    # Print ArgoCD access information
    success "ArgoCD installation completed!"
    echo -e "\n${CYAN}ArgoCD Access Information:${NC}"
    echo -e "${YELLOW}=======================================================${NC}"
    echo -e "1. Through domain (requires DNS setup):"
    echo -e "   URL: ${GREEN}https://argocd.letsdeployit.com${NC}"
    echo -e "2. Through port-forward (recommended for testing):"
    echo -e "   Run: ${GREEN}kubectl port-forward svc/argocd-server -n argocd 8080:443${NC}"
    echo -e "   Then open: ${GREEN}https://localhost:8080${NC}"
    echo -e "\nCredentials:"
    echo -e "   Username: ${GREEN}admin${NC}"
    echo -e "   Password: ${GREEN}${ARGOCD_PASSWORD}${NC}"
    echo -e "${YELLOW}=======================================================${NC}"

    # Add note about certificate
    info "Note about SSL certificate:"
    echo -e "The SSL certificate is self-signed. You will see a browser warning."
    echo -e "This is expected and safe for development/testing environments."
    echo -e "For production, replace 'selfsigned-issuer' with a proper certificate issuer."

    # 4. Install Prometheus and Grafana
    info "Installing Prometheus and Grafana..."
    install_helm_chart "prometheus" "prometheus-community" "https://prometheus-community.github.io/helm-charts" "kube-prometheus-stack" "monitoring" \
        --set grafana.enabled=true \
        --set grafana.adminPassword=admin \
        --set grafana.ingress.enabled=true \
        --set grafana.ingress.ingressClassName=nginx \
        --set grafana.ingress.annotations."nginx\.ingress\.kubernetes\.io/ssl-redirect"=\"true\" \
        --set grafana.ingress.hosts[0]=grafana.letsdeployit.com \
        --set grafana.ingress.tls[0].hosts[0]=grafana.letsdeployit.com \
        --set grafana.ingress.tls[0].secretName=grafana-tls \
        --set grafana.resources.requests.cpu=100m \
        --set grafana.resources.requests.memory=128Mi \
        --set grafana.resources.limits.cpu=200m \
        --set grafana.resources.limits.memory=256Mi \
        --set prometheus.enabled=true \
        --set prometheus.ingress.enabled=true \
        --set prometheus.ingress.ingressClassName=nginx \
        --set prometheus.ingress.hosts[0]=prometheus.letsdeployit.com \
        --set prometheus.ingress.tls[0].hosts[0]=prometheus.letsdeployit.com \
        --set prometheus.ingress.tls[0].secretName=prometheus-tls \
        --set prometheus.prometheusSpec.retention=5d \
        --set prometheus.prometheusSpec.resources.requests.cpu=200m \
        --set prometheus.prometheusSpec.resources.requests.memory=512Mi \
        --set prometheus.prometheusSpec.resources.limits.cpu=500m \
        --set prometheus.prometheusSpec.resources.limits.memory=1Gi \
        --set defaultRules.create=true \
        --set defaultRules.rules.general=true \
        --set defaultRules.rules.k8s=true \
        --set defaultRules.rules.node=true \
        --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
        --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
        --wait

    # Wait for Prometheus and Grafana to be ready
    info "Waiting for Prometheus and Grafana to be ready..."
    kubectl wait --namespace monitoring \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/name=grafana \
        --timeout=180s || warn "Grafana pod not ready, but continuing..."
    
    # Get and display Grafana admin password
    info "Retrieving Grafana admin password..."
    GRAFANA_PASSWORD=$(kubectl get secret -n monitoring prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 -d)
    
    # Print access information
    success "Prometheus and Grafana installation completed!"
    info "Access Information:"
    echo -e "\n${CYAN}Grafana Access:${NC}"
    echo -e "${YELLOW}=======================================================${NC}"
    echo -e "1. Through domain (if configured):"
    echo -e "   URL: ${GREEN}https://grafana.letsdeployit.com${NC}"
    echo -e "2. Through port-forward (recommended for testing):"
    echo -e "   Run: ${GREEN}kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80${NC}"
    echo -e "   Then open: ${GREEN}http://localhost:3000${NC}"
    echo -e "   Username: ${GREEN}admin${NC}"
    echo -e "   Password: ${GREEN}${GRAFANA_PASSWORD}${NC}"
    
    echo -e "\n${CYAN}Prometheus Access:${NC}"
    echo -e "${YELLOW}=======================================================${NC}"
    echo -e "1. Through domain (if configured):"
    echo -e "   URL: ${GREEN}https://prometheus.letsdeployit.com${NC}"
    echo -e "2. Through port-forward (recommended for testing):"
    echo -e "   Run: ${GREEN}kubectl port-forward -n monitoring svc/prometheus-prometheus 9090:9090${NC}"
    echo -e "   Then open: ${GREEN}http://localhost:9090${NC}"
    echo -e "${YELLOW}=======================================================${NC}"

    # Get access information
    info "Getting access information..."
    
    # Get ingress hostname (with error handling)
    INGRESS_HOSTNAME=$(kubectl get service -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "Not available yet")
    
    # Print access information
    success "Deployment completed successfully! 🚀"
    echo -e "\n${CYAN}Access Information${NC}"
    echo -e "${YELLOW}=======================================================${NC}"
    echo -e "${BLUE}ArgoCD:${NC}"
    echo -e "  URL: ${GREEN}https://argocd.letsdeployit.com${NC}"
    echo -e "  Username: ${GREEN}admin${NC}"
    echo -e "  Password: ${GREEN}$ARGOCD_PASSWORD${NC}"
    echo -e "  Local Access: ${GREEN}kubectl port-forward -n argocd svc/argocd-server 8080:443${NC}"
    echo -e "\n${BLUE}Grafana:${NC}"
    echo -e "  URL: ${GREEN}https://grafana.letsdeployit.com${NC}"
    echo -e "  Username: ${GREEN}admin${NC}"
    echo -e "  Password: ${GREEN}${GRAFANA_PASSWORD}${NC}"
    echo -e "  Local Access: ${GREEN}kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80${NC}"
    echo -e "\n${BLUE}Load Balancer:${NC}"
    echo -e "  Hostname: ${GREEN}$INGRESS_HOSTNAME${NC}"
    echo -e "${YELLOW}=======================================================${NC}"

    info "To use local access (if domain is not configured):"
    echo -e "1. Run: ${GREEN}kubectl port-forward -n argocd svc/argocd-server 8080:443${NC}"
    echo -e "2. Open: ${GREEN}https://localhost:8080${NC}"
    echo -e "3. Login with the credentials shown above"
}

# Run main function
main 