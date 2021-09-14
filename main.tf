
terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.2.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.11.1"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.20.0"
    }
    kubernetes-alpha = {
      source = "hashicorp/kubernetes-alpha"
      version = "0.4.1"
    }
  }
}

variable "region" {
  default     = "us-east-1"
  description = "AWS region"
}

variable "access_key" {
  type = string
  description = "AWS Access key"
}

variable "secret_key" {
  type = string
  description = "AWS Secret key"
}

provider "aws" {
  region = "us-east-1"
  access_key = var.access_key
  secret_key = var.secret_key 
}

data "aws_eks_cluster" "default" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "default" {
  name = var.cluster_name
}

resource "local_file" "kubeconfig" {
  sensitive_content = templatefile("${path.module}/kubeconfig.tpl", {
    cluster_name = var.cluster_name,
    clusterca    = data.aws_eks_cluster.default.certificate_authority[0].data,
    endpoint     = data.aws_eks_cluster.default.endpoint,
    })
  filename          = "${path.module}/kubeconfig-${var.cluster_name}"
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.default.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.default.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.default.token
}

provider "kubectl" {
  host                   = data.aws_eks_cluster.default.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.default.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.default.token
  load_config_file       = false
  #config_path            = "${path.module}/kubeconfig-${var.cluster_name}"
}

data "kubectl_file_documents" "eck_operator_manifests" {
    content = file("./eck-operator.yaml")
}

resource "kubectl_manifest" "eck_operator" {
    count     = length(data.kubectl_file_documents.eck_operator_manifests.documents)
    yaml_body = element(data.kubectl_file_documents.eck_operator_manifests.documents, count.index)
}

resource "kubernetes_namespace" "elastic_ns" {
  metadata {
    name = "elastic"
  }
}

data "kubectl_file_documents" "elasticsearch_manifests" {
    content = templatefile("./elasticsearch-manifest.yaml", { s3_key = "${var.s3_key}", s3_key_id = "${var.s3_key_id}" })
    # content = file("./elasticsearch-manifest.yaml")
    }

resource "kubectl_manifest" "elasticsearch" {
    count     = length(data.kubectl_file_documents.elasticsearch_manifests.documents)
    yaml_body = element(data.kubectl_file_documents.elasticsearch_manifests.documents, count.index)
}

data "kubectl_file_documents" "kibana_manifests" {
    content = file("./kibana-manifest.yaml")
}

resource "kubectl_manifest" "kibana" {
    count     = length(data.kubectl_file_documents.kibana_manifests.documents)
    yaml_body = element(data.kubectl_file_documents.kibana_manifests.documents, count.index)
}

