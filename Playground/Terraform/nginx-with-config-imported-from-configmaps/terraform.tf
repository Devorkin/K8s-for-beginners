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
resource "kubernetes_config_map" "nginx-conf" {
  metadata {
    name = "nginx-conf"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  data = {
    "nginx.conf" = "${file("${path.module}/nginx.conf")}"
  }
}
resource "kubernetes_deployment" "nginx-redirect" {
  metadata {
    name = "nginx-redirect"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        type = "web-servers"
      }
    }
    template {
      metadata {
        labels = {
          type = "web-servers"
        }
      }
      spec {
        container {
          image = "nginx"
          name = "nginx-container"
          port {
            container_port = 80
          }
          volume_mount {
            name = "nginx-conf"
            mount_path = "/etc/nginx/nginx.conf"
            sub_path = "nginx.conf"
            read_only = true
          }
        }
        volume {
          name = "nginx-conf"
          config_map {
            name = "nginx-conf"
            items {
              key = "nginx.conf"
              path = "nginx.conf"
            }
          }
        }
      }
    }
  } 
}
resource "kubernetes_service" "nginx-svc" {
  metadata {
    name = "nginx-svc"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  spec {
    selector = {
      type = kubernetes_deployment.nginx-redirect.spec.0.selector.0.match_labels.type
    }
    type = "NodePort"
    port {
      node_port = 30203
      port = 80
      target_port = 80
    }
  }
  
}
