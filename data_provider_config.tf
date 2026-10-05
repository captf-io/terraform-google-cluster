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

# The provider's effective project and region, so a null project or region
# variable resolves to what the identity Secret configured.
data "google_client_config" "provider_config" {
  lifecycle {
    postcondition {
      condition     = self.project != null && self.project != ""
      error_message = "No GCP project: set spec.variables.project on the TerraformCluster, or GOOGLE_PROJECT in the identity Secret."
    }
    postcondition {
      condition     = self.region != null && self.region != ""
      error_message = "No GCP region: set spec.variables.region on the TerraformCluster, or GOOGLE_REGION in the identity Secret."
    }
  }
}
