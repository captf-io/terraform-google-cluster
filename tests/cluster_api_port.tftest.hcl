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

# Unit tests of a non-default API port, in a file of their own: the endpoint
# guard refuses a port change on an existing cluster, so these need a fresh
# state. Mocked; nothing reaches GCP.

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

run "api_server_port_override" {
  variables {
    cluster_network = {
      pods            = []
      services        = []
      service_domain  = null
      api_server_port = 8443
    }
  }

  assert {
    condition     = output.control_plane_endpoint.port == 8443 && output.exports.api.port == 8443 && output.exports.api.backend_port == 8443
    error_message = "api_server_port sets both the frontend and the backend port."
  }
  assert {
    condition     = google_compute_forwarding_rule.api_forwarding_rules["kube_apiserver"].port_range == "8443" && google_compute_region_health_check.api_region_health_checks["kube_apiserver"].tcp_health_check[0].port == 8443
    error_message = "The forwarding rule and health check must use api_server_port."
  }
  assert {
    condition     = google_compute_instance_group.api_instance_groups["us-central1-b"].named_port[0].port == 8443
    error_message = "The named port must follow api_server_port."
  }
  assert {
    condition     = length(google_compute_firewall.pod_ingress_firewalls) == 0
    error_message = "Without pod CIDRs there is no pod rule."
  }
}

run "rke2_backend_port_is_6443" {
  variables {
    distribution = "rke2"
    cluster_network = {
      pods            = []
      services        = []
      service_domain  = null
      api_server_port = 8443
    }
  }

  assert {
    condition     = output.control_plane_endpoint.port == 8443 && output.exports.api.port == 8443 && output.exports.api.backend_port == 6443
    error_message = "With RKE2 the endpoint keeps api_server_port and the kube-apiserver backend is 6443: RKE2 never reads apiServerPort."
  }
  assert {
    condition     = google_compute_forwarding_rule.api_forwarding_rules["kube_apiserver"].port_range == "8443" && google_compute_region_health_check.api_region_health_checks["kube_apiserver"].tcp_health_check[0].port == 6443
    error_message = "The frontend serves api_server_port; the health check probes 6443."
  }
  assert {
    condition     = one(google_compute_firewall.api_ingress_firewall[0].allow).ports == tolist(["6443", "9345"])
    error_message = "The firewall opens the backend ports, 6443 and 9345."
  }
}

