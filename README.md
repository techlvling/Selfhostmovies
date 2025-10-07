# 🎬 Selfhostmovies – Build Your Own Netflix (by Tech Lvling)

Tired of hunting for your favorite shows across sketchy sites?  
Let’s fix that. This setup turns your PC or server into your **own private streaming hub** — totally free, no subscriptions, no ads, no BS.

> ⚙️ Powered by: **Docker + Jellyfin + Sonarr + Radarr + Prowlarr + Deluge**
> 
> 🌐 Optional: **VPN (Mullvad via Gluetun)** – For the privacy warriors.

---

## ⚡ Quick Start (1-minute setup)

💡 **Step 0 — Pre-Check (run this once):**
```bash
sudo apt update && sudo apt install -y git dos2unix

Step 1 — Clone and enter the repo
git clone https://github.com/techlvling/Selfhostmovies.git
cd Selfhostmovies
Step 2 — Make it executable
chmod +x install_media_stack.sh
Step 3 — Run the installer
sudo ./install_media_stack.sh
