# Changelog

All notable changes to this repository will be documented in this file.

## [1.1.0] - 2026-09-21

### Changed
- Refactored `auroraops-base` into clean child capability repository for parent `auroraops-control`.
- Removed old-monolith hardcoded paths (`/root/AuroraOps/scripts`) in `system.base`.
- Decoupled Docker service restarts and Hysteria port-hopping from `system.firewall`.
- Relocated non-base roles:
  - `system.zerotier` and `personalization.user_management` to `auroraops-services`.
  - `system.benchmark`, `system.reinstall`, and `system.systemd_priority` to `auroraops-ops`.
- Pinned collection dependencies (`ansible.posix: 2.1.0`, `community.general: 13.1.0`).
- Reconciled collection version and root compatibility metadata to `1.1.0`.
