terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.0"
    }
  }
}
provider "kubernetes" {
  config_path = "~/.kube/config"
}
resource "kubernetes_priority_class" "low-priority" {
  value = 500000
  metadata {
    name = "low-priority"
  }
  global_default = false
}
resource "kubernetes_priority_class" "medium-priority" {
  value = 750000
  metadata {
    name = "medium-priority"
  }
  global_default = false
}
resource "kubernetes_priority_class" "high-priority" {
  value = 1000000
  metadata {
    name = "high-priority"
  }
  global_default = false
}