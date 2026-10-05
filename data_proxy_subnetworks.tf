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

# The proxy-only subnet the internal proxy load balancer needs, part of the
# network you bring: one per region and network, shared by every Envoy-based
# load balancer there (https://cloud.google.com/load-balancing/docs/proxy-only-subnets).
data "google_compute_subnetworks" "proxy_subnetworks" {
  count = local.internal_lb ? 1 : 0

  # AIP-160 filter on the Compute list API; the network is matched in
  # locals_cluster.tf because the data source cannot filter on it. No
  # postcondition: data sources are read during destroy too, and a missing
  # subnet must not block it (api_forwarding_rules.tf checks instead).
  filter  = "purpose = \"REGIONAL_MANAGED_PROXY\""
  project = local.network_project
  region  = local.region
}
