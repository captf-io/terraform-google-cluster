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

# Unit tests of the cluster role with a mocked Google provider: nothing
# reaches GCP. Each run plans against a node subnetwork listing of its own,
# so this file has no file-level override_data of node_subnetworks, which a
# run-level override would shadow. Run from the role directory with
# `terraform test` or `tofu test`, or `make unit-test`.

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

run "rejects_proxy_subnet_of_other_network" {
  command = plan

  variables {
    network = "third-vpc"
  }

  override_data {
    target = data.google_compute_subnetworks.node_subnetworks
    values = {
      subnetworks = [{
        description              = ""
        ip_cidr_range            = "10.0.0.0/20"
        name                     = "captf-nodes"
        network                  = "https://www.googleapis.com/compute/v1/projects/captf-test/global/networks/third-vpc"
        network_name             = "third-vpc"
        network_self_link        = "third-vpc"
        private_ip_google_access = true
        self_link                = "https://www.googleapis.com/compute/v1/projects/captf-test/regions/us-central1/subnetworks/captf-nodes"
      }]
    }
  }

  expect_failures = [google_compute_forwarding_rule.api_forwarding_rules]
}

run "rejects_subnetwork_outside_network" {
  command = plan

  override_data {
    target = data.google_compute_subnetworks.node_subnetworks
    values = {
      subnetworks = [{
        description              = ""
        ip_cidr_range            = "10.0.0.0/20"
        name                     = "captf-nodes"
        network                  = "https://www.googleapis.com/compute/v1/projects/captf-test/global/networks/other-vpc"
        network_name             = "other-vpc"
        network_self_link        = "other-vpc"
        private_ip_google_access = true
        self_link                = "https://www.googleapis.com/compute/v1/projects/captf-test/regions/us-central1/subnetworks/captf-nodes"
      }]
    }
  }

  expect_failures = [google_compute_firewall.node_internal_firewall]
}

run "rejects_missing_subnetwork" {
  command = plan

  override_data {
    target = data.google_compute_subnetworks.node_subnetworks
    values = {
      subnetworks = []
    }
  }

  expect_failures = [google_compute_firewall.node_internal_firewall]
}
