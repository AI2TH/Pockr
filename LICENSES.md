# Licensing

This project bundles several open-source components. Each has its own license with different rules about how you can use them in your own projects.

---

## Component licenses

| Component | License | What it means |
|---|---|---|
| **QEMU** | GPLv2 (TCG: BSD/Expat) | Can use commercially; binary distribution requires source availability |
| **Alpine Linux** | MIT / various | Permissive; keep copyright notices |
| **Docker** | Apache 2.0 | Permissive; keep copyright and NOTICE file |
| **Flutter** | BSD 3-Clause | Permissive; keep copyright notices |

---

## Can I use these in my own project?

**Short answer: yes for all four, including commercial/proprietary apps.**

Flutter, Alpine, and Docker are permissive licenses — include their copyright notices and you're good.

QEMU is the only one that needs attention.

---

## QEMU (GPLv2) — the full picture

### What GPLv2 requires when you distribute QEMU binaries

If you ship QEMU binaries inside your app (APK, installer, etc.) you must:

1. Include the full GPLv2 license text (in-app About screen or bundled file)
2. Include the TCG BSD/Expat license text
3. Include third-party notices for QEMU's dependencies (glib, zlib, pixman, etc.)
4. Make the QEMU source code available — either:
   - Link to the upstream source tag you built from, **or**
   - Provide a written offer to supply the source on request (valid for 3 years)

### Does GPLv2 "infect" my app code?

**No — if QEMU runs as a separate process.**

GPLv2's copyleft effect applies when you *link* GPLv2 code into your binary. If your app communicates with QEMU over a socket or pipe (as this project does), your own source code is not required to be GPLv2.

```
Your app code  ──spawns──▶  QEMU process  ──socket──▶  Alpine VM
    (any license)                (GPLv2)
```

This is the same model used by any app that launches an external program.

### What you do NOT need to do

- Open-source your own app code
- Use a GPL-compatible license for your app
- Share your app's source

---

## Reusing this project in other projects

| Your project type | OK? | Notes |
|---|---|---|
| Open source (any license) | Yes | Comply with QEMU binary distribution rules |
| Commercial closed-source app | Yes | Same — QEMU runs as a subprocess, not linked |
| Embedding QEMU as a linked library | Only if GPLv2-compatible | Linking triggers copyleft |
| Play Store distribution | Yes | Disclose QEMU source; follow ForegroundService policy |

---

## Compliance checklist

If you ship this app (or a fork) publicly:

- [ ] GPLv2 license text included in app (About / Licenses screen)
- [ ] TCG BSD license text included
- [ ] Third-party notices for QEMU deps (glib, zlib, pixman, libffi, etc.)
- [ ] QEMU source reference or written offer available
- [ ] Alpine Linux and Docker license notices included
- [ ] Flutter BSD 3-Clause notice included

---

## Sources

| Topic | Source |
|---|---|
| QEMU license (GPLv2 + TCG BSD) | https://wiki.qemu.org/License |
| Apache 2.0 (Docker) | https://www.apache.org/licenses/LICENSE-2.0 |
| MIT (Alpine packages) | https://opensource.org/licenses/MIT |
| BSD 3-Clause (Flutter) | https://opensource.org/licenses/BSD-3-Clause |
| GPLv2 | https://www.gnu.org/licenses/old-licenses/gpl-2.0.html |
