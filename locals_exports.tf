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

# The exports handed to every machine and pool as captf_cluster_outputs,
# schema captf.io/gcp-cluster/v1 (CONVENTIONS.md section 12; README
# "Exports"). Nothing here is secret: exports are stored in clear.
locals {
  # What decides the endpoint, recorded by api_endpoint_guard.tf.
  api_endpoint_inputs = {
    api_load_balancer_public = var.api_load_balancer_public
    network                  = var.network
    subnetwork               = var.subnetwork
    project                  = local.project
    region                   = local.region
    api_server_port          = local.api_port
  }

  # The endpoint the module owns, or null for a user endpoint.
  api_host = (
    local.internal_lb ? try(google_compute_address.api_address[0].address, null) :
    local.external_lb ? try(google_compute_global_address.api_global_address[0].address, null) :
    null
  )

  exports = {
    schema      = "captf.io/gcp-cluster/v1"
    project     = local.project
    region      = local.region
    network     = local.network_self_link
    subnetwork  = local.subnetwork_self_link
    name_prefix = local.name_prefix
    # Failure domain name => attributes; the name is the zone.
    failure_domains  = { for z in local.zones : z => { zone = z } }
    node_network_tag = local.node_network_tag
    control_plane = {
      service_account = local.control_plane_service_account
      network_tags    = [local.node_network_tag, local.control_plane_network_tag]
    }
    worker = {
      service_account = local.worker_service_account
      network_tags    = [local.node_network_tag, local.worker_network_tag]
    }
    # What control-plane machines register against: the instance group of
    # their zone. Null for a user endpoint: there is nothing to join.
    api = local.module_endpoint ? {
      host            = local.api_host
      port            = local.api_port
      backend_port    = local.api_backend_port
      instance_groups = { for z, g in google_compute_instance_group.api_instance_groups : z => g.self_link }
    } : null
  }
}
