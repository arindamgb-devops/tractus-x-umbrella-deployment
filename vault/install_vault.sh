#!/bin/bash
set -euo pipefail

NAMESPACE="tractus-x"
RELEASE_NAME="vault"

# Check if Helm is installed
if ! command -v helm &> /dev/null; then
  echo "❌ Helm not found. Please install Helm first."
  exit 1
fi

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
  echo "❌ kubectl not found. Please install kubectl first."
  exit 1
fi

# ----------------------------
# 1️⃣ Create namespace if it doesn't exist
# ----------------------------
if ! kubectl get ns "$NAMESPACE" &> /dev/null; then
  echo "➡ Creating namespace $NAMESPACE..."
  kubectl create ns "$NAMESPACE"
fi

# ----------------------------
# 2️⃣ Add HashiCorp repo and update
# ----------------------------
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# ----------------------------
# 3️⃣ Install or upgrade Vault
# ----------------------------
echo "➡ Installing/upgrading Vault..."
helm upgrade --install "$RELEASE_NAME" hashicorp/vault \
  -n "$NAMESPACE" \
  -f vault-values.yaml

# ----------------------------
# 4️⃣ Wait for Vault pods to be ready
# ----------------------------
echo "➡ Waiting for Vault pods to be ready..."
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=vault -n "$NAMESPACE" --timeout=120s

# ----------------------------
# 5️⃣ Apply Ingress YAML
# ----------------------------
echo "➡ Applying Ingress manifest..."
kubectl apply -f vault-ingress.yaml -n "$NAMESPACE"

# ----------------------------
# 6️⃣ Show status and instructions
# ----------------------------
echo "✔ Vault installation complete!"
kubectl get pods -n "$NAMESPACE"
kubectl get svc -n "$NAMESPACE"
kubectl get ingress -n "$NAMESPACE"

echo
echo "Access Vault UI at: http://vault.tx.test"
echo "Root token: root (dev mode)"

