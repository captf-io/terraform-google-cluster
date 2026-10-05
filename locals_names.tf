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

# Names of every cloud resource, derived from the Cluster's key with a hash
# that keeps truncated names unique (CONVENTIONS.md section 6).
locals {
  cluster_key  = "${var.captf_cluster.namespace}/${var.captf_cluster.name}"
  cluster_hash = substr(sha256(local.cluster_key), 0, 8)
  # Kubernetes names may hold dots; Compute Engine names may not
  # (https://cloud.google.com/compute/docs/naming-resources).
  cluster_slug = replace(lower("captf-${var.captf_cluster.namespace}-${var.captf_cluster.name}"), "/[^a-z0-9-]/", "-")

  # Compute Engine names are at most 63 characters. 48 leaves room for the
  # longest suffix appended ("-api-supervisor", "-pod-ingress-v4"); 48 - 9
  # leaves room for "-" and the hash.
  name_max    = 48
  name_prefix = "${trimsuffix(substr(local.cluster_slug, 0, local.name_max - 9), "-")}-${local.cluster_hash}"

  # Service account IDs are 6 to 30 characters
  # (https://cloud.google.com/iam/docs/service-accounts-create): 30 - 9 - 3
  # leaves room for the hash and the role suffix.
  service_account_prefix = "${trimsuffix(substr(local.cluster_slug, 0, 30 - 9 - 3), "-")}-${local.cluster_hash}"
  service_account_ids = {
    control-plane = "${local.service_account_prefix}-cp"
    worker        = "${local.service_account_prefix}-wk"
  }

  # Network tags. cloud-provider-gcp targets Service firewall rules at a node
  # tag (its gce.conf node-tags), so every node carries node_network_tag.
  node_network_tag          = "${local.name_prefix}-node"
  control_plane_network_tag = "${local.name_prefix}-control-plane"
  worker_network_tag        = "${local.name_prefix}-worker"

  # Descriptions of resources that cannot carry labels. They name only the
  # Cluster, never captf_tags: description is ForceNew on addresses, target
  # proxies and instance groups, and captf.io/template can change.
  description = "CAPTF cluster ${local.cluster_key}"
}
