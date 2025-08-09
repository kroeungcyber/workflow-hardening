# Secure n8n Deployment with Docker and Tailscale

This project provides a secure, self-hosted n8n setup using Docker, Tailscale, and UFW on a DigitalOcean Droplet. It follows a Zero Trust security model, ensuring that your n8n instance is not exposed to the public internet.

For a detailed explanation of how the components work together, please see the [System Architecture Overview](ARCHITECTURE.md).

## Features

- **Zero Trust Access**: Utilizes Tailscale for secure, IP-independent access.
- **Network Isolation**: Docker network configuration prevents public internet access to the n8n container.
- **Firewall Hardening**: `ufw` rules to block all non-essential traffic.
- **Brute-Force Protection**: Built-in rate limiting for the n8n login.
- **OWASP Top 10 Alignment**: The architecture addresses key principles from the OWASP Top 10.

## Prerequisites

1.  A DigitalOcean Droplet (or any Linux server).
2.  Docker and Docker Compose installed on the Droplet.
3.  A Tailscale account (a free account is sufficient).

## Step-by-Step Deployment Guide

> **Note:** The following commands should be executed on your **DigitalOcean Droplet (your server)** via an SSH connection.

### Phase 1: Install and Configure Tailscale

1.  **Install Tailscale on your Server (Droplet):**
    ```bash
    curl -fsSL https://tailscale.com/install.sh | sh
    ```

2.  **Start Tailscale and Authenticate:**
    Follow the on-screen instructions to authenticate your server with your Tailscale account.
    ```bash
    sudo tailscale up
    ```

3.  **Get your Server's Tailscale IP:**
    Take note of the IP address (usually starts with `100.x.y.z`).
    ```bash
    tailscale ip -4
    ```

4.  **Install Tailscale on User Devices:**
    Install the Tailscale client on the computers of the two users who need access. They should log in to the same Tailscale network.

### Phase 2: Configure and Deploy n8n

1.  **Clone this Repository:**
    ```bash
    git clone https://github.com/kroeungcyber/workflow-hardening.git
    cd workflow-hardening
    ```

2.  **Set Environment Variables:**
    Create a `.env` file in the project directory with your server's Tailscale IP address and PostgreSQL credentials.
    ```bash
    cat > .env <<EOL
    # Tailscale IP for n8n
    N8N_HOST=$(tailscale ip -4)
    
    # PostgreSQL credentials
    POSTGRES_DB=n8n_db
    POSTGRES_USER=n8n_user
    POSTGRES_PASSWORD=$(openssl rand -base64 24)
    EOL
    ```
    This generates a strong random password for the database.

3.  **Run Docker Compose:**
    This will start the n8n container with PostgreSQL database, which will only be accessible via the Tailscale network.
    ```bash
    docker-compose up -d
    ```

### Phase 3: Harden the Firewall

1.  **Make the Firewall Script Executable:**
    ```bash
    chmod +x setup_firewall.sh
    ```

2.  **Run the Firewall Script:**
    This will configure `ufw` to block all public traffic, allowing only SSH and Tailscale connections.
    ```bash
    sudo ./setup_firewall.sh
    ```

### Phase 4: Verification

1.  **Check Docker Container:** Ensure the n8n container is running.
    ```bash
    docker ps
    ```
    You should see the `n8n_secure` container in the list.

2.  **Check Firewall Status:** Verify the firewall rules are active.
    ```bash
    sudo ufw status verbose
    ```
    Confirm that the default policy is `deny (incoming)` and that you see `ALLOW IN` rules for SSH and your Tailscale interface.

3.  **Test Public Access (Optional):** From a device *not* on your Tailscale network, try to access `http://<Your_Droplet_Public_IP>:5678`. The connection should time out. This confirms the firewall is blocking public access.

## Data Synchronization Solution

The PostgreSQL database ensures that all workflow data is stored centrally on the server. This resolves the synchronization issue between different computers because:

1. All users access the same centralized database
2. Workflow changes are immediately visible to all connected devices
3. User-specific settings are stored in the database rather than locally
4. Collaboration features work seamlessly across devices

## Accessing Your n8n Instance

Once the setup is complete, you can access your n8n instance by navigating to the following URL in your web browser from a device connected to your Tailscale network:

`http://<YOUR_SERVER_TAILSCALE_IP>:5678`

Replace `<YOUR_SERVER_TAILSCALE_IP>` with the IP address you noted in Phase 1.

### Using Tailscale MagicDNS (Recommended)

For a more user-friendly experience, you can use Tailscale's MagicDNS feature. This gives your server a memorable machine name that you can use instead of the IP address.

1.  Enable MagicDNS in your [Tailscale Admin Console](https://login.tailscale.com/admin/dns).
2.  Find your server's machine name in the "Machines" tab of the admin console.
3.  You can now access n8n at `http://<machine-name>:5678`.

## Managing the n8n Service

-   **To stop the service:**
    ```bash
    docker-compose down
    ```
-   **To start the service again:**
    ```bash
    docker-compose up -d
    ```
-   **To update n8n to the latest version:**
    ```bash
    docker-compose pull
    docker-compose up -d
    ```

## Advanced Threat Mitigation

-   **DDoS Attacks**: By removing public exposure, the primary attack surface for DDoS is eliminated. Tailscale's underlying WireGuard protocol also provides protection against certain types of network attacks.
-   **Brute-Force Attacks**: The `docker-compose.yml` file enables n8n's built-in rate limiting for authentication attempts. For even greater security, enable Two-Factor Authentication (2FA) within the n8n user settings.
