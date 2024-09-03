#!/bin/bash

# Enhanced WireGuardMin installation script

# Uninstall any previous WireGuard installation
echo "Uninstalling any previous WireGuard installation..."
sudo apt remove --purge wireguard wireguard-tools qrencode -y
sudo apt autoremove -y
sudo apt autoclean

# Update and install necessary packages
echo "Updating package list and installing necessary packages..."
sudo apt update && sudo apt upgrade -y
sudo apt install wireguard wireguard-tools qrencode resolvconf curl -y

# Check if DuckDNS setup is required
DUCKDNS_DOMAIN=""
DUCKDNS_TOKEN=""
if [ ! -f /home/pi/duckdns/duck.log ]; then
    echo "Setting up DuckDNS for Dynamic DNS..."

    # Create DuckDNS directory for scripts
    mkdir -p /home/pi/duckdns

    # Prompt user for DuckDNS information
    echo "Please enter your desired DuckDNS domain (subdomain of duckdns.org):"
    read DUCKDNS_DOMAIN
    echo "Visit https://www.duckdns.org/ to create an account and obtain your token."
    echo "Enter your DuckDNS token:"
    read DUCKDNS_TOKEN

    # Create the DuckDNS update script
    echo "Creating DuckDNS update script..."
    echo "echo url=\"https://www.duckdns.org/update?domains=$DUCKDNS_DOMAIN&token=$DUCKDNS_TOKEN&ip=\" | curl -k -o /home/pi/duckdns/duck.log -K -" > /home/pi/duckdns/duck.sh
    chmod +x /home/pi/duckdns/duck.sh

    # Set up a cron job to update DuckDNS every 5 minutes
    echo "Setting up DuckDNS cron job..."
    (crontab -l 2>/dev/null; echo "*/5 * * * * /home/pi/duckdns/duck.sh >/dev/null 2>&1") | crontab -
else
    echo "DuckDNS is already set up. Using existing settings."
    DUCKDNS_DOMAIN=$(grep -oP '(?<=domains=)[^&]*' /home/pi/duckdns/duck.sh)
    DUCKDNS_TOKEN=$(grep -oP '(?<=token=)[^&]*' /home/pi/duckdns/duck.sh)
fi

# Generate WireGuard keys
echo "Generating WireGuard keys..."
SERVER_PRIV_KEY=$(wg genkey)
SERVER_PUB_KEY=$(echo $SERVER_PRIV_KEY | wg pubkey)
CLIENT_PRIV_KEY=$(wg genkey)
CLIENT_PUB_KEY=$(echo $CLIENT_PRIV_KEY | wg pubkey)

# Create WireGuard configuration directory
WG_CONFIG_DIR="/etc/wireguard"
WG_CONFIG_FILE="$WG_CONFIG_DIR/wg0.conf"
sudo mkdir -p $WG_CONFIG_DIR

# Create the server configuration file
echo "Creating server configuration file..."
sudo bash -c "cat > $WG_CONFIG_FILE" <<EOL
[Interface]
PrivateKey = $SERVER_PRIV_KEY
Address = 10.0.0.1/24
ListenPort = 51820
SaveConfig = true

PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
PublicKey = $CLIENT_PUB_KEY
AllowedIPs = 10.0.0.2/32
EOL

# Set permissions for the configuration file
sudo chmod 600 $WG_CONFIG_FILE

# Enable and start WireGuard
echo "Enabling and starting WireGuard..."
sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0

# Create the client configuration file
CLIENT_CONFIG_FILE="$WG_CONFIG_DIR/client.conf"
echo "Creating client configuration file..."
sudo bash -c "cat > $CLIENT_CONFIG_FILE" <<EOL
[Interface]
PrivateKey = $CLIENT_PRIV_KEY
Address = 10.0.0.2/24
DNS = 8.8.8.8

[Peer]
PublicKey = $SERVER_PUB_KEY
Endpoint = $DUCKDNS_DOMAIN.duckdns.org:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 21
EOL

# Generate QR code for the client configuration and save as PNG
echo "Generating QR code..."
sudo qrencode -o /home/pi/wg_client_qr.png -t png < $CLIENT_CONFIG_FILE

echo "WireGuard installation and setup complete!"
echo "QR code saved to /home/pi/wg_client_qr.png"

# Final message
echo "DuckDNS is set up to update your IP address. Ensure your DuckDNS domain and token are correct in /home/pi/duckdns/duck.sh."
echo "Use an image viewer to open the QR code PNG file: /home/pi/wg_client_qr.png"
