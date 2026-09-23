---
name: admin-steps-run-through-sudo
description: Why apply's administrator script runs through sudo with SUDO_ASKPASS and DISPLAY, and not osascript or sudo -A
metadata:
  type: reference
---

Learned 2026-09-23, during the first real `Anaclast apply`.

- `osascript` `with administrator privileges` runs the script under Security.framework's authtrampoline. TCC treats that as its own responsible process, so writing `/etc/pam.d` fails with "Operation not permitted" even as root. The directory is guarded by the SystemPolicySysAdminFiles service.
- `sudo` keeps the calling app as the responsible process. That app, a terminal or Anaclast itself, needs Full Disk Access for the `sudo_local` write.
- Without a terminal, sudo falls back to `SUDO_ASKPASS` only while `DISPLAY` is set ([tgetpass.c](https://github.com/apple-oss-distributions/sudo/blob/9d15835617972783e565818fae7ea047626b1e5c/sudo/src/tgetpass.c#L135-L151)). An empty value is enough.
- `sudo -A` is not a substitute. Apple's sudo then sets the PAM data `askpass-enabled` ([pam.c](https://github.com/apple-oss-distributions/sudo/blob/9d15835617972783e565818fae7ea047626b1e5c/sudo/plugins/sudoers/auth/pam.c#L270-L279)), and pam_tid returns without showing Touch ID ([pam_tid.c](https://github.com/apple-oss-distributions/pam_modules/blob/f777092aa90f5b2b57e40d7abf51e9f1b1b34be3/modules/pam_tid/pam_tid.c#L102-L108)).

**How to apply:** keep the sudo route. The Machine window has no terminal, so it depends on `DISPLAY` plus the bundled `askpass` dialog for its password fallback. Touch ID comes first either way. Related: [[report-live-state]].
