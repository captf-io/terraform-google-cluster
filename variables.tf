# Copyright 2026 The CAPTF Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# User variables of the cluster role, set through the TerraformCluster's
# spec.variables or spec.variablesFrom
# (https://captf.io/docs/user-guide/variables.html). Alphabetical.

variable "additional_tags" {
  description = "Extra GCP labels for every labelable resource. Keys and values must already be valid GCP labels; the captf-io_ keys are reserved for captf_tags, which win."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition     = length(var.additional_tags) <= 58
    error_message = "additional_tags holds at most 58 labels: GCP allows 64 per resource and captf_tags takes 6."
  }
  validation {
    condition     = alltrue([for k, v in var.additional_tags : can(regex("^[a-z][a-z0-9_-]{0,62}$", k)) && can(regex("^[a-z0-9_-]{0,63}$", v))])
    error_message = "additional_tags keys must match ^[a-z][a-z0-9_-]{0,62}$ and values ^[a-z0-9_-]{0,63}$ (GCP label syntax)."
  }
  validation {
    condition     = alltrue([for k in keys(var.additional_tags) : !startswith(k, "captf-io_")])
    error_message = "additional_tags must not use keys starting with captf-io_: they are reserved for the mapped captf_tags."
  }
}

variable "api_allowed_cidrs" {
  description = "Client CIDRs allowed to reach the public API endpoint, enforced by a Cloud Armor policy. Required when api_load_balancer_public is true; include the Cloud NAT egress addresses so nodes can reach the endpoint."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for c in var.api_allowed_cidrs : can(cidrhost(c, 0))])
    error_message = "api_allowed_cidrs must hold CIDR blocks such as 203.0.113.0/24."
  }
}

variable "api_global_access" {
  description = "Let clients in any region of the VPC reach the internal API endpoint. Off by default: only clients in the cluster's region can."
  type        = bool
  default     = false
  nullable    = false
}

variable "api_load_balancer_public" {
  description = "Serve the API through a global external proxy load balancer instead of the internal one. Off by default; requires api_allowed_cidrs."
  type        = bool
  default     = false
  nullable    = false
}

variable "control_plane_roles" {
  description = "Project roles for a module-created control-plane service account: what cloud-provider-gcp and the PD CSI controller need. Ignored with control_plane_service_account."
  type        = list(string)
  default = [
    "roles/compute.instanceAdmin.v1",
    "roles/compute.loadBalancerAdmin",
    "roles/compute.securityAdmin",
    "roles/compute.storageAdmin",
    "roles/compute.viewer",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
  ]
  nullable = false

  validation {
    condition     = alltrue([for r in var.control_plane_roles : can(regex("^(roles|projects/[^/]+/roles|organizations/[0-9]+/roles)/[A-Za-z0-9_.]+$", r))])
    error_message = "control_plane_roles must hold role names such as roles/compute.viewer or projects/<project>/roles/<id>."
  }
}

variable "control_plane_service_account" {
  description = "Email of an existing service account for control-plane nodes. Null creates one with control_plane_roles."
  type        = string
  default     = null

  validation {
    condition     = var.control_plane_service_account == null || can(regex("^[^@]+@[^@]+\\.iam\\.gserviceaccount\\.com$", var.control_plane_service_account))
    error_message = "control_plane_service_account must be a service account email ending in .iam.gserviceaccount.com."
  }
}

variable "distribution" {
  description = "Kubernetes distribution of the control plane: kubeadm, or rke2, which adds the RKE2 supervisor port 9345 on the API address and always uses kube-apiserver port 6443 on the nodes. kubeadm by default."
  type        = string
  default     = "kubeadm"
  nullable    = false

  validation {
    condition     = contains(["kubeadm", "rke2"], var.distribution)
    error_message = "distribution must be kubeadm or rke2."
  }
}

variable "network" {
  description = "Name of the existing VPC network the cluster runs in (bring your own network). Required."
  type        = string
  default     = null

  validation {
    condition     = var.network != null
    error_message = "network is required: set spec.variables.network on the TerraformCluster to the name of an existing VPC network."
  }
  validation {
    condition     = var.network == null || can(regex("^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$", var.network))
    error_message = "network must be a VPC network name such as my-vpc, not a URL."
  }
}

variable "network_project" {
  description = "Project that owns the network: the host project of a Shared VPC. Null means the cluster's own project. Firewall rules are created here."
  type        = string
  default     = null

  validation {
    condition     = var.network_project == null || can(regex("^[a-z][-a-z0-9]{4,28}[a-z0-9]$", var.network_project))
    error_message = "network_project must be a project ID such as my-host-project."
  }
}

variable "project" {
  description = "Project to create the cluster in. Null uses the provider's project: GOOGLE_PROJECT from the identity Secret, or the credentials' project."
  type        = string
  default     = null

  validation {
    condition     = var.project == null || can(regex("^[a-z][-a-z0-9]{4,28}[a-z0-9]$", var.project))
    error_message = "project must be a project ID such as my-project."
  }
}

variable "region" {
  description = "Region of the cluster. Null uses the provider's region: GOOGLE_REGION from the identity Secret."
  type        = string
  default     = null

  validation {
    condition     = var.region == null || can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "region must be a region name such as us-central1."
  }
}

variable "subnetwork" {
  description = "Name of the existing regional subnetwork, in network, that nodes and the internal API address use. Required."
  type        = string
  default     = null

  validation {
    condition     = var.subnetwork != null
    error_message = "subnetwork is required: set spec.variables.subnetwork on the TerraformCluster to the name of an existing subnetwork in the cluster's region."
  }
  validation {
    condition     = var.subnetwork == null || can(regex("^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$", var.subnetwork))
    error_message = "subnetwork must be a subnetwork name such as my-subnet, not a URL."
  }
}

variable "worker_roles" {
  description = "Project roles for a module-created worker service account: logs and metrics only. Ignored with worker_service_account."
  type        = list(string)
  default = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
  ]
  nullable = false

  validation {
    condition     = alltrue([for r in var.worker_roles : can(regex("^(roles|projects/[^/]+/roles|organizations/[0-9]+/roles)/[A-Za-z0-9_.]+$", r))])
    error_message = "worker_roles must hold role names such as roles/logging.logWriter or projects/<project>/roles/<id>."
  }
}

variable "worker_service_account" {
  description = "Email of an existing service account for worker nodes. Null creates one with worker_roles."
  type        = string
  default     = null

  validation {
    condition     = var.worker_service_account == null || can(regex("^[^@]+@[^@]+\\.iam\\.gserviceaccount\\.com$", var.worker_service_account))
    error_message = "worker_service_account must be a service account email ending in .iam.gserviceaccount.com."
  }
}

variable "zones" {
  description = "Zones of the region to use as failure domains. Empty means every zone of the region; set it when the machine type is not offered everywhere."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = length(var.zones) == length(distinct(var.zones))
    error_message = "zones must not repeat a zone."
  }
  validation {
    condition     = alltrue([for z in var.zones : can(regex("^[a-z]+-[a-z]+[0-9]+-[a-z0-9]+$", z))])
    error_message = "zones must hold zone names such as us-central1-a."
  }
}
