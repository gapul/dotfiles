{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.dotfiles.automation.kubernetes;
in
{
  options.dotfiles.automation.kubernetes = {
    enable = mkEnableOption "Kubernetes environment management";
    
    clusterManagement = mkOption {
      type = types.bool;
      default = true;
      description = "Enable cluster management tools";
    };
    
    helmSupport = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Helm package manager";
    };
    
    kustomizeSupport = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Kustomize configuration management";
    };
    
    argocdSupport = mkOption {
      type = types.bool;
      default = false;
      description = "Enable ArgoCD GitOps support";
    };
    
    istioSupport = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Istio service mesh tools";
    };
    
    monitoringStack = mkOption {
      type = types.bool;
      default = true;
      description = "Enable monitoring stack (Prometheus, Grafana)";
    };
    
    loggingStack = mkOption {
      type = types.bool;
      default = true;
      description = "Enable logging stack (ELK, Loki)";
    };
    
    securityTools = mkOption {
      type = types.bool;
      default = true;
      description = "Enable security scanning and policy tools";
    };
    
    developmentTools = mkOption {
      type = types.bool;
      default = true;
      description = "Enable development and debugging tools";
    };
    
    multiClusterSupport = mkOption {
      type = types.bool;
      default = false;
      description = "Enable multi-cluster management";
    };
  };

  config = mkIf cfg.enable {
    # Core Kubernetes tools
    home-manager.users.yuki.home.packages = with pkgs; [
      # Essential cluster tools
      kubectl
      kubectx  # includes both kubectx and kubens commands
      k9s
      stern
      
      # Configuration management
    ] ++ optionals cfg.kustomizeSupport [
      kustomize
      kustomize-sops
    ] ++ optionals cfg.helmSupport [
      kubernetes-helm
      helmfile
      helm-docs
      kubernetes-helmPlugins.helm-secrets
    ] ++ optionals cfg.clusterManagement [
      # Cluster management
      kind
      minikube
      k3d
      
      # Node and resource management
      kubectl-node-shell
      kubectl-tree
      kubectl-view-allocations
    ] ++ optionals (cfg.clusterManagement && pkgs.stdenv.isLinux) [
      # Linux-only cluster management tools
      k3s
    ] ++ optionals cfg.argocdSupport [
      argocd
      argo-rollouts
    ] ++ optionals cfg.istioSupport [
      istioctl
    ] ++ optionals cfg.monitoringStack [
      prometheus
      grafana
      prometheus-alertmanager
    ] ++ optionals cfg.securityTools [
      # Security and policy
      trivy
      # Note: Some packages may not be available in nixpkgs for Darwin
    ] ++ optionals cfg.developmentTools [
      # Development and debugging
      skaffold
      dive  # Container image analysis
      # Note: Some kubectl plugins may not be available in nixpkgs for Darwin
    ] ++ optionals cfg.multiClusterSupport [
      # Multi-cluster tools
      fluxcd
      linkerd
    ];

    # Kubectl configuration
    home-manager.users.yuki.home.file.".kube/config.template" = {
      text = ''
        # Kubernetes configuration template
        # Copy this to ~/.kube/config and customize for your clusters
        
        apiVersion: v1
        kind: Config
        preferences: {}
        
        clusters:
        - cluster:
            certificate-authority-data: <CA_DATA>
            server: https://kubernetes.default.svc
          name: default-cluster
        
        contexts:
        - context:
            cluster: default-cluster
            user: default-user
            namespace: default
          name: default-context
        
        current-context: default-context
        
        users:
        - name: default-user
          user:
            token: <USER_TOKEN>
      '';
    };

    # K9s configuration
    home-manager.users.yuki.home.file.".config/k9s/config.yml" = mkIf (config ? home-manager) {
      text = ''
        k9s:
          refreshRate: 2
          maxConnRetry: 5
          readOnly: false
          noExitOnCtrlC: false
          ui:
            enableMouse: false
            headless: false
            logoless: false
            crumbsless: false
            reactive: false
            noIcons: false
          skipLatestRevCheck: false
          disablePodCounting: false
          shellPod:
            image: busybox:1.35.0
            namespace: default
            limits:
              cpu: 100m
              memory: 100Mi
          imageScans:
            enable: false
            exclusions:
              namespaces: []
              labels: {}
          logger:
            tail: 100
            buffer: 5000
            sinceSeconds: -1
            fullScreenLogs: false
            textWrap: false
            showTime: false
          thresholds:
            cpu:
              critical: 90
              warn: 70
            memory:
              critical: 90
              warn: 70
      '';
    };

    # Shell aliases for Kubernetes
    home-manager.users.yuki.programs.zsh.shellAliases = {
      # Basic kubectl shortcuts
      k = "kubectl";
      kgp = "kubectl get pods";
      kgs = "kubectl get services";
      kgd = "kubectl get deployments";
      kgn = "kubectl get nodes";
      kgi = "kubectl get ingress";
      kgpv = "kubectl get pv";
      kgpvc = "kubectl get pvc";
      
      # Describe resources
      kdp = "kubectl describe pod";
      kds = "kubectl describe service";
      kdd = "kubectl describe deployment";
      kdn = "kubectl describe node";
      
      # Logs and debugging
      kl = "kubectl logs";
      klf = "kubectl logs -f";
      kex = "kubectl exec -it";
      
      # Context and namespace management
      kctx = "kubectx";
      kns = "kubens";
      
      # Helm shortcuts
      h = mkIf cfg.helmSupport "helm";
      hi = mkIf cfg.helmSupport "helm install";
      hu = mkIf cfg.helmSupport "helm upgrade";
      hd = mkIf cfg.helmSupport "helm delete";
      hl = mkIf cfg.helmSupport "helm list";
      hs = mkIf cfg.helmSupport "helm search";
      
      # Development tools
      sk = mkIf cfg.developmentTools "skaffold";
      skd = mkIf cfg.developmentTools "skaffold dev";
      skr = mkIf cfg.developmentTools "skaffold run";
    };

    # Kubernetes cluster management script
    home-manager.users.yuki.home.file."bin/k8s-cluster" = mkIf (config ? home-manager) {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # Kubernetes Cluster Management
        set -euo pipefail
        
        COMMAND="$1"
        CLUSTER_NAME="''${2:-dev-cluster}"
        
        # Colors for output
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[1;33m'
        BLUE='\033[0;34m'
        NC='\033[0m'
        
        log_info() { echo -e "''${BLUE}ℹ️  $1''${NC}"; }
        log_success() { echo -e "''${GREEN}✅ $1''${NC}"; }
        log_warning() { echo -e "''${YELLOW}⚠️  $1''${NC}"; }
        log_error() { echo -e "''${RED}❌ $1''${NC}"; }
        
        case "$COMMAND" in
          "create-local")
            log_info "Creating local Kubernetes cluster: $CLUSTER_NAME"
            
            # Choose cluster type based on availability
            if command -v kind &> /dev/null; then
              log_info "Using kind for cluster creation"
              
              cat > kind-config.yaml << 'EOF'
        kind: Cluster
        apiVersion: kind.x-k8s.io/v1alpha4
        name: {{CLUSTER_NAME}}
        networking:
          apiServerAddress: "127.0.0.1"
          apiServerPort: 6443
        nodes:
        - role: control-plane
          kubeadmConfigPatches:
          - |
            kind: InitConfiguration
            nodeRegistration:
              kubeletExtraArgs:
                node-labels: "ingress-ready=true"
          extraPortMappings:
          - containerPort: 80
            hostPort: 80
            protocol: TCP
          - containerPort: 443
            hostPort: 443
            protocol: TCP
        - role: worker
        - role: worker
        EOF
              
              sed -i.bak "s/{{CLUSTER_NAME}}/$CLUSTER_NAME/g" kind-config.yaml
              rm -f kind-config.yaml.bak
              
              kind create cluster --config kind-config.yaml
              
            elif command -v k3d &> /dev/null; then
              log_info "Using k3d for cluster creation"
              k3d cluster create "$CLUSTER_NAME" \
                --port "8080:80@loadbalancer" \
                --port "8443:443@loadbalancer" \
                --agents 2
                
            elif command -v minikube &> /dev/null; then
              log_info "Using minikube for cluster creation"
              minikube start -p "$CLUSTER_NAME" \
                --driver=docker \
                --cpus=2 \
                --memory=4g \
                --disk-size=20g
            else
              log_error "No local Kubernetes cluster tool found (kind, k3d, minikube)"
              exit 1
            fi
            
            log_success "Local cluster '$CLUSTER_NAME' created successfully"
            ;;
            
          "delete-local")
            log_info "Deleting local cluster: $CLUSTER_NAME"
            
            if command -v kind &> /dev/null && kind get clusters | grep -q "$CLUSTER_NAME"; then
              kind delete cluster --name "$CLUSTER_NAME"
            elif command -v k3d &> /dev/null && k3d cluster list | grep -q "$CLUSTER_NAME"; then
              k3d cluster delete "$CLUSTER_NAME"
            elif command -v minikube &> /dev/null && minikube profile list | grep -q "$CLUSTER_NAME"; then
              minikube delete -p "$CLUSTER_NAME"
            else
              log_warning "Cluster '$CLUSTER_NAME' not found or no management tool available"
            fi
            
            log_success "Cluster '$CLUSTER_NAME' deleted"
            ;;
            
          "status")
            log_info "Kubernetes Cluster Status"
            echo "=========================="
            
            # Current context
            echo "🎯 Current Context: $(kubectl config current-context 2>/dev/null || echo 'None')"
            
            # Cluster info
            if kubectl cluster-info &> /dev/null; then
              echo "🏃 Cluster: Running"
              echo "📋 Version: $(kubectl version --short --client 2>/dev/null | head -1)"
              
              # Node status
              echo ""
              echo "📊 Nodes:"
              kubectl get nodes --no-headers 2>/dev/null | while read line; do
                echo "  $line"
              done
              
              # Namespace summary
              echo ""
              echo "📂 Namespaces:"
              kubectl get namespaces --no-headers 2>/dev/null | wc -l | xargs echo "  Total:"
              
              # Resource usage
              if command -v kubectl-view-allocations &> /dev/null; then
                echo ""
                echo "💾 Resource Allocation:"
                kubectl-view-allocations | head -10
              fi
            else
              echo "❌ Cluster: Not accessible"
            fi
            ;;
            
          "install-tools")
            log_info "Installing essential Kubernetes tools"
            
            # Install nginx-ingress for local clusters
            if kubectl get nodes &> /dev/null; then
              if ! kubectl get namespace ingress-nginx &> /dev/null; then
                log_info "Installing NGINX Ingress Controller"
                kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
                
                log_info "Waiting for ingress controller to be ready..."
                kubectl wait --namespace ingress-nginx \
                  --for=condition=ready pod \
                  --selector=app.kubernetes.io/component=controller \
                  --timeout=90s
              fi
              
              # Install metrics-server for local development
              if ! kubectl get deployment metrics-server -n kube-system &> /dev/null; then
                log_info "Installing metrics-server"
                kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
                
                # Patch for local development
                kubectl patch deployment metrics-server -n kube-system --type='json' \
                  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
              fi
              
              ${if cfg.monitoringStack then ''
                # Install monitoring stack
                if ! kubectl get namespace monitoring &> /dev/null; then
                  log_info "Setting up monitoring namespace"
                  kubectl create namespace monitoring
                fi
              '' else ""}
              
              log_success "Essential tools installed"
            else
              log_error "No accessible Kubernetes cluster found"
              exit 1
            fi
            ;;
            
          "health-check")
            log_info "Kubernetes Health Check"
            echo "======================="
            
            ISSUES=0
            
            # Check kubectl connectivity
            if kubectl cluster-info &> /dev/null; then
              echo "✅ kubectl: Connected"
            else
              echo "❌ kubectl: Cannot connect to cluster"
              ((ISSUES++))
            fi
            
            # Check nodes
            if kubectl get nodes --no-headers 2>/dev/null | grep -q Ready; then
              echo "✅ Nodes: Ready"
            else
              echo "❌ Nodes: Issues detected"
              ((ISSUES++))
            fi
            
            # Check system pods
            if kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -v Running | grep -v Completed; then
              echo "⚠️  System Pods: Some pods not running"
            else
              echo "✅ System Pods: All running"
            fi
            
            # Check DNS
            if kubectl run test-pod --image=busybox --rm -it --restart=Never -- nslookup kubernetes.default &> /dev/null; then
              echo "✅ DNS: Working"
            else
              echo "⚠️  DNS: Issues detected"
            fi
            
            # Security checks
            ${if cfg.securityTools then ''
              if command -v kube-score &> /dev/null; then
                echo ""
                echo "🔒 Security Scan:"
                kubectl get deployments --all-namespaces -o yaml | kube-score score - | head -10
              fi
            '' else ""}
            
            echo ""
            if [[ $ISSUES -eq 0 ]]; then
              echo "✅ Cluster health: Good"
            else
              echo "⚠️  Cluster health: $ISSUES issues found"
            fi
            ;;
            
          "logs")
            local namespace="''${3:-default}"
            local resource="''${4:-}"
            
            if [[ -n "$resource" ]]; then
              log_info "Streaming logs for $resource in namespace $namespace"
              stern "$resource" -n "$namespace"
            else
              log_info "Streaming logs for all resources in namespace $namespace"
              stern ".*" -n "$namespace"
            fi
            ;;
            
          "debug")
            local pod_name="''${3:-}"
            if [[ -z "$pod_name" ]]; then
              log_error "Pod name required for debugging"
              exit 1
            fi
            
            log_info "Starting debug session for pod: $pod_name"
            
            # Get pod info
            kubectl describe pod "$pod_name"
            
            # Check logs
            echo ""
            log_info "Recent logs:"
            kubectl logs "$pod_name" --tail=50
            
            # Interactive shell if possible
            echo ""
            log_info "Attempting to start shell..."
            kubectl exec -it "$pod_name" -- /bin/sh || \
            kubectl exec -it "$pod_name" -- /bin/bash || \
            log_warning "Could not start interactive shell"
            ;;
            
          *)
            echo "Usage: k8s-cluster <command> [cluster-name] [additional-args]"
            echo ""
            echo "Commands:"
            echo "  create-local [name]    Create local cluster"
            echo "  delete-local [name]    Delete local cluster"
            echo "  status                 Show cluster status"
            echo "  install-tools          Install essential tools"
            echo "  health-check           Perform health check"
            echo "  logs [ns] [resource]   Stream logs"
            echo "  debug <pod>            Debug pod"
            echo ""
            exit 1
            ;;
        esac
      '';
    };

    # Kubernetes manifest generator
    home-manager.users.yuki.home.file."bin/k8s-generate" = mkIf (config ? home-manager) {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # Kubernetes Manifest Generator
        set -euo pipefail
        
        RESOURCE_TYPE="$1"
        RESOURCE_NAME="$2"
        NAMESPACE="''${3:-default}"
        
        case "$RESOURCE_TYPE" in
          "deployment")
            cat << EOF
        apiVersion: apps/v1
        kind: Deployment
        metadata:
          name: $RESOURCE_NAME
          namespace: $NAMESPACE
          labels:
            app: $RESOURCE_NAME
        spec:
          replicas: 3
          selector:
            matchLabels:
              app: $RESOURCE_NAME
          template:
            metadata:
              labels:
                app: $RESOURCE_NAME
            spec:
              containers:
              - name: $RESOURCE_NAME
                image: nginx:1.21
                ports:
                - containerPort: 80
                resources:
                  requests:
                    memory: "64Mi"
                    cpu: "250m"
                  limits:
                    memory: "128Mi"
                    cpu: "500m"
                livenessProbe:
                  httpGet:
                    path: /
                    port: 80
                  initialDelaySeconds: 30
                  periodSeconds: 10
                readinessProbe:
                  httpGet:
                    path: /
                    port: 80
                  initialDelaySeconds: 5
                  periodSeconds: 5
        EOF
            ;;
            
          "service")
            cat << EOF
        apiVersion: v1
        kind: Service
        metadata:
          name: $RESOURCE_NAME
          namespace: $NAMESPACE
          labels:
            app: $RESOURCE_NAME
        spec:
          selector:
            app: $RESOURCE_NAME
          ports:
          - protocol: TCP
            port: 80
            targetPort: 80
          type: ClusterIP
        EOF
            ;;
            
          "ingress")
            cat << EOF
        apiVersion: networking.k8s.io/v1
        kind: Ingress
        metadata:
          name: $RESOURCE_NAME
          namespace: $NAMESPACE
          annotations:
            nginx.ingress.kubernetes.io/rewrite-target: /
        spec:
          ingressClassName: nginx
          rules:
          - host: $RESOURCE_NAME.local
            http:
              paths:
              - path: /
                pathType: Prefix
                backend:
                  service:
                    name: $RESOURCE_NAME
                    port:
                      number: 80
        EOF
            ;;
            
          "configmap")
            cat << EOF
        apiVersion: v1
        kind: ConfigMap
        metadata:
          name: $RESOURCE_NAME
          namespace: $NAMESPACE
        data:
          config.yaml: |
            # Configuration for $RESOURCE_NAME
            app:
              name: $RESOURCE_NAME
              version: "1.0.0"
              debug: false
        EOF
            ;;
            
          "secret")
            cat << EOF
        apiVersion: v1
        kind: Secret
        metadata:
          name: $RESOURCE_NAME
          namespace: $NAMESPACE
        type: Opaque
        data:
          # Base64 encoded secrets
          username: $(echo -n "admin" | base64)
          password: $(echo -n "changeme" | base64)
        EOF
            ;;
            
          *)
            echo "Supported resource types: deployment, service, ingress, configmap, secret"
            exit 1
            ;;
        esac
      '';
    };

    # Shell functions for Kubernetes management
    home-manager.users.yuki.programs.zsh.initExtra = mkIf (config ? home-manager) ''
      # Quick cluster context switching
      kctx-quick() {
        local contexts=($(kubectl config get-contexts -o name))
        if [[ ''${#contexts[@]} -eq 0 ]]; then
          echo "No Kubernetes contexts found"
          return 1
        fi
        
        echo "Available contexts:"
        for i in "''${!contexts[@]}"; do
          echo "$((i+1)). ''${contexts[i]}"
        done
        
        read -p "Select context (1-''${#contexts[@]}): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ''${#contexts[@]} ]]; then
          kubectx "''${contexts[$((choice-1))]}"
        fi
      }
      
      # Quick namespace switching
      kns-quick() {
        local namespaces=($(kubectl get namespaces -o name | cut -d/ -f2))
        if [[ ''${#namespaces[@]} -eq 0 ]]; then
          echo "No namespaces found"
          return 1
        fi
        
        echo "Available namespaces:"
        for i in "''${!namespaces[@]}"; do
          echo "$((i+1)). ''${namespaces[i]}"
        done
        
        read -p "Select namespace (1-''${#namespaces[@]}): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ''${#namespaces[@]} ]]; then
          kubens "''${namespaces[$((choice-1))]}"
        fi
      }
      
      # Pod shell access
      kshell() {
        local pod="$1"
        local container="''${2:-}"
        
        if [[ -n "$container" ]]; then
          kubectl exec -it "$pod" -c "$container" -- /bin/bash || \
          kubectl exec -it "$pod" -c "$container" -- /bin/sh
        else
          kubectl exec -it "$pod" -- /bin/bash || \
          kubectl exec -it "$pod" -- /bin/sh
        fi
      }
      
      # Resource monitoring
      kwatch() {
        local resource="''${1:-pods}"
        watch -n 2 "kubectl get $resource"
      }
      
      # Quick resource deletion with confirmation
      kdel() {
        local resource="$1"
        local name="$2"
        
        echo "⚠️  About to delete $resource/$name"
        read -p "Are you sure? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
          kubectl delete "$resource" "$name"
        else
          echo "Cancelled"
        fi
      }
    '';
  };
}