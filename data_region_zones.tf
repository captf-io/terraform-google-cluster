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

# Every zone of the region, whatever its status: a zone that is DOWN for a
# while must not drop out of the failure domains (that would plan to destroy
# its instance group). node_internal_firewall.tf checks var.zones against it.
data "google_compute_zones" "region_zones" {
  project = local.project
  region  = local.region
}
