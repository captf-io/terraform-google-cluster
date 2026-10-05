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

# One unmanaged instance group per zone, the API backends. Control-plane
# machines join their zone's group in their own state, so a machine's destroy
# deregisters it (machine.md "Control-plane machines"; DESIGN.md decision 1).
resource "google_compute_instance_group" "api_instance_groups" {
  for_each = local.module_endpoint ? toset(local.zones) : toset([])

  description = "${local.description}: control-plane nodes in ${each.key}"
  name        = "${local.name_prefix}-control-plane"
  network     = local.network_self_link
  project     = local.project
  zone        = each.key

  dynamic "named_port" {
    for_each = local.api_listeners

    content {
      name = named_port.value.port_name
      port = named_port.value.backend_port
    }
  }

  lifecycle {
    # Machines own the membership; this group never lists instances itself.
    ignore_changes = [instances]
  }
}
