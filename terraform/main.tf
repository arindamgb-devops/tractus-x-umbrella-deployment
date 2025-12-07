terraform {
  required_version = ">= 1.0.0"

  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "null" {}

############################################
# 1) Minikube cluster
############################################
resource "null_resource" "minikube_cluster" {
  # Store profile name so destroy-time provisioner can use it via self.triggers
  triggers = {
    profile = var.minikube_profile
  }

  provisioner "local-exec" {
    # CREATE: start minikube
    command = <<EOT
set -e

echo ">>> Starting Minikube profile '${var.minikube_profile}' (if not already running)..."

minikube start \
  --memory=${var.minikube_memory_mb} \
  --cpus=${var.minikube_cpus} \
  -p ${var.minikube_profile} \
  --driver=docker

echo ">>> Switching current profile to '${var.minikube_profile}'..."
minikube profile ${var.minikube_profile}

echo ">>> Minikube status:"
minikube status -p ${var.minikube_profile}
EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<EOT
set -e

echo ">>> Deleting Minikube profile '${self.triggers.profile}'..."
minikube delete -p ${self.triggers.profile} || true
EOT
  }
}

############################################
# 2) Minikube addons
############################################
resource "null_resource" "minikube_addons" {
  depends_on = [null_resource.minikube_cluster]

  provisioner "local-exec" {
    command = <<EOT
set -e

PROFILE=${var.minikube_profile}

echo ">>> Enabling metrics-server addon..."
minikube addons enable metrics-server -p "$PROFILE"

echo ">>> Enabling dashboard addon..."
minikube addons enable dashboard -p "$PROFILE"

echo ">>> Enabling ingress addon..."
minikube addons enable ingress -p "$PROFILE"

echo ">>> Enabling ingress-dns addon..."
minikube addons enable ingress-dns -p "$PROFILE"

echo ">>> Addons status:"
minikube addons list -p "$PROFILE" | egrep 'metrics-server|dashboard|ingress' || true
EOT
  }
}

############################################
# 3) Wait for ingress controller to be ready
############################################
resource "null_resource" "ingress_controller_ready" {
  depends_on = [null_resource.minikube_addons]

  provisioner "local-exec" {
    command = <<EOT
set -e

echo ">>> Waiting for ingress-nginx controller to become ready..."

NS="ingress-nginx"
DEPLOY="ingress-nginx-controller"

kubectl -n "$NS" rollout status deployment/"$DEPLOY" --timeout=180s

echo ">>> Ingress controller is ready."
EOT
  }
}

############################################
# 4) Argo CD via Helm
############################################
resource "null_resource" "argocd" {
  depends_on = [null_resource.minikube_addons]

  triggers = {
    namespace = var.argocd_namespace
    release   = var.argocd_release_name
  }

  provisioner "local-exec" {
    # CREATE
    command = <<EOT
set -e

echo ">>> Adding Argo Helm repo..."
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update

echo ">>> Creating namespace '${var.argocd_namespace}' (if not exists)..."
kubectl get ns ${var.argocd_namespace} >/dev/null 2>&1 || kubectl create namespace ${var.argocd_namespace}

echo ">>> Installing / upgrading Argo CD release '${var.argocd_release_name}'..."
helm upgrade --install ${var.argocd_release_name} argo/argo-cd \
  --namespace ${var.argocd_namespace} \
  -f ${var.argocd_values_file}

echo ">>> Argo CD pods:"
kubectl get pods -n ${var.argocd_namespace}
EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<EOT
set -e

echo ">>> Uninstalling Argo CD..."
helm uninstall ${self.triggers.release} -n ${self.triggers.namespace} || true

echo ">>> Deleting Argo CD namespace..."
kubectl delete ns ${self.triggers.namespace} --ignore-not-found=true
EOT
  }
}

############################################
# 5) Apply tx-gitops.yaml after ArgoCD
############################################
resource "null_resource" "argocd_gitops_app" {
  depends_on = [null_resource.argocd]

  triggers = {
    tx_gitops_file = var.tx_gitops_file
  }

  provisioner "local-exec" {
    # CREATE
    command = <<EOT
set -e

echo ">>> Applying GitOps manifest '${var.tx_gitops_file}'..."
#kubectl apply -f ${var.tx_gitops_file}

echo ">>> GitOps resources created (filtered by tx):"
kubectl get all --all-namespaces | grep tx || true
EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<EOT
set -e

echo ">>> Deleting GitOps resources from '${self.triggers.tx_gitops_file}'..."
kubectl delete -f ${self.triggers.tx_gitops_file} --ignore-not-found=true || true
EOT
  }
}

############################################
# 6) Vault via Helm + ingress
############################################
resource "null_resource" "vault" {
  depends_on = [
    null_resource.minikube_addons,
    null_resource.ingress_controller_ready
  ]

  triggers = {
    namespace = var.vault_namespace
    release   = var.vault_release_name
  }

  provisioner "local-exec" {
    # CREATE
    command = <<EOT
set -e

echo ">>> Adding HashiCorp Helm repo..."
helm repo add hashicorp https://helm.releases.hashicorp.com >/dev/null 2>&1 || true
helm repo update

echo ">>> Creating namespace '${var.vault_namespace}' (if not exists)..."
kubectl get ns ${var.vault_namespace} >/dev/null 2>&1 || kubectl create namespace ${var.vault_namespace}

echo ">>> Installing / upgrading Vault release '${var.vault_release_name}'..."
helm upgrade --install ${var.vault_release_name} hashicorp/vault \
  --namespace ${var.vault_namespace} \
  -f ${var.vault_values_file}

echo ">>> Applying Vault ingress from '${var.vault_ingress_file}'..."
kubectl apply -f ${var.vault_ingress_file} -n ${var.vault_namespace}

echo ">>> Vault pods:"
kubectl get pods -n ${var.vault_namespace}
EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<EOT
set -e

echo ">>> Uninstalling Vault..."
helm uninstall ${self.triggers.release} -n ${self.triggers.namespace} || true

echo ">>> Deleting Vault namespace..."
kubectl delete ns ${self.triggers.namespace} --ignore-not-found=true
EOT
  }
}

