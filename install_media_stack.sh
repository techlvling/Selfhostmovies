#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
# 🎬 Selfhostmovies Installer v1.2 (Tech Lvling)
# Auto-fixes line endings, adds style & power
# ─────────────────────────────────────────────

# --- 🩹 Auto Fix CRLF Line Endings ---
if file "$0" | grep -q "CRLF"; then
  echo -e "\033[1;33m[!] CRLF line endings detected — fixing with dos2unix...\033[0m"
  if ! command -v dos2unix &>/dev/null; then
    echo -e "\033[1;34mInstalling dos2unix...\033[0m"
    sudo apt update -y && sudo apt install -y dos2unix
  fi
  sudo dos2unix "$0" >/dev/null 2>&1
  echo -e "\033[1;32m[✓] Fixed line endings — re-running installer...\033[0m"
  exec bash "$0"
  exit 0
fi

# --- Animation Setup ---
spinner="/-\|"
function animate() {
  local msg=$1
  echo -ne "$msg "
  while :; do
    for i in {0..3}; do
      echo -ne "\b${spinner:i:1}"
      sleep 0.1
    done
  done
}

function stop_animation() {
  kill "$1" &>/dev/null || true
  printf "\b✓\n"
}

# --- Animated Intro ---
clear
echo -e "\033[1;36m"
echo "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
echo "┃        🚀  Tech Lvling Presents...           ┃"
echo "┃           🧠 Selfhostmovies v1.2             ┃"
echo "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"
echo -e "\033[0m"
sleep 1
echo
animate "Booting media stack..." & PID=$!
sleep 2; stop_animation $PID
animate "Loading Docker modules..." & PID=$!
sleep 2; stop_animation $PID
animate "Contacting Jellyfin gods..." & PID=$!
sleep 2; stop_animation $PID
echo -e "\033[1;32mSystem online. Let's build your own Netflix.\033[0m"
sleep 1
echo "───────────────────────────────────────────────"

# --- Step 1: Dependencies ---
echo -e "\n\033[1;34m[ Step 1/5 ] Installing dependencies...\033[0m"
sudo apt update -y
sudo apt install -y curl git ca-certificates gnupg lsb-release ipcalc dos2unix

# --- Step 2: Network Setup ---
echo -e "\n\033[1;34m[ Step 2/5 ] Network configuration...\033[0m"
IFACE=$(ip -o -4 route show to default | awk '{print $5}' || true)
CIDR=$(ip -o -f inet addr show "$IFACE" | awk '{print $4}' | head -n1 || echo "")
CURRENT_IP=$(echo "$CIDR" | cut -d/ -f1)
GATEWAY=$(ip route | awk '/default/ {print $3; exit}')

echo "Detected interface: $IFACE"
echo "Detected IP:        $CURRENT_IP"
echo "Detected gateway:   $GATEWAY"
echo "───────────────────────────────────────────────"
read -rp "Would you like to make this IP static? (y/N): " STATIC
if [[ "${STATIC:-n}" =~ ^[Yy]$ ]]; then
  NETPLAN_FILE="/etc/netplan/99-selfhost-static.yaml"
  sudo tee "$NETPLAN_FILE" > /dev/null <<YAML
network:
  version: 2
  renderer: networkd
  ethernets:
    $IFACE:
      dhcp4: no
      addresses:
        - ${CIDR}
      routes:
        - to: default
          via: ${GATEWAY}
      nameservers:
        addresses: [1.1.1.1,8.8.8.8]
YAML
  sudo netplan apply
  echo "Static IP applied successfully."
else
  echo "Using DHCP (default)."
fi

# --- Step 3: Docker Setup ---
echo -e "\n\033[1;34m[ Step 3/5 ] Installing Docker + Compose...\033[0m"
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
| sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update -y
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable --now docker

# --- Step 4: Media Folders ---
echo -e "\n\033[1;34m[ Step 4/5 ] Setting up media folders...\033[0m"
sudo mkdir -p /mnt/media/{Movies,TV,Downloads,docker}
sudo chown -R 1000:1000 /mnt/media
sudo chmod -R 775 /mnt/media

# --- Step 5: VPN Setup ---
echo -e "\n\033[1;34m[ Step 5/5 ] Optional VPN setup (Mullvad WireGuard)...\033[0m"
read -rp "Enter Mullvad WireGuard Private Key (or press Enter to skip): " MULLVAD_KEY
if [ -n "${MULLVAD_KEY:-}" ]; then
  read -rp "Enter Mullvad WireGuard Address (e.g. 10.64.42.2/32): " MULLVAD_ADDR
