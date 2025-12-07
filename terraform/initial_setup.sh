#!/usr/bin/env bash
set -euo pipefail

#############################################
# Config
#############################################
# Change this if you want a different user
NEW_USER="arindam"

#############################################
# Sanity checks
#############################################
if [[ "$EUID" -ne 0 ]]; then
  echo "❌ This script must be run as root (use: sudo ./initial_setup.sh)"
  exit 1
fi

if ! command -v apt >/dev/null 2>&1; then
  echo "❌ This script is written for Debian/Ubuntu (apt-based) systems."
  exit 1
fi

#############################################
# Helper to append a line to a file if missing
#############################################
append_if_missing() {
  local FILE="$1"
  local LINE="$2"

  # Create file if it doesn't exist
  if [[ ! -f "$FILE" ]]; then
    touch "$FILE"
  fi

  if ! grep -qxF "$LINE" "$FILE" 2>/dev/null; then
    echo "$LINE" >> "$FILE"
  fi
}

#############################################
# 1) Create user & add to sudo
#############################################
echo ">>> Creating user '$NEW_USER' (if it does not exist)..."

if id -u "$NEW_USER" >/dev/null 2>&1; then
  echo "    User '$NEW_USER' already exists, skipping useradd."
else
  useradd -m -s /bin/bash -G sudo "$NEW_USER"
  echo "    User '$NEW_USER' created and added to sudo group."
fi

USER_HOME=$(eval echo "~$NEW_USER")

#############################################
# 2) Update apt & install base packages
#############################################
echo ">>> Updating apt and installing base packages (Docker, socat, bash-completion, snapd, gnupg, lsb-release)..."

apt update -y
apt install -y docker.io socat bash-completion snapd gnupg software-properties-common lsb-release

echo ">>> Adding '$NEW_USER' to docker group..."
usermod -aG docker "$NEW_USER" || true

#############################################
# 3) Install Minikube
#############################################
if command -v minikube >/dev/null 2>&1; then
  echo ">>> Minikube already installed, skipping."
else
  echo ">>> Installing Minikube..."
  curl -Lo /tmp/minikube-linux-amd64 \
    https://github.com/kubernetes/minikube/releases/latest/download/minikube-linux-amd64

  install /tmp/minikube-linux-amd64 /usr/local/bin/minikube
  rm /tmp/minikube-linux-amd64

  echo "    Minikube version: $(minikube version || echo 'installed')"
fi

#############################################
# 4) Install kubectl
#############################################
if command -v kubectl >/dev/null 2>&1; then
  echo ">>> kubectl already installed, skipping."
else
  echo ">>> Installing kubectl (latest stable)..."

  KUBECTL_VERSION="$(curl -L -s https://dl.k8s.io/release/stable.txt)"
  curl -Lo /tmp/kubectl \
    "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"

  install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl
  rm /tmp/kubectl

  echo "    kubectl version: $(kubectl version --client --output=yaml | head -n 3 || echo 'installed')"
fi

#############################################
# 5) Install Helm via snap
#############################################
if command -v helm >/dev/null 2>&1; then
  echo ">>> Helm already installed, skipping."
else
  echo ">>> Installing Helm (via snap)..."
  snap install helm --classic
  echo "    Helm version: $(helm version --short || echo 'installed')"
fi

#############################################
# 6) Install Terraform (HashiCorp apt repo)
#############################################
if command -v terraform >/dev/null 2>&1; then
  echo ">>> Terraform already installed, skipping."
else
  echo ">>> Installing Terraform via HashiCorp apt repository..."

  # Add HashiCorp GPG key
  curl -fsSL https://apt.releases.hashicorp.com/gpg \
    | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

  # Add repository for current distro codename
  CODENAME="$(lsb_release -cs)"
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com ${CODENAME} main" \
    > /etc/apt/sources.list.d/hashicorp.list

  apt update -y
  apt install -y terraform

  echo "    Terraform version: $(terraform version | head -n 1 || echo 'installed')"
fi

#############################################
# 7) Configure bash completion & alias for NEW_USER
#############################################
echo ">>> Configuring bash completion, kubectl alias, and minikube completion for '$NEW_USER'..."

# Ensure bash-completion is sourced
append_if_missing "$USER_HOME/.bashrc" 'if [ -f /etc/bash_completion ]; then . /etc/bash_completion; fi'

# Minikube completion
append_if_missing "$USER_HOME/.bashrc" 'eval "$(minikube completion bash)"'

# kubectl completion
append_if_missing "$USER_HOME/.bashrc" 'source <(kubectl completion bash)'

# Short alias k
append_if_missing "$USER_HOME/.bashrc" 'alias k=kubectl'
append_if_missing "$USER_HOME/.bashrc" 'complete -o default -F __start_kubectl k'

# Fix ownership of .bashrc in case we created/edited it as root
chown "$NEW_USER:$NEW_USER" "$USER_HOME/.bashrc"

#############################################
# 8) Summary
#############################################
echo
echo "✅ Initial setup completed."
echo
echo "Installed/verified tools:"
echo "  - Docker       : $(docker --version 2>/dev/null || echo 'installed')"
echo "  - Minikube     : $(minikube version 2>/dev/null || echo 'installed')"
echo "  - kubectl      : $(kubectl version --client --short 2>/dev/null || echo 'installed')"
echo "  - Helm         : $(helm version --short 2>/dev/null || echo 'installed')"
echo "  - Terraform    : $(terraform version 2>/dev/null | head -n1 || echo 'installed')"
echo
echo "Next steps:"
echo "  1) Log out and log back in as '$NEW_USER' (or run: su - $NEW_USER)."
echo "  2) Because '$NEW_USER' is in the 'docker' group, log in again so group membership is refreshed."
echo "  3) Then you can run Minikube, kubectl, Helm, and Terraform as '$NEW_USER'."
