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

# The public API address, the endpoint host when api_load_balancer_public is set: its own
# resource so it outlives a forwarding rule replacement. Global, because the
# external proxy load balancer is global (DESIGN.md decision 1).
resource "google_compute_global_address" "api_global_address" {
  count = local.external_lb ? 1 : 0

  address_type = "EXTERNAL"
  description  = "${local.description}: Kubernetes API"
  ip_version   = "IPV4"
  labels       = local.tags
  name         = "${local.name_prefix}-api"
  project      = local.project
}
