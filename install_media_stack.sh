#!/usr/bin/env bash
set -euo pipefail

# install_media_stack.sh
# Builds local Netflix-style media stack with optional VPN (Mullvad + Gluetun)
# Now includes static IP configuration before install.

echo "==> Updating system..."
sudo apt update && sudo apt install -y ca-certificates curl gnupg lsb-release apt-transport-https net-tools

# 🧠 Detect current network interface
echo "==> Detecting network info..."
IFACE=$(ip -o -4 route show to default | awk '{print $5}')
CURRENT_IP=$(hostname -I | awk '{print $1}')
GATEWAY=$(ip route | grep default | awk '{print $3}')
CIDR=$(ip -o -f inet addr show $IFACE | awk '{print $4}')
SUBNET_MASK=$(ipcalc "$CIDR" | grep "Netmask:" | awk '{print $2}')

echo "Detected interface: $IFACE"
echo "Current IP: $CURRENT_IP"
echo "Gateway: $GATEWAY"
echo "Netmask: $SUBNET_MASK"
echo

read -p "Do you want to make your IP static? (y/N): " MAKE_STATIC
if [[ "$MAKE_STATIC" =~ ^[Yy]$ ]]; then
  read -p "Enter desired static IP [default: $CURRENT_IP]: " STATIC_IP
  STATIC_IP=${STATIC_IP:-$CURRENT_IP}
  echo "==> Setting static IP to $STATIC_IP ..."
  
  # Create Netplan config
  sudo tee /etc/netplan/99-static.yaml > /dev/null <<YAML
network:
  version: 2
  renderer: networkd
  ethernets:
    $IFACE:
      dhcp4: no
      addresses: [$STATIC_IP/24]
      gateway4: $GATEWAY
      nameservers:
        addresses: [1.1.1.1, 8.8.8.8]
YAML

  echo "==> Applying static IP..."
  sudo netplan apply
  echo "Static IP applied: $STATIC_IP"
  echo
else
  echo "Skipping static IP setup — continuing with DHCP."
fi

# Docker installation
echo "==> Installing Docker..."
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable --now docker

# Create folder structure
sudo mkdir -p /mnt/media/{Movies,TV,Downloads,docker}
sudo chown -R 1000:1000 /mnt/media
sudo chmod -R 775 /mnt/media

# VPN setup
echo "==> Checking for VPN credentials..."
read -p "Enter Mullvad WireGuard PRIVATE KEY (or press Enter to skip): " VPN_KEY
read -p "Enter Mullvad WireGuard ADDRESS (example: 10.64.42.x/32) or press Enter to skip: " VPN_ADDR

sudo tee /mnt/media/docker/docker-compose.yml > /dev/null <<YML
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
      - SERVER_CITIES=Singapore
      - TZ=Asia/Kolkata
$(if [ -n "$VPN_KEY" ]; then
cat <<VPN
      - WIREGUARD_PRIVATE_KEY=$VPN_KEY
      - WIREGUARD_ADDRESSES=$VPN_ADDR
VPN
fi)
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
    $(if [ -n "$VPN_KEY" ]; then echo 'network_mode: "container:gluetun"'; fi)
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
    $(if [ -n "$VPN_KEY" ]; then echo 'network_mode: "container:gluetun"'; fi)
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

echo "==> Bringing up containers..."
cd /mnt/media/docker
sudo docker compose up -d

echo "==> Setup complete!"
echo
echo "Access your services using:"
echo "  Jellyfin  -> http://$CURRENT_IP:8096"
echo "  Radarr    -> http://$CURRENT_IP:7878"
echo "  Sonarr    -> http://$CURRENT_IP:8989"
echo "  Prowlarr  -> http://$CURRENT_IP:9696"
echo "  Deluge    -> http://$CURRENT_IP:8112"
