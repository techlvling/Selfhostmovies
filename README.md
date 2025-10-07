# Selfhostmovies

One-line clone-and-run installer for a local Netflix-style media server:
Radarr, Sonarr, Prowlarr, Deluge, Jellyfin — optional Mullvad VPN (WireGuard) via Gluetun.

---

## Quick start (recommended)

**1) Pre-check (run once to avoid Windows line-ending problems):**
```bash
sudo apt update && sudo apt install -y git dos2unix
