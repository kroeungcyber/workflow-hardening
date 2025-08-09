#!/bin/bash

# This script configures UFW (Uncomplicated Firewall) to secure the n8n instance.
# It allows SSH and Tailscale traffic while denying all other incoming connections.

# Ensure the script is run with root privileges
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit
fi

echo "Configuring firewall rules..."

# 1. Reset UFW to a default state
ufw --force reset

# 2. Set default policies: deny all incoming, allow all outgoing
ufw default deny incoming
ufw default allow outgoing

# 3. Allow SSH connections (on the default port 22)
# For enhanced security, you can restrict this to your Tailscale network.
# Example: ufw allow from 100.x.y.z/32 to any port 22 proto tcp
ufw allow ssh

# 4. Allow all traffic on the Tailscale interface (tailscale0)
ufw allow in on tailscale0
ufw allow out on tailscale0

# 5. Enable the firewall
ufw enable

echo "Firewall configuration complete."
ufw status verbose
