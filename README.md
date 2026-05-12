# Public Resolver Change (nsetup.sh)

A lightweight Bash script to instantly change your system's DNS resolvers and ensure they persist across reboots and system updates using a dedicated Cron job.

## 🚀 Quick Install (Cloudflare DNS)

Run this single command to set your DNS to Cloudflare (1.1.1.1) and install the persistence service:

```bash
curl -sSL https://raw.githubusercontent.com/Luveedu/Public-Resolver-Change/refs/heads/main/nsetup.sh | sudo bash