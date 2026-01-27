Title: Authoritative Citations for Android VM Container App Architecture

Purpose
- Consolidate authoritative sources validating claims in [ARCHITECTURE.md](ARCHITECTURE.md:1) and [ARCHITECTURE2.md](ARCHITECTURE2.md:1).
- Provide verbatim excerpts or succinct paraphrases with URLs to support line-precise corrections.

1) Docker Engine — Rootless Mode
- URL: https://docs.docker.com/engine/security/rootless/
- Key points:
  - Rootless mode executes the Docker daemon and containers inside a user namespace. It requires certain prerequisites.
  - Prerequisites include availability of the commands newuidmap and newgidmap, provided by the uidmap package, and subordinate UID/GID mappings in /etc/subuid and /etc/subgid.
  - Rootless mode does not use binaries with SETUID bits or file capabilities, except newuidmap and newgidmap, which are needed to allow multiple UIDs/GIDs to be used in the user namespace.
- Implication for Android:
  - Stock Android kernels often disable CONFIG_USER_NS; when user namespaces are unavailable and uidmap tooling is absent, Docker rootless prerequisites are not satisfied.

2) Podman — Daemonless, User-level Operation
- URL: https://docs.podman.io/en/latest/markdown/podman.1.html
- Excerpt:
  - “Podman (Pod Manager) is a fully featured container engine that is a simple daemonless tool… Most Podman commands can be run as a regular user, without requiring additional privileges.”
- Implication:
  - Even with user-level operation, container runtime expectations still rely on kernel features (namespaces, cgroups, overlayfs) that are limited or unavailable to Android applications.

3) QEMU — System Emulation Invocation (Network options context)
- URL: https://www.qemu.org/docs/master/system/invocation.html
- Excerpt (Network options → user mode host forwarding):
  - "hostfwd=[tcp|udp|unix]:[[hostaddr]:hostport|hostpath]-[guestaddr]:guestport"
  - "Redirect incoming TCP, UDP or UNIX connections to the host port hostport to the guest IP address guestaddr on guest port guestport. If guestaddr is not specified, its value is x.x.x.15 (default first address given by the built-in DHCP server). By specifying hostaddr, the rule can be bound to a specific host interface. If no connection type is set, TCP is used. This option can be given multiple times."
  - Examples shown in the manual:
    - "qemu-system-x86_64 -nic user,hostfwd=tcp:127.0.0.1:6001-:6000"
    - "qemu-system-x86_64 -nic user,hostfwd=tcp::5555-:23"

4) QEMU — User Mode Emulation Overview
- URL: https://www.qemu.org/docs/master/user/main.html
- Key understanding:
  - QEMU provides user-space emulation and system emulation; the app architecture proposes system emulation (qemu-system-aarch64/x86_64) to provide a full guest Linux OS independent of host kernel constraints.

5) QEMU — Licensing
- URL: https://wiki.qemu.org/License
- Excerpts:
  - “QEMU as a whole is released under the GNU General Public License, version 2.”
  - “Parts of QEMU have specific licenses compatible with the GPLv2… The Tiny Code Generator (TCG) is released under the BSD license…”
- Implication:
  - Distributing QEMU binaries inside an APK requires GPLv2 compliance (license text, notices, source offering as applicable), and acknowledging component licenses (e.g., TCG BSD).

6) QEMU — User Networking (slirp) and hostfwd
- URL: https://wiki.qemu.org/Documentation/Networking#User_Networking
- Excerpt (verbatim from the QEMU Wiki User Networking page):
  - "This is the default networking backend and generally is the easiest to use. It does not require root / Administrator privileges. It has the following limitations:"
  - "there is a lot of overhead so the performance is poor"
  - "in general, ICMP traffic does not work (so you cannot use ping within a guest)"
  - "on Linux hosts, ping does work from within the guest, but it needs initial setup by root (once per host) -- see the steps below"
  - "the guest is not directly accessible from the host or the external network"
- Configuration notes on slirp (user networking):
  - "You can configure User Networking using the -netdev user command line option."
  - "You can isolate the guest from the host (and broader network) using the restrict option... You can selectively override this using hostfwd and guestfwd options."

