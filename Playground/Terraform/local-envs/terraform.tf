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
resource "kubernetes_deployment" "local-envs" {
  metadata {
    name = "local-envs"
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
            value = "Hello world!"
          }
          env {
            name = "GIVEN_STRING"
            value = "it is nice e-meeting you"
          }
          env {
            name = "NAME"
            value = "Kubernetes"
          }
          command = ["bash", "-c"]
          args = ["echo \"$(GREETING) $(GIVEN_STRING), $(NAME)\" && sleep infinity"]
        }
      }
    }
  }
  
  
}