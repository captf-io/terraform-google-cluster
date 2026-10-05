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

# Contract inputs of the cluster role, in contract order, with the contract's
# types: https://captf.io/docs/module-author/contract/v1alpha1/common.html and
# https://captf.io/docs/module-author/contract/v1alpha1/cluster.html

# Read only by its own validation.
# tflint-ignore: terraform_unused_declarations
variable "captf_contract" {
  description = "Contract version the controller generated the root module for."
  type        = string

  validation {
    condition     = var.captf_contract == "v1alpha1"
    error_message = "captf_contract must be \"v1alpha1\": this module implements the v1alpha1 cluster role only."
  }
}

variable "captf_cluster" {
  description = "The owning CAPI Cluster."
  type = object({
    name      = string
    namespace = string
  })
}

# Names come from the Cluster; the TerraformCluster adds nothing.
# tflint-ignore: terraform_unused_declarations
variable "captf_object" {
  description = "The TerraformCluster being reconciled."
  type = object({
    kind      = string
    name      = string
    namespace = string
  })
}

# Not passed to the cluster role; declared with a default so validate passes
# (cluster.md "Inputs").
# tflint-ignore: terraform_unused_declarations
variable "captf_cluster_outputs" {
  description = "Not used by the cluster role: the controller passes it to machines and pools only."
  type        = any
  default     = null
}

variable "captf_tags" {
  description = "Fixed captf.io/* tags the controller sets; applied as GCP labels to every labelable resource."
  type        = map(string)
}

variable "control_plane_endpoint" {
  description = "An endpoint the module does not own (user or control-plane provider). Non-null means: create no API load balancer."
  type = object({
    host = string
    port = number
  })
  default = null
}

# Accepted for the contract; nothing in GCP depends on the cluster's version.
# tflint-ignore: terraform_unused_declarations
variable "kubernetes_version" {
  description = "Cluster.spec.topology.version, or null without ClusterClass. Unused: machines and pools carry their own version."
  type        = string
  default     = null
}

# Nothing here needs a live workload API server.
# tflint-ignore: terraform_unused_declarations
variable "control_plane_initialized" {
  description = "Cluster.status.initialization.controlPlaneInitialized, latched. Unused: no resource waits for the workload cluster."
  type        = bool
}

variable "cluster_network" {
  description = "Cluster.spec.clusterNetwork: pod CIDRs feed a firewall rule, api_server_port the API load balancer port."
  type = object({
    pods            = list(string)
    services        = list(string)
    service_domain  = string
    api_server_port = number
  })
  default = null
}
