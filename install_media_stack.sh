#!/usr/bin/env bash
set -euo pipefail

# install_media_stack.sh
# - Sets optional static IP via netplan (interactive)
# - Installs Docker (and dependencies)
# - Creates /mnt/media layout
# - Writes docker-compose.yml with optional Mullvad WireGuard (Gluetun)
# - Starts the stack
#
# IMPORTANT: If you supply Mullvad WireGuard Private Key and Address when prompted,
# Deluge & Prowlarr will be routed through Gluetun. If you skip, everything runs locally.

echo "==> Prep: update & install prerequisites..."
sudo apt update -y
sudo apt install -y curl git ca-certificates gnupg lsb-release ipcalc dos2unix

# convert this script's line endings just in case (no harm)
if command -v dos2unix >/dev/null 2>&1; then
  dos2unix "$0" 2>/dev/null || true
fi

# -------------------------
# Detect network info
# -------------------------
IFACE=$(ip -o -4 route show to default | awk '{print $5}' || true)
if [ -z "$IFACE" ]; then
  echo "ERROR: Could not detect default network interface. Exiting."
  exit 1
fi

CIDR=$(ip -o -f inet addr show "$IFACE" | awk '{print $4}' | head -n1) || true
CURRENT_IP=$(echo "$CIDR" | cut -d/ -f1 || true)
CURRENT_CIDR="$CIDR"

GATEWAY=$(ip route | awk '/default/ {print $3; exit}' || true)
echo "Detected interface: $IFACE"
echo "Detected address:  ${CURRENT_CIDR:-unknown}"
echo "Detected gateway:  ${GATEWAY:-unknown}"
echo "-----------------------------------------"

# Ask user about static IP
read -rp "Make this IP static on this machine? (y/N): " MAKE_STATIC
if [[ "${MAKE_STATIC:-n}" =~ ^[Yy]$ ]]; then
  read -rp "Static IP to use [default: ${CURRENT_IP:-}]: " STATIC_IP
  STATIC_IP=${STATIC_IP:-$CURRENT_IP}
  if [ -z "$STATIC_IP" ]; then
    echo "No IP provided, aborting static setup."
  else
    NETPLAN_FILE="/etc/netplan/99-selfhost-static.yaml"
    echo "Writing netplan config to $NETPLAN_FILE"
    sudo tee "$NETPLAN_FILE" > /dev/null <<NETY
network:
  version: 2
  renderer: networkd
  ethernets:
    $IFACE:
      dhcp4: no
      addresses:
        - ${CURRENT_CIDR:-${STATIC_IP}/24}
      gateway4: ${GATEWAY:-}
      nameservers:
        addresses: [1.1.1.1,8.8.8.8]
NETY
    echo "Applying netplan..."
    sudo netplan apply || echo "netplan apply returned non-zero; check /etc/netplan"
    echo "Static config applied (if no error shown)."
  fi
else
  echo "Skipping static IP setup (DHCP remains)."
fi

echo "-----------------------------------------"
# -------------------------
# Docker install
# -------------------------
echo "==> Installing Docker & Compose plugin..."
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update -y
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable --now docker

# -------------------------
# Folder layout and perms
# -------------------------
echo "==> Creating media folders and docker workspace..."
sudo mkdir -p /mnt/media/{Movies,TV,Downloads,docker}
sudo chown -R 1000:1000 /mnt/media
sudo chmod -R 775 /mnt/media

# -------------------------
# Optional: ask for Mullvad WireGuard info
# -------------------------
echo
echo "OPTIONAL VPN (Mullvad WireGuard) — leave blank to skip VPN."
read -rp "Enter Mullvad WireGuard PRIVATE KEY (paste, then press Enter) or press Enter to skip: " MULLVAD_KEY
if [ -n "${MULLVAD_KEY:-}" ]; then
  read -rp "Enter Mullvad WireGuard ADDRESS (example: 10.64.42.2/32): " MULLVAD_ADDR
fi

# -------------------------
# Build docker-compose.yml dynamically
# -------------------------
COMPOSE_FILE="/mnt/media/docker/docker-compose.yml"
echo "==> Writing docker-compose to $COMPOSE_FILE"
sudo mkdir -p /mnt/media/docker
sudo chown 1000:1000 /mnt/media/docker

# Using a temp file then move into place
TMP_COMPOSE="$(mktemp)"
cat > "$TMP_COMPOSE" <<'YML'
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

# append WireGuard env lines conditionally
if [ -n "${MULLVAD_KEY:-}" ]; then
  cat >> "$TMP_COMPOSE" <<YML
      - WIREGUARD_PRIVATE_KEY=${MULLVAD_KEY}
      - WIREGUARD_ADDRESSES=${MULLVAD_ADDR}
YML
fi

cat >> "$TMP_COMPOSE" <<'YML'
      - SERVER_CITIES=Singapore
      - TZ=Asia/Kolkata
    volumes:
      - /mnt/media/docker/gluetun:/gluetun
    ports:
      - 8112:8112
      - 9696:9696
    restart: unless-stopped
YML

# prowlarr block
cat >> "$TMP_COMPOSE" <<'YML'
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
  echo '    network_mode: "container:gluetun"' >> "$TMP_COMPOSE"
fi

cat >> "$TMP_COMPOSE" <<'YML'
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
YML

# deluge block
cat >> "$TMP_COMPOSE" <<'YML'
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
  echo '    network_mode: "container:gluetun"' >> "$TMP_COMPOSE"
fi

cat >> "$TMP_COMPOSE" <<'YML'
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

# move file into place with correct owner/perms
sudo mv "$TMP_COMPOSE" "$COMPOSE_FILE"
sudo chown 1000:1000 "$COMPOSE_FILE"
sudo chmod 644 "$COMPOSE_FILE"
echo "docker-compose written."

# -------------------------
# Start the stack
# -------------------------
cd /mnt/media/docker
echo "==> Starting containers..."
sudo docker compose up -d

echo
echo "==> Completed. Services:"
echo "  Jellyfin  -> http://<your-ip>:8096"
echo "  Radarr    -> http://<your-ip>:7878"
echo "  Sonarr    -> http://<your-ip>:8989"
echo "  Prowlarr  -> http://<your-ip>:9696"
echo "  Deluge    -> http://<your-ip>:8112"
echo
if [ -n "${MULLVAD_KEY:-}" ]; then
  echo "NOTE: VPN keys were provided. Deluge + Prowlarr are routed via Gluetun (Mullvad)."
else
  echo "NOTE: No VPN keys provided. All services run on local network (no VPN)."
fi

echo
echo "Check gluetun logs to confirm VPN IP (if you added keys):"
echo "  sudo docker logs gluetun --tail 80"
echo
echo "Done."
