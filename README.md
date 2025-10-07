# 🎬 Selfhostmovies – Build Your Own Netflix (by Tech Lvling)
https://www.youtube.com/@TechLeveling

Tired of hunting for your favorite shows across sketchy sites?  
Let’s fix that. This setup turns your PC or server into your **own private streaming hub** — totally free, no subscriptions, no ads, no BS.

> ⚙️ Powered by: **Docker + Jellyfin + Sonarr + Radarr + Prowlarr + Deluge**
> 
> 🌐 Optional: **VPN (Mullvad via Gluetun)** – For the privacy.

---

## ⚡ Quick Start (1-minute setup)

💡 **Pre-Check (run this once):**
```bash
sudo apt update && sudo apt install -y git dos2unix
git clone https://github.com/techlvling/Selfhostmovies.git
cd Selfhostmovies
chmod +x install_media_stack.sh
sudo ./install_media_stack.sh
