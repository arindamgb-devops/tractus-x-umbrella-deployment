variable "minikube_profile" {
  description = "Name of the Minikube profile to use"
  type        = string
  default     = "tractus"
}

variable "minikube_cpus" {
  description = "Number of CPUs to allocate to Minikube"
  type        = number
  default     = 6
}

variable "minikube_memory_mb" {
  description = "Memory in MB allocated to Minikube"
  type        = number
  default     = 20480 # 20 GiB
}

variable "argocd_namespace" {
  description = "Namespace for Argo CD"
  type        = string
  default     = "argocd"
}

variable "argocd_release_name" {
  description = "Helm release name for Argo CD"
  type        = string
  default     = "argocd"
}

variable "argocd_values_file" {
  description = "Path to the Argo CD values YAML file"
  type        = string
  default     = "argocd-values.yaml"
}

variable "tx_gitops_file" {
  description = "Path to the tx-gitops manifest file"
  type        = string
  default     = "tx-gitops.yaml"
}

variable "vault_namespace" {
  description = "Namespace for HashiCorp Vault"
  type        = string
  default     = "tractus-x"
}

variable "vault_release_name" {
  description = "Helm release name for Vault"
  type        = string
  default     = "vault"
}

variable "vault_values_file" {
  description = "Path to the Vault values YAML file"
  type        = string
  default     = "vault-values.yaml"
}

variable "vault_ingress_file" {
  description = "Path to the Vault ingress manifest"
  type        = string
  default     = "vault-ingress.yaml"
}
