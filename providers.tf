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

# The Google provider. Credentials come only from the identity Secret
# (GOOGLE_CREDENTIALS or GOOGLE_APPLICATION_CREDENTIALS); a null project or
# region falls back to GOOGLE_PROJECT and GOOGLE_REGION from the same Secret.
provider "google" {
  # Every label is set explicitly from local.tags (CONVENTIONS.md section 7),
  # so the labels on a resource are exactly the ones the README documents.
  add_terraform_attribution_label = false
  project                         = var.project
  region                          = var.region
}
