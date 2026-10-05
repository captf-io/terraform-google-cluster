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

# Unit tests of the cluster role's public API endpoint (api_load_balancer_public),
# in a file of their own: the endpoint guard refuses to switch an existing
# cluster's endpoint, so these need a fresh state. Mocked; nothing reaches GCP.

mock_provider "google" {
  mock_data "google_client_config" {
    defaults = {
      project = "captf-test"
      region  = "us-central1"
      zone    = ""
    }
  }

  mock_data "google_compute_subnetworks" {
    defaults = {
      subnetworks = [
        {
          description              = ""
          ip_cidr_range            = "10.129.0.0/23"
          name                     = "captf-proxy-only"
          network                  = "https://www.googleapis.com/compute/v1/projects/captf-test/global/networks/captf-vpc"
          network_name             = "captf-vpc"
          network_self_link        = "captf-vpc"
          private_ip_google_access = false
          self_link                = "https://www.googleapis.com/compute/v1/projects/captf-test/regions/us-central1/subnetworks/captf-proxy-only"
        },
        {
          description              = "another network's proxy-only subnet"
          ip_cidr_range            = "10.200.0.0/23"
          name                     = "other-proxy-only"
          network                  = "https://www.googleapis.com/compute/v1/projects/captf-test/global/networks/other-vpc"
          network_name             = "other-vpc"
          network_self_link        = "other-vpc"
          private_ip_google_access = false
          self_link                = "https://www.googleapis.com/compute/v1/projects/captf-test/regions/us-central1/subnetworks/other-proxy-only"
        },
      ]
    }
  }

  mock_data "google_compute_zones" {
    defaults = {
      names = ["us-central1-a", "us-central1-b", "us-central1-c", "us-central1-f"]
    }
  }

  mock_resource "google_compute_address" {
    defaults = {
      address = "10.0.0.10"
    }
  }

  mock_resource "google_compute_global_address" {
    defaults = {
      address = "34.110.0.10"
    }
  }
}

# The node subnetwork listing; the mock's default is the proxy-only listing.
override_data {
  target = data.google_compute_subnetworks.node_subnetworks
  values = {
    subnetworks = [{
      description              = ""
      ip_cidr_range            = "10.0.0.0/20"
      name                     = "captf-nodes"
      network                  = "https://www.googleapis.com/compute/v1/projects/captf-test/global/networks/captf-vpc"
      network_name             = "captf-vpc"
      network_self_link        = "captf-vpc"
      private_ip_google_access = true
      self_link                = "https://www.googleapis.com/compute/v1/projects/captf-test/regions/us-central1/subnetworks/captf-nodes"
    }]
  }
}

variables {
  captf_contract = "v1alpha1"
  captf_cluster  = { name = "demo", namespace = "team-a" }
  captf_object   = { kind = "TerraformCluster", name = "demo", namespace = "team-a" }
  captf_tags = {
    "captf.io/cluster"    = "demo"
    "captf.io/namespace"  = "team-a"
    "captf.io/kind"       = "TerraformCluster"
    "captf.io/name"       = "demo"
    "captf.io/managed-by" = "captf"
    "captf.io/template"   = ""
  }
  control_plane_endpoint    = null
  kubernetes_version        = "v1.33.4"
  control_plane_initialized = false
  cluster_network = {
    pods            = ["192.168.0.0/16"]
    services        = ["10.128.0.0/12"]
    service_domain  = "cluster.local"
    api_server_port = null
  }

  network    = "captf-vpc"
  subnetwork = "captf-nodes"
}

run "tags_on_taggable_resources_public" {
  variables {
    api_load_balancer_public = true
    api_allowed_cidrs        = ["203.0.113.0/24"]
  }

  assert {
    condition     = google_compute_global_address.api_global_address[0].labels["captf-io_cluster"] == "demo"
    error_message = "The global API address must carry captf_tags."
  }
  assert {
    condition     = google_compute_global_forwarding_rule.api_global_forwarding_rules["kube_apiserver"].labels == google_compute_global_address.api_global_address[0].labels
    error_message = "The global forwarding rule must carry captf_tags."
  }
  assert {
    condition     = google_compute_security_policy.api_security_policy[0].labels == google_compute_global_address.api_global_address[0].labels
    error_message = "The security policy must carry captf_tags."
  }
}

run "public_endpoint" {
  variables {
    api_load_balancer_public = true
    api_allowed_cidrs        = ["203.0.113.0/24", "198.51.100.7/32"]
  }

  assert {
    condition     = output.control_plane_endpoint == { host = "34.110.0.10", port = 6443 }
    error_message = "A public endpoint is the global address."
  }
  assert {
    condition     = google_compute_global_forwarding_rule.api_global_forwarding_rules["kube_apiserver"].load_balancing_scheme == "EXTERNAL_MANAGED" && google_compute_backend_service.api_backend_services["kube_apiserver"].load_balancing_scheme == "EXTERNAL_MANAGED"
    error_message = "The public endpoint is a global external proxy load balancer."
  }
  assert {
    condition     = google_compute_backend_service.api_backend_services["kube_apiserver"].security_policy == google_compute_security_policy.api_security_policy[0].id
    error_message = "The backend service must be guarded by the Cloud Armor policy."
  }
  assert {
    condition     = length(google_compute_security_policy.api_security_policy[0].rule) == 2
    error_message = "The policy must hold one allow rule and the default deny rule."
  }
  assert {
    condition     = google_compute_firewall.api_ingress_firewall[0].source_ranges == toset(["130.211.0.0/22", "35.191.0.0/16"])
    error_message = "The API rule allows Google's front ends only."
  }
  assert {
    condition     = length(google_compute_address.api_address) == 0 && length(data.google_compute_subnetworks.proxy_subnetworks) == 0
    error_message = "A public endpoint needs no internal address and no proxy-only subnet."
  }
}

run "public_allowlist_chunks" {
  command = plan

  variables {
    api_load_balancer_public = true
    api_allowed_cidrs        = [for i in range(23) : "198.51.100.${i}/32"]
  }

  assert {
    condition     = length(google_compute_security_policy.api_security_policy[0].rule) == 4
    error_message = "23 CIDRs need three allow rules of at most 10 ranges, plus the default rule."
  }
}

run "public_requires_allowed_cidrs" {
  command = plan

  variables {
    api_load_balancer_public = true
  }

  expect_failures = [google_compute_firewall.node_internal_firewall]
}