fi

# --- Generate Docker Compose ---
COMPOSE_FILE="/mnt/media/docker/docker-compose.yml"
echo -e "\n\033[1;34mGenerating docker-compose.yml...\033[0m"
cat > "$COMPOSE_FILE" <<YML
version: "3.9"

services:
  gluetun:
    image: qmcgaw/gluetun
    container_name: gluetun
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun
    environment:
      - VPN_SERVICE_PROVIDER=mullvad
      - VPN_TYPE=wireguard
YML

if [ -n "${MULLVAD_KEY:-}" ]; then
cat >> "$COMPOSE_FILE" <<YML
      - WIREGUARD_PRIVATE_KEY=${MULLVAD_KEY}
      - WIREGUARD_ADDRESSES=${MULLVAD_ADDR}
YML
fi

cat >> "$COMPOSE_FILE" <<'YML'
      - SERVER_CITIES=Singapore
      - TZ=Asia/Kolkata
    volumes:
      - /mnt/media/docker/gluetun:/gluetun
    ports:
      - 8112:8112
      - 9696:9696
    restart: unless-stopped

  prowlarr:
    image: lscr.io/linuxserver/prowlarr:latest
    container_name: prowlarr
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Asia/Kolkata
    volumes:
      - /mnt/media/docker/prowlarr:/config
YML

if [ -n "${MULLVAD_KEY:-}" ]; then
  echo '    network_mode: "container:gluetun"' >> "$COMPOSE_FILE"
fi

cat >> "$COMPOSE_FILE" <<'YML'
    restart: unless-stopped

  radarr:
    image: lscr.io/linuxserver/radarr:latest
    container_name: radarr
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Asia/Kolkata
    volumes:
      - /mnt/media/docker/radarr:/config
      - /mnt/media/Movies:/movies
      - /mnt/media/Downloads:/downloads
    ports:
      - 7878:7878
    restart: unless-stopped

  sonarr:
    image: lscr.io/linuxserver/sonarr:latest
    container_name: sonarr
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Asia/Kolkata
    volumes:
      - /mnt/media/docker/sonarr:/config
      - /mnt/media/TV:/tv
      - /mnt/media/Downloads:/downloads
    ports:
      - 8989:8989
    restart: unless-stopped

  deluge:
    image: lscr.io/linuxserver/deluge:latest
    container_name: deluge
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Asia/Kolkata
    volumes:
      - /mnt/media/docker/deluge:/config
      - /mnt/media/Downloads:/downloads
YML

if [ -n "${MULLVAD_KEY:-}" ]; then
  echo '    network_mode: "container:gluetun"' >> "$COMPOSE_FILE"
fi

cat >> "$COMPOSE_FILE" <<'YML'
    restart: unless-stopped

  jellyfin:
    image: lscr.io/linuxserver/jellyfin:latest
    container_name: jellyfin
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Asia/Kolkata
    volumes:
      - /mnt/media/docker/jellyfin:/config
      - /mnt/media:/media
    ports:
      - 8096:8096
    restart: unless-stopped

  watchtower:
    image: containrrr/watchtower
    container_name: watchtower
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    restart: unless-stopped
YML

# --- Launch Containers ---
echo -e "\n\033[1;32mStarting containers...\033[0m"
cd /mnt/media/docker
sudo docker compose up -d

# --- Outro ---
clear
sleep 1
echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e "\033[1;32m 🎉 Setup Complete! Welcome to your media empire! 🎉\033[0m"
echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
sleep 1
echo -e "👉  Jellyfin:  http://$CURRENT_IP:8096"
echo -e "👉  Radarr:    http://$CURRENT_IP:7878"
echo -e "👉  Sonarr:    http://$CURRENT_IP:8989"
echo -e "👉  Prowlarr:  http://$CURRENT_IP:9696"
echo -e "👉  Deluge:    http://$CURRENT_IP:8112"
sleep 1
echo
if [ -n "${MULLVAD_KEY:-}" ]; then
  echo -e "\033[1;33mVPN ENABLED:\033[0m Deluge & Prowlarr are routed through Gluetun (Mullvad)."
else
  echo -e "\033[1;33mVPN DISABLED:\033[0m Running locally (no tunneling)."
fi
echo
sleep 1
echo -e "\033[1;35m👾 Made with ❤️ by Tech Lvling — Subscribe for more setups!\033[0m"
echo -e "\033[1;34m📺 YouTube: https://www.youtube.com/@techlvling\033[0m"
echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
sleep 2
