# Public Resolver Change

An interactive, robust Bash script to instantly change your Linux system's DNS resolvers and guarantee they persist across network restarts and server reboots. 

Instead of fighting the operating system with cron jobs, this tool utilizes native OS network managers or filesystem-level locks to ensure your DNS remains permanent.

## ✨ Features

* **Interactive CLI:** Simple menu-driven interface to select your settings.
* **6 Major DNS Providers Supported:** Google, Cloudflare, OpenDNS, Quad9, ControlD, and GCore DNS.
* **Two Persistence Methods:**
  * **Native OS (Recommended):** Safely hooks into `systemd-resolved` using drop-in directories so it never conflicts with OS updates.
  * **Lock System (chattr):** An immutable filesystem lock for stubborn server environments (like complex cloud-init stacks) that forcefully overwrite DNS records.

## 🚀 Quick Run

Run this single command to launch the interactive setup menu (requires root privileges):

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Luveedu/Public-Resolver-Change/refs/heads/main/nsetup.sh)"
