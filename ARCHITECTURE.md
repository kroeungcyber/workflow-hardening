# System Architecture Overview

This document explains how the secure n8n setup works by breaking it down into its core components. The entire system is designed around a **Zero Trust** principle, meaning nothing is trusted by default, and all access is explicitly verified.

Here is a simplified diagram of the data flow:

```
+----------------+      +-------------------------+      +-----------------------------+
|                |      |                         |      |      DigitalOcean Droplet   |
|   User Device  |----->|   Tailscale Network     |----->|      (Your Server)          |
| (Your Computer)|      |   (Secure VPN Tunnel)   |      |                             |
|                |      |                         |      | +-------------------------+ |
+----------------+      +-------------------------+      | | UFW Firewall            | |
                                                         | | (Blocks Public Internet)| |
                                                         | +-----------+-------------+ |
                                                         |             |               |
                                                         |             v               |
                                                         | +-------------------------+ |
                                                         | | Docker                  | |
                                                         | | +---------------------+ | |
                                                         | | | n8n Container       | | |
                                                         | | +---------------------+ | |
                                                         | +-------------------------+ |
                                                         +-----------------------------+
```

## How It Works, Step-by-Step

1.  **The User's Device:**
    -   Your computer has the Tailscale client installed and running.
    -   When you want to access n8n, Tailscale creates a secure, encrypted connection (a WireGuard® tunnel) from your device into the Tailscale network.

2.  **The Tailscale Network (The Secure Overlay):**
    -   Think of Tailscale as a private, invisible layer on top of the public internet. Only devices you've authorized can join this network.
    -   Your server (the DigitalOcean Droplet) is also on this network.
    -   Tailscale gives each device a unique `100.x.y.z` IP address. These IPs are private and only work within your Tailscale network.
    -   This is how you solve the "dynamic IP" problem. It doesn't matter what your public IP address is; as long as you are logged into Tailscale, you have a consistent, secure identity on the private network.

3.  **The DigitalOcean Droplet (The Server):**
    -   **Layer 1: The Firewall (`ufw`)**: The very first thing any traffic hits is the server's firewall. We have configured it to `DENY` all incoming connections from the public internet. The *only* exception is for traffic coming from the secure Tailscale network (`tailscale0` interface). This is the most critical step; it makes your n8n instance invisible to the public.
    -   **Layer 2: Docker and n8n**:
        -   Inside the server, Docker runs your n8n container.
        -   In the `docker-compose.yml` file, we configured the n8n service to bind *only* to the server's Tailscale IP address (`${N8N_HOST}:5678:5678`).
        -   This means that even if the firewall were to fail, the n8n application itself would not accept connections from the server's public IP address. It's a second layer of defense.

## Summary of Security Benefits

-   **No Public Exposure**: Your n8n instance has no open ports on the public internet, which drastically reduces the attack surface. It's effectively cloaked.
-   **Encrypted Traffic**: All communication between your device and the server is end-to-end encrypted by Tailscale.
-   **Strong Authentication**: Access is controlled by your Tailscale account's identity provider (like Google, Microsoft, or GitHub), which supports Multi-Factor Authentication (MFA).
-   **DDoS and Brute-Force Mitigation**: Since attackers can't see or connect to your n8n login page from the public internet, they cannot launch DDoS or brute-force attacks against it. The rate-limiting configured in n8n is an extra precaution for authorized users.
