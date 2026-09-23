---
name: driver-extension-removal-needs-owner
description: On macOS 27 with SIP on, only the owner's System Settings toggle removes a leftover DriverKit extension such as Karabiner's VirtualHIDDevice
metadata:
  type: reference
---

2026-09-24, retiring Karabiner's DriverKit VirtualHIDDevice after Karabiner-Elements left the machine config:

- `systemextensionsctl uninstall` refuses while System Integrity Protection is on.
- Deactivating through Karabiner's VirtualHIDDevice manager fails with OSSystemExtensionErrorDomain code 13 when nobody approves the authorization, and an unattended run shows no dialog.
- The route that works is the toggle under System Settings > General > Login Items & Extensions > Driver Extensions, which asks for the owner's password or Touch ID.
- After the toggle the extension leaves `systemextensionsctl list` and its process exits, with no reboot.
- Root-owned leftovers stay behind: `/Library/Application Support/org.pqrs` with stale sockets and `/var/log/karabiner` with logs. launchd keeps inert enable records for the `org.pqrs.service.agent.*` agents, which are not loaded.

**Why:** an agent cannot approve the authorization, so every other route burns time and ends at the same toggle.

**How to apply:** go straight to the System Settings toggle, hand it to the owner, and confirm with `systemextensionsctl list`. Related: [[keyboard-never-bricks]], [[admin-steps-run-through-sudo]], [[use-owner-sudo-session]].
