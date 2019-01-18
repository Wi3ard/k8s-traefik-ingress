/*
 * Input variables.
 */

variable "acme_email" {
  description = "Admin e-mail for Let's Encrypt"
  type        = "string"
}

variable "domain_name" {
  description = "Root domain name for the stack"
  type        = "string"
}

variable "dns_zone_name" {
  description = "The unique name of the zone hosted by Google Cloud DNS"
  type        = "string"
}

variable "google_project_id" {
  description = "GCE project ID"
  type        = "string"
}

variable "region" {
  default     = "us-central1"
  description = "Region to create resources in"
  type        = "string"
}

/*
 * Terraform providers.
 */

provider "google" {
  version = "~> 1.20"

  project = "${var.google_project_id}"
  region  = "${var.region}"
}

provider "helm" {
  version = "~> 0.7"
}

provider "kubernetes" {
  version = "~> 1.4"
}

/*
 * GCS remote storage for storing Terraform state.
 */

terraform {
  backend "gcs" {}
}

/*
 * Terraform resources.
 */

# Consul helm chart.
resource "helm_release" "consul" {
  chart         = "stable/consul"
  force_update  = true
  name          = "consul"
  namespace     = "kube-system"
  recreate_pods = true
  reuse_values  = true

  values = [<<EOF
ImageTag: "1.4.0"
EOF
  ]
}

# Traefik helm chart.
resource "helm_release" "traefik" {
  depends_on = ["helm_release.consul"]

  chart         = "stable/traefik"
  force_update  = true
  name          = "traefik"
  namespace     = "kube-system"
  recreate_pods = true
  reuse_values  = true

  values = [<<EOF
accessLogs:
  enabled: false
acme:
  challengeType: "http-01"
  domains:
    enabled: true
    domainsList:
      - main: "${var.domain_name}"
      - sans:
        - "www.${var.domain_name}"
  email: "${var.acme_email}"
  enabled: true
  logging: true
  onHostRule: true
  persistence:
    enabled: false
  staging: false
externalTrafficPolicy: Local
forwardedHeaders:
  enabled: true
  trustedIPs:
    - 0.0.0.0/0
kvprovider:
  storeAcme: true
  consul:
    endpoint: "consul:8500"
    prefix: traefik
    watch: true
rbac:
  enabled: true
ssl:
  cipherSuites: [
    "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384",
    "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384",
    "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305",
    "TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305",
    "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256",
    "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256",
    "TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256",
    "TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256"
  ]
  enabled: true
  enforced: true
  generateTLS: false
  tlsMinVersion: VersionTLS12
cpuRequest: 200m
memoryRequest: 100Mi
cpuLimit: 400m
memoryLimit: 300Mi
EOF
  ]
}

# Traefik autoscaler.
resource "kubernetes_horizontal_pod_autoscaler" "traefik" {
  metadata {
    name      = "${helm_release.traefik.metadata.0.name}"
    namespace = "${helm_release.traefik.metadata.0.namespace}"

    labels {
      app     = "traefik"
      release = "traefik"
    }
  }

  spec {
    max_replicas                      = 10
    min_replicas                      = 2
    target_cpu_utilization_percentage = 50

    scale_target_ref {
      api_version = "extensions/v1beta1"
      kind        = "Deployment"
      name        = "${helm_release.traefik.name}"
    }
  }
}

# Data source for Traefik Helm chart.
data "kubernetes_service" "traefik" {
  depends_on = ["helm_release.traefik"]

  metadata {
    name      = "${helm_release.traefik.metadata.0.name}"
    namespace = "${helm_release.traefik.metadata.0.namespace}"
  }
}

# DNS zone managed by Google Cloud DNS.
data "google_dns_managed_zone" "default" {
  name = "${var.dns_zone_name}"
}

# Root A record.
resource "google_dns_record_set" "a_root" {
  name         = "${var.domain_name}."
  managed_zone = "${data.google_dns_managed_zone.default.name}"
  type         = "A"
  ttl          = 300

  rrdatas = ["${data.kubernetes_service.traefik.load_balancer_ingress.0.ip}"]
}

# Wildcard A record.
resource "google_dns_record_set" "a_wildcard" {
  name         = "*.${var.domain_name}."
  managed_zone = "${data.google_dns_managed_zone.default.name}"
  type         = "A"
  ttl          = 300

  rrdatas = ["${data.kubernetes_service.traefik.load_balancer_ingress.0.ip}"]
}

/*
 * Outputs.
 */

output "load_balancer_ip" {
  description = "IP address of the load balancer"
  value = "${data.kubernetes_service.traefik.load_balancer_ingress.0.ip}"
}
