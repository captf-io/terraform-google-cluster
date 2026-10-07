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
# reaches GCP. Run from the role directory with `terraform test` or
# `tofu test`, or `make unit-test`. Run names follow CONVENTIONS.md
# section 14; public endpoint, API port and validation runs have files of
# their own.

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

# The proxy-only subnet listing; the mock's default is the node listing, so
# the runs that change it override node_subnetworks without shadowing a
# file-level override.
override_data {
  target = data.google_compute_subnetworks.proxy_subnetworks
  values = {
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

run "happy_path" {
  assert {
    condition     = terraform_data.api_endpoint_guard[0].input.api_load_balancer_public == false && terraform_data.api_endpoint_guard[0].input.api_server_port == 6443 && terraform_data.api_endpoint_guard[0].input.address == "10.0.0.10"
    error_message = "The endpoint guard records what decides the endpoint, the address included."
  }
  assert {
    condition     = output.control_plane_endpoint == { host = "10.0.0.10", port = 6443 }
    error_message = "control_plane_endpoint must be the internal API address on port 6443."
  }
  assert {
    condition = output.failure_domains == [
      { name = "us-central1-a", control_plane = true, attributes = { zone = "us-central1-a" } },
      { name = "us-central1-b", control_plane = true, attributes = { zone = "us-central1-b" } },
      { name = "us-central1-c", control_plane = true, attributes = { zone = "us-central1-c" } },
      { name = "us-central1-f", control_plane = true, attributes = { zone = "us-central1-f" } },
    ]
    error_message = "failure_domains must list every zone of the region, eligible for the control plane."
  }
  assert {
    condition     = output.exports.schema == "captf.io/gcp-cluster/v1" && output.exports.project == "captf-test" && output.exports.region == "us-central1"
    error_message = "exports must carry the schema, project and region."
  }
  assert {
    condition     = output.exports.api.host == "10.0.0.10" && output.exports.api.port == 6443 && output.exports.api.backend_port == 6443
    error_message = "exports.api must carry the endpoint and backend port."
  }
  assert {
    condition     = keys(output.exports.api.instance_groups) == ["us-central1-a", "us-central1-b", "us-central1-c", "us-central1-f"]
    error_message = "exports.api.instance_groups must hold one group per zone."
  }
  assert {
    condition     = output.health.state == "running" && output.health.healthy && output.health.message == "API forwarding rule serves 10.0.0.10:6443." && length(output.health.reasons) == 0
    error_message = "A cluster whose API forwarding rule exists is running and healthy."
  }
  assert {
    condition     = google_compute_address.api_address[0].purpose == "SHARED_LOADBALANCER_VIP" && google_compute_address.api_address[0].address_type == "INTERNAL"
    error_message = "The API address must be internal and shareable between listeners."
  }
  assert {
    condition     = google_compute_forwarding_rule.api_forwarding_rules["kube_apiserver"].load_balancing_scheme == "INTERNAL_MANAGED" && google_compute_forwarding_rule.api_forwarding_rules["kube_apiserver"].port_range == "6443"
    error_message = "The API forwarding rule must be an internal proxy rule on port 6443."
  }
  assert {
    condition     = !google_compute_forwarding_rule.api_forwarding_rules["kube_apiserver"].allow_global_access
    error_message = "Global access is off by default."
  }
  assert {
    condition     = google_compute_region_backend_service.api_region_backend_services["kube_apiserver"].timeout_sec == 3600 && toset([for b in google_compute_region_backend_service.api_region_backend_services["kube_apiserver"].backend : b.group]) == toset([for g in google_compute_instance_group.api_instance_groups : g.self_link])
    error_message = "The backend service must have a 3600 s idle timeout and one backend per zone."
  }
  assert {
    condition     = google_compute_region_health_check.api_region_health_checks["kube_apiserver"].tcp_health_check[0].port == 6443
    error_message = "The health check must probe the backend port over TCP."
  }
  assert {
    condition     = keys(google_compute_forwarding_rule.api_forwarding_rules) == ["kube_apiserver"]
    error_message = "With kubeadm there is one listener."
  }
  assert {
    condition     = google_compute_instance_group.api_instance_groups["us-central1-a"].named_port[0].name == "apiserver" && google_compute_instance_group.api_instance_groups["us-central1-a"].named_port[0].port == 6443
    error_message = "Instance groups must name the API port."
  }
  assert {
    condition     = google_compute_firewall.api_ingress_firewall[0].source_ranges == toset(["10.129.0.0/23", "130.211.0.0/22", "35.191.0.0/16"])
    error_message = "The API rule must allow this network's proxy-only subnet and the health checkers, nothing else."
  }
  assert {
    condition     = one(google_compute_firewall.api_ingress_firewall[0].allow).protocol == "tcp" && one(google_compute_firewall.api_ingress_firewall[0].allow).ports == tolist(["6443"])
    error_message = "The API rule must open the API port only."
  }
  assert {
    condition     = keys(google_compute_firewall.pod_ingress_firewalls) == ["v4"] && google_compute_firewall.pod_ingress_firewalls["v4"].source_ranges == toset(["192.168.0.0/16"])
    error_message = "Pod CIDRs must reach the nodes."
  }
  assert {
    condition     = length(google_service_account.node_service_accounts) == 2 && google_service_account.node_service_accounts["control-plane"].account_id == "captf-team-a-demo-${substr(sha256("team-a/demo"), 0, 8)}-cp"
    error_message = "Two node service accounts are created, named after the cluster."
  }
  assert {
    condition     = length(google_project_iam_member.node_project_roles) == 9
    error_message = "The default roles (7 control plane, 2 worker) must be granted."
  }
  assert {
    condition     = length(google_service_account_iam_member.node_service_account_users) == 2
    error_message = "The control-plane account must be a user of both node accounts."
  }
  assert {
    condition     = length(google_compute_global_address.api_global_address) == 0 && length(google_compute_security_policy.api_security_policy) == 0
    error_message = "No external load balancer by default."
  }
}

# A second identical apply keeps every id: nothing is replaced. OpenTofu
# reads run outputs only in a run's variables, so they are passed in there.
run "reapply_is_stable" {
  variables {
    previous_api_address_id           = run.happy_path.api_address_id
    previous_api_forwarding_rule_ids  = run.happy_path.api_forwarding_rule_ids
    previous_api_backend_service_ids  = run.happy_path.api_backend_service_ids
    previous_api_instance_group_ids   = run.happy_path.api_instance_group_ids
    previous_firewall_rule_ids        = run.happy_path.firewall_rule_ids
    previous_node_service_account_ids = run.happy_path.node_service_account_ids
    previous_control_plane_endpoint   = run.happy_path.control_plane_endpoint
  }

  assert {
    condition     = output.api_address_id == var.previous_api_address_id
    error_message = "A second apply must keep the API address."
  }
  assert {
    condition     = output.api_forwarding_rule_ids == var.previous_api_forwarding_rule_ids && output.api_backend_service_ids == var.previous_api_backend_service_ids
    error_message = "A second apply must keep the forwarding rules and backend services."
  }
  assert {
    condition     = output.api_instance_group_ids == var.previous_api_instance_group_ids
    error_message = "A second apply must keep the instance groups."
  }
  assert {
    condition     = output.firewall_rule_ids == var.previous_firewall_rule_ids && output.node_service_account_ids == var.previous_node_service_account_ids
    error_message = "A second apply must keep the firewall rules and service accounts."
  }
  assert {
    condition     = output.control_plane_endpoint == var.previous_control_plane_endpoint
    error_message = "The endpoint must not change."
  }
}

run "tags_on_taggable_resources" {
  variables {
    additional_tags = { team = "platform" }
  }

  assert {
    condition = google_compute_address.api_address[0].labels == tomap({
      "captf-io_cluster"    = "demo"
      "captf-io_namespace"  = "team-a"
      "captf-io_kind"       = "terraformcluster"
      "captf-io_name"       = "demo"
      "captf-io_managed-by" = "captf"
      "captf-io_template"   = ""
      "team"                = "platform"
    })
    error_message = "The API address must carry the mapped captf_tags and additional_tags."
  }
  assert {
    condition     = google_compute_forwarding_rule.api_forwarding_rules["kube_apiserver"].labels == google_compute_address.api_address[0].labels
    error_message = "The forwarding rule must carry the same labels."
  }
}

run "tags_mapping_long_value" {
  command = plan

  variables {
    captf_tags = {
      "captf.io/cluster"    = "demo"
      "captf.io/namespace"  = "team-a"
      "captf.io/kind"       = "TerraformCluster"
      "captf.io/name"       = "a.very-long-terraform-cluster-name-that-is-longer-than-sixty-three-characters"
      "captf.io/managed-by" = "captf"
      "captf.io/template"   = "Template.v2"
    }
  }

  assert {
    condition     = google_compute_address.api_address[0].labels["captf-io_name"] == "${substr("a_very-long-terraform-cluster-name-that-is-longer-than-sixty-three-characters", 0, 54)}-${substr(sha256("a.very-long-terraform-cluster-name-that-is-longer-than-sixty-three-characters"), 0, 8)}"
    error_message = "A value over 63 characters keeps 54 characters plus the hash of the original."
  }
  assert {
    condition     = google_compute_address.api_address[0].labels["captf-io_template"] == "template_v2"
    error_message = "Values are lowercased and invalid characters become _."
  }
}

run "user_endpoint_skips_load_balancer" {
  variables {
    control_plane_endpoint = { host = "api.example.com", port = 443 }
  }

  assert {
    condition     = output.control_plane_endpoint == { host = "api.example.com", port = 443 }
    error_message = "A user endpoint is passed through."
  }
  assert {
    condition     = output.exports.api == null
    error_message = "exports.api is null for a user endpoint: there is nothing to register with."
  }
  assert {
    condition = alltrue([
      length(google_compute_address.api_address) == 0,
      length(google_compute_forwarding_rule.api_forwarding_rules) == 0,
      length(google_compute_region_backend_service.api_region_backend_services) == 0,
      length(google_compute_instance_group.api_instance_groups) == 0,
      length(google_compute_firewall.api_ingress_firewall) == 0,
      length(google_compute_global_address.api_global_address) == 0,
    ])
    error_message = "A user endpoint creates no load balancer, instance group or API firewall rule."
  }
  assert {
    condition     = output.health.state == "running" && output.health.healthy
    error_message = "With a user endpoint the cluster is running."
  }
  assert {
    condition     = length(data.google_compute_subnetworks.proxy_subnetworks) == 0
    error_message = "No proxy-only subnet is needed without a load balancer."
  }
}

run "cluster_network_null" {
  variables {
    cluster_network = null
  }

  assert {
    condition     = output.control_plane_endpoint.port == 6443 && length(google_compute_firewall.pod_ingress_firewalls) == 0
    error_message = "A null cluster_network means port 6443 and no pod rule."
  }
}

run "pod_cidrs_dual_stack" {
  command = plan

  variables {
    cluster_network = {
      pods            = ["192.168.0.0/16", "fd00:10:244::/56"]
      services        = []
      service_domain  = null
      api_server_port = null
    }
  }

  assert {
    condition     = google_compute_firewall.pod_ingress_firewalls["v4"].source_ranges == toset(["192.168.0.0/16"]) && google_compute_firewall.pod_ingress_firewalls["v6"].source_ranges == toset(["fd00:10:244::/56"])
    error_message = "Dual-stack pod CIDRs get one rule per address family."
  }
}

run "rke2_listeners" {
  variables {
    distribution = "rke2"
  }

  assert {
    condition     = keys(google_compute_forwarding_rule.api_forwarding_rules) == ["kube_apiserver", "rke2_supervisor"]
    error_message = "rke2 adds the supervisor listener."
  }
  assert {
    condition     = google_compute_forwarding_rule.api_forwarding_rules["rke2_supervisor"].ip_address == google_compute_forwarding_rule.api_forwarding_rules["kube_apiserver"].ip_address && google_compute_forwarding_rule.api_forwarding_rules["rke2_supervisor"].port_range == "9345"
    error_message = "The supervisor listens on 9345 on the API address (RKE2 joins at https://<endpoint host>:9345)."
  }
  assert {
    condition     = one(google_compute_firewall.api_ingress_firewall[0].allow).ports == tolist(["6443", "9345"])
    error_message = "The API rule must open 9345 as well."
  }
  assert {
    condition     = length(google_compute_instance_group.api_instance_groups["us-central1-c"].named_port) == 2
    error_message = "Instance groups must name both ports."
  }
}

run "global_access" {
  command = plan

  variables {
    api_global_access = true
  }

  assert {
    condition     = google_compute_forwarding_rule.api_forwarding_rules["kube_apiserver"].allow_global_access
    error_message = "api_global_access must reach the forwarding rule."
  }
}

run "zones_pinned" {
  variables {
    zones = ["us-central1-c", "us-central1-a"]
  }

  assert {
    condition     = [for d in output.failure_domains : d.name] == ["us-central1-a", "us-central1-c"]
    error_message = "zones pins the failure domains, sorted."
  }
  assert {
    condition     = keys(google_compute_instance_group.api_instance_groups) == ["us-central1-a", "us-central1-c"]
    error_message = "Only the pinned zones get instance groups."
  }
}

run "exports_shape" {
  assert {
    condition     = toset(keys(output.exports)) == toset(["api", "control_plane", "failure_domains", "name_prefix", "network", "node_network_tag", "project", "region", "schema", "subnetwork", "worker"])
    error_message = "exports must hold exactly the captf.io/gcp-cluster/v1 keys."
  }
  assert {
    condition     = output.exports.network == "https://www.googleapis.com/compute/v1/projects/captf-test/global/networks/captf-vpc" && output.exports.subnetwork == "https://www.googleapis.com/compute/v1/projects/captf-test/regions/us-central1/subnetworks/captf-nodes"
    error_message = "exports carry the network and subnetwork self links."
  }
  assert {
    condition     = output.exports.failure_domains == { for z in ["us-central1-a", "us-central1-b", "us-central1-c", "us-central1-f"] : z => { zone = z } }
    error_message = "exports.failure_domains maps each zone to its attributes."
  }
  assert {
    condition     = output.exports.name_prefix == "captf-team-a-demo-${substr(sha256("team-a/demo"), 0, 8)}" && output.exports.node_network_tag == "${output.exports.name_prefix}-node"
    error_message = "exports carry the name prefix and the node network tag."
  }
  assert {
    condition     = output.exports.control_plane.network_tags == [output.exports.node_network_tag, "${output.exports.name_prefix}-control-plane"] && output.exports.worker.network_tags == [output.exports.node_network_tag, "${output.exports.name_prefix}-worker"]
    error_message = "Every node carries the node tag plus its role tag."
  }
  assert {
    condition     = output.exports.control_plane.service_account == "${google_service_account.node_service_accounts["control-plane"].account_id}@captf-test.iam.gserviceaccount.com" && output.exports.worker.service_account == "${google_service_account.node_service_accounts["worker"].account_id}@captf-test.iam.gserviceaccount.com"
    error_message = "exports carry the node service accounts."
  }
  assert {
    condition     = output.exports.api.instance_groups == { for z, g in google_compute_instance_group.api_instance_groups : z => g.self_link }
    error_message = "exports.api.instance_groups are the groups' self links."
  }
}

run "node_identity_byo" {
  variables {
    control_plane_service_account = "cp@captf-test.iam.gserviceaccount.com"
    worker_service_account        = "worker@captf-test.iam.gserviceaccount.com"
  }

  assert {
    condition     = length(google_service_account.node_service_accounts) == 0 && length(google_project_iam_member.node_project_roles) == 0 && length(google_service_account_iam_member.node_service_account_users) == 0
    error_message = "Brought service accounts are used as they are: nothing is created or granted."
  }
  assert {
    condition     = output.exports.control_plane.service_account == "cp@captf-test.iam.gserviceaccount.com" && output.exports.worker.service_account == "worker@captf-test.iam.gserviceaccount.com"
    error_message = "exports carry the brought accounts."
  }
  assert {
    condition     = google_compute_firewall.node_internal_firewall[0].target_service_accounts == toset(["cp@captf-test.iam.gserviceaccount.com", "worker@captf-test.iam.gserviceaccount.com"])
    error_message = "Firewall rules target the brought accounts."
  }
  assert {
    condition     = google_compute_firewall.api_ingress_firewall[0].target_service_accounts == toset(["cp@captf-test.iam.gserviceaccount.com"])
    error_message = "The API rule targets the control-plane account only."
  }
}

run "node_identity_byo_control_plane_only" {
  variables {
    control_plane_service_account = "cp@captf-test.iam.gserviceaccount.com"
  }

  assert {
    condition     = keys(google_service_account.node_service_accounts) == ["worker"] && length(google_project_iam_member.node_project_roles) == 2
    error_message = "Only the worker account is created and granted roles."
  }
  assert {
    condition     = google_service_account_iam_member.node_service_account_users["worker"].member == "serviceAccount:cp@captf-test.iam.gserviceaccount.com"
    error_message = "The brought control-plane account may act as the created worker account."
  }
}

# The endpoint guard: once the load balancer exists, every input that decides
# the endpoint is fixed (CONVENTIONS.md section 12). Each run is a plan that
# would change one of them.

run "rejects_api_load_balancer_public_change" {
  command = plan

  variables {
    api_load_balancer_public = true
    api_allowed_cidrs        = ["203.0.113.0/24"]
  }

  expect_failures = [terraform_data.api_endpoint_guard]
}

run "rejects_network_change" {
  command = plan

  variables {
    network = "other-vpc"
  }

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

  expect_failures = [terraform_data.api_endpoint_guard]
}

run "rejects_subnetwork_change" {
  command = plan

  variables {
    subnetwork = "captf-nodes-2"
  }

  override_data {
    target = data.google_compute_subnetworks.node_subnetworks
    values = {
      subnetworks = [{
        description              = ""
        ip_cidr_range            = "10.0.0.0/20"
        name                     = "captf-nodes-2"
        network                  = "https://www.googleapis.com/compute/v1/projects/captf-test/global/networks/captf-vpc"
        network_name             = "captf-vpc"
        network_self_link        = "captf-vpc"
        private_ip_google_access = true
        self_link                = "https://www.googleapis.com/compute/v1/projects/captf-test/regions/us-central1/subnetworks/captf-nodes-2"
      }]
    }
  }

  expect_failures = [terraform_data.api_endpoint_guard]
}

run "rejects_project_change" {
  command = plan

  variables {
    network_project = "captf-test"
  }

  override_data {
    target = data.google_client_config.provider_config
    values = {
      project = "captf-other"
      region  = "us-central1"
      zone    = ""
    }
  }

  expect_failures = [terraform_data.api_endpoint_guard]
}

run "rejects_region_change" {
  command = plan

  override_data {
    target = data.google_client_config.provider_config
    values = {
      project = "captf-test"
      region  = "us-east1"
      zone    = ""
    }
  }

  expect_failures = [terraform_data.api_endpoint_guard]
}

run "rejects_api_server_port_change" {
  command = plan

  variables {
    cluster_network = {
      pods            = ["192.168.0.0/16"]
      services        = ["10.128.0.0/12"]
      service_domain  = "cluster.local"
      api_server_port = 8443
    }
  }

  expect_failures = [terraform_data.api_endpoint_guard]
}
