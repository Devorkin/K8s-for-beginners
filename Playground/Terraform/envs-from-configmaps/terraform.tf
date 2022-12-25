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
resource "kubernetes_namespace" "namespace" {
  metadata {
    name = "tf-playground"
  }
}
resource "kubernetes_config_map" "pod-envs" {
  metadata {
    name = "pod-envs"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  data = {
    "GREETING" = "Hello"
    "NAME" = "Containered.io"
  }
}
resource "kubernetes_deployment" "envs-from-configmaps" {
  metadata {
    name = "envs-from-configmaps"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        "type" = "greeting"
      }
    }
    template {
      metadata {
        labels = {
          "type" = "greeting"
        }
      }
      spec {
        container {
          image = "bash"
          name = "print-envs"
          env {
            name = "GREETING"
            value_from {
              config_map_key_ref {
                name = "pod-envs"
                key = "GREETING"
              }
            }
          }
          env {
            name = "NAME"
            value_from {
              config_map_key_ref {
                name = "pod-envs"
                key = "NAME"
              }
            }
          }
          command = ["bash", "-c"]
          args = ["echo \"$(GREETING), $(NAME)\" && sleep infinity"]
        }
      }
    }
  }
}
