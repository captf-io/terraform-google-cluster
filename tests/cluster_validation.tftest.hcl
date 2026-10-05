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

# Validation and precondition tests of the cluster role. Every run is a plan
# from an empty state, so no endpoint guard is recorded yet. Mocked; nothing
# reaches GCP.

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

run "invalid_captf_contract" {
  command = plan
  variables {
    captf_contract = "v1alpha2"
  }
  expect_failures = [var.captf_contract]
}

run "invalid_additional_tags_count" {
  command = plan
  variables {
    additional_tags = { for i in range(59) : "k${i}" => "v" }
  }
  expect_failures = [var.additional_tags]
}

run "invalid_additional_tags_syntax" {
  command = plan
  variables {
    additional_tags = { "Team.Name" = "x" }
  }
  expect_failures = [var.additional_tags]
}

run "invalid_additional_tags_reserved" {
  command = plan
  variables {
    additional_tags = { "captf-io_cluster" = "other" }
  }
  expect_failures = [var.additional_tags]
}

run "invalid_api_allowed_cidrs" {
  command = plan
  variables {
    api_allowed_cidrs = ["203.0.113.0"]
  }
  expect_failures = [var.api_allowed_cidrs]
}

run "invalid_control_plane_roles" {
  command = plan
  variables {
    control_plane_roles = ["compute.viewer"]
  }
  expect_failures = [var.control_plane_roles]
}

run "invalid_control_plane_service_account" {
  command = plan
  variables {
    control_plane_service_account = "someone@example.com"
  }
  expect_failures = [var.control_plane_service_account]
}

run "invalid_network_missing" {
  command = plan
  variables {
    network = null
  }
  expect_failures = [var.network]
}

run "invalid_network_url" {
  command = plan
  variables {
    network = "projects/captf-test/global/networks/captf-vpc"
  }
  expect_failures = [var.network]
}

run "invalid_network_project" {
  command = plan
  variables {
    network_project = "Host_Project"
  }
  expect_failures = [var.network_project]
}

run "invalid_project" {
  command = plan
  variables {
    project = "x"
  }
  expect_failures = [var.project]
}

run "invalid_region" {
  command = plan
  variables {
    region = "us-central1-a"
  }
  expect_failures = [var.region]
}

run "invalid_subnetwork_missing" {
  command = plan
  variables {
    subnetwork = null
  }
  expect_failures = [var.subnetwork]
}

run "invalid_subnetwork_url" {
  command = plan
  variables {
    subnetwork = "regions/us-central1/subnetworks/captf-nodes"
  }
  expect_failures = [var.subnetwork]
}

run "invalid_worker_roles" {
  command = plan
  variables {
    worker_roles = ["logging.logWriter"]
  }
  expect_failures = [var.worker_roles]
}

run "invalid_worker_service_account" {
  command = plan
  variables {
    worker_service_account = "worker"
  }
  expect_failures = [var.worker_service_account]
}

run "invalid_zones_repeated" {
  command = plan
  variables {
    zones = ["us-central1-a", "us-central1-a"]
  }
  expect_failures = [var.zones]
}

run "invalid_zones_syntax" {
  command = plan
  variables {
    zones = ["us-central1"]
  }
  expect_failures = [var.zones]
}

run "rejects_missing_proxy_subnet" {
  command = plan

  override_data {
    target = data.google_compute_subnetworks.proxy_subnetworks
    values = {
      subnetworks = []
    }
  }

  expect_failures = [google_compute_forwarding_rule.api_forwarding_rules]
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

run "rejects_zone_outside_region" {
  command = plan

  variables {
    zones = ["us-central1-a", "us-east1-b"]
  }

  expect_failures = [google_compute_firewall.node_internal_firewall]
}

run "rejects_missing_project" {
  command = plan

  override_data {
    target = data.google_client_config.provider_config
    values = {
      project = ""
      region  = "us-central1"
    }
  }

  expect_failures = [data.google_client_config.provider_config]
}

run "rejects_missing_region" {
  command = plan

  override_data {
    target = data.google_client_config.provider_config
    values = {
      project = "captf-test"
      region  = ""
    }
  }

  expect_failures = [data.google_client_config.provider_config]
}

run "rejects_supervisor_port_collision" {
  command = plan

  variables {
    distribution = "rke2"
    cluster_network = {
      pods            = []
      services        = []
      service_domain  = null
      api_server_port = 9345
    }
  }

  expect_failures = [google_compute_firewall.node_internal_firewall]
}