7) Android Kernel Config — AOSP Defconfig showing CONFIG_USER_NS disabled
- URL (Google Git): https://android.googlesource.com/kernel/x86_64/+/android-x86_64-fugu-3.10-n-preview-1/arch/arm/configs/bonito_defconfig
- Verbatim lines (as rendered in Google Git):
  - “# CONFIG_UTS_NS is not set”
  - “# CONFIG_IPC_NS is not set”
  - “# CONFIG_USER_NS is not set”
  - “# CONFIG_PID_NS is not set”
- Implication:
  - This defconfig example shows multiple namespaces (including USER_NS) disabled. Similar hardening settings are common across device kernels; this blocks Docker rootless prerequisites and user-level container runtimes on-stock Android.

8) Play Store Policies — Background Execution and Foreground Service
- URLs to collect and add in final corrections:
  - Foreground service policies: (to be inserted)
  - Background execution limits: (to be inserted)
  - Battery/network usage disclosures best practices: (to be inserted)
- Implication:
  - Embedded VM apps must use ForegroundService for persistent background work, communicate resource usage transparently, and comply with background limits.

9) Google Play Policy — Device and Network Abuse
- Policy Center page: Device and Network Abuse (https://support.google.com/googleplay/android-developer)
- Verbatim clauses (captured from the policy page):
  - “We don’t allow apps that interfere with, disrupt, damage, or access in an unauthorized manner the user’s device, other devices or computers, servers, networks, application programming interfaces (APIs), or services, including but not limited to other apps on the device, any Google service, or an authorized carrier’s network.”
  - “Apps on Google Play must comply with the default Android system optimization requirements documented in the Core App Quality guidelines for Google Play.”
  - “An app distributed via Google Play may not modify, replace, or update itself using any method other than Google Play’s update mechanism. Likewise, an app may not download executable code (such as dex, JAR, .so files) from a source other than Google Play. This restriction does not apply to code that runs in a virtual machine or an interpreter where either provides indirect access to Android APIs (such as JavaScript in a webview or browser).”
- Implication:
  - VM-based apps must avoid device/network abuse, rely solely on Play updates, avoid fetching native executables or code from non-Play sources, and ensure guest VM code does not indirectly access Android APIs.
Planned Mapping to Architecture Files
- Rootless premise and prerequisites:
  - [ARCHITECTURE.md](ARCHITECTURE.md:11), [ARCHITECTURE2.md](ARCHITECTURE2.md:9) — add Docker rootless prerequisites and Android kernel namespace limitations with AOSP defconfig citation.
- Networking via slirp hostfwd:
  - [ARCHITECTURE.md](ARCHITECTURE.md:69,107,118), [ARCHITECTURE2.md](ARCHITECTURE2.md:64,96,107) — include hostfwd syntax citation and limitations.
- Licensing compliance checklist:
  - [ARCHITECTURE.md](ARCHITECTURE.md:243), [ARCHITECTURE2.md](ARCHITECTURE2.md:238) — add GPLv2/TCG BSD compliance actions and third-party notices.
- Play policies:
  - [ARCHITECTURE.md](ARCHITECTURE.md:148), [ARCHITECTURE2.md](ARCHITECTURE2.md:213) — insert ForegroundService requirement and disclosure notes.
- Performance expectations:
  - [ARCHITECTURE.md](ARCHITECTURE.md:171), [ARCHITECTURE2.md](ARCHITECTURE2.md:204) — clarify KVM availability and VM overhead.

Next Actions
- Completed: Added explicit hostfwd syntax and examples from QEMU “Network options” (-netdev user, -nic user) with citation.
- Completed: Captured slirp limitations (performance overhead, ICMP/ping behavior, host reachability) and configuration notes (restrict, hostfwd/guestfwd) from the QEMU Wiki User Networking page.
- Capture Google Play policy URLs and key clauses for ForegroundService and background execution.
- Draft line-precise corrections with embedded reference links and update diagrams where useful.
