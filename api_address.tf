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

# The internal API address, the endpoint host: its own resource so it outlives
# a forwarding rule replacement, SHARED_LOADBALANCER_VIP so both listeners share it
# (https://cloud.google.com/load-balancing/docs/forwarding-rule-concepts).
resource "google_compute_address" "api_address" {
  count = local.internal_lb ? 1 : 0

  address_type = "INTERNAL"
  description  = "${local.description}: Kubernetes API"
  labels       = local.tags
  name         = "${local.name_prefix}-api"
  project      = local.project
  purpose      = "SHARED_LOADBALANCER_VIP"
  region       = local.region
  subnetwork   = local.subnetwork_self_link
}
