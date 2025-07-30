# Hardening a Self-Hosted n8n Instance: A Complete Guide

This guide provides a comprehensive, step-by-step process for securing a self-hosted n8n instance on a DigitalOcean droplet using a multi-layered, defense-in-depth approach.

---

## Table of Contents
1.  [Part 1: Enable JWT Authentication for n8n](#part-1-enable-jwt-authentication-for-n8n)
2.  [Part 2: Set up Cloudflare Dynamic DNS (DDNS)](#part-2-set-up-cloudflare-dynamic-dns-ddns)
3.  [Part 3: Restrict Access with UFW Firewall](#part-3-restrict-access-with-ufw-firewall)
4.  [Part 4: Set up Nginx as a Reverse Proxy](#part-4-set-up-nginx-as-a-reverse-proxy)
5.  [Part 5: Cloudflare WAF, Bot Management, and Zero Trust](#part-5-cloudflare-waf-bot-management-and-zero-trust)

---

## Part 1: Enable JWT Authentication for n8n

**Justification:** Enabling JWT authentication is a critical security measure that replaces the default static API key with a more secure, token-based system. This prevents unauthorized access to your n8n REST API.

**Best Practice:** Use strong, randomly generated secrets for your JWTs and manage them securely using a secrets management tool or `.env` files excluded from version control.

### Step-by-Step Instructions

1.  **Generate Strong Secrets:**
    Generate unique, random strings for your encryption key and JWT secrets.
    ```bash
    openssl rand -base64 32
    ```

2.  **Set Environment Variables:**
    Add the following variables to your n8n environment configuration (e.g., `docker-compose.yml`).

    ```yaml
    # Example for a docker-compose.yml file
    services:
      n8n:
        image: n8nio/n8n
        # ... other configurations
        environment:
          # ... other variables
          - N8N_ENCRYPTION_KEY=your_strong_random_encryption_key
          - N8N_SECURE_COOKIE=true
          - N8N_USER_MANAGEMENT_DISABLED=false
          - N8N_USER_MANAGEMENT_JWT_AUTH_ACTIVE=true
          - N8N_USER_MANAGEMENT_JWT_AUTH_SECRET=your_super_strong_jwt_secret
          - N8N_USER_MANAGEMENT_JWT_AUTH_ISSUER=n8n.kroeungcyber.com
          - N8N_USER_MANAGEMENT_JWT_AUTH_ALGORITHM=HS256
          - N8N_USER_MANAGEMENT_JWT_AUTH_EXPIRATION=15m
          - N8N_USER_MANAGEMENT_JWT_AUTH_REFRESH_ENABLED=true
          - N8N_USER_MANAGEMENT_JWT_AUTH_REFRESH_EXPIRATION=7d
          - N8N_USER_MANAGEMENT_JWT_AUTH_REFRESH_SECRET=your_super_strong_jwt_refresh_secret
    ```
3.  **Restart n8n** for the changes to take effect.

---

## Part 2: Set up Cloudflare Dynamic DNS (DDNS)

**Justification:** DDNS ensures your domain `n8n.kroeungcyber.com` always points to your droplet's IP address, which is essential for consistent access and for the firewall rules that follow.

**Best Practice:** Use a scoped Cloudflare API token with permissions limited to editing DNS records for the specific zone.

### Step-by-Step Instructions

1.  **Create a Cloudflare API Token:**
    *   In Cloudflare, go to **My Profile** > **API Tokens** > **Create Token**.
    *   Use the **Edit zone DNS** template and scope it to your `kroeungcyber.com` zone.
    *   Copy the generated token.

2.  **Create the DDNS Update Script (`update-cloudflare-dns.sh`):**
    ```bash
    #!/bin/bash
    CF_API_TOKEN="YOUR_CLOUDFLARE_API_TOKEN"
    CF_ZONE_ID="YOUR_ZONE_ID"
    CF_RECORD_NAME="n8n.kroeungcyber.com"
    
    CURRENT_IP=$(curl -s http://ipv4.icanhazip.com)
    RECORD_INFO=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?type=A&name=${CF_RECORD_NAME}" -H "Authorization: Bearer ${CF_API_TOKEN}" -H "Content-Type: application/json")
    CF_RECORD_ID=$(echo $RECORD_INFO | jq -r '.result[0].id')
    CF_RECORD_IP=$(echo $RECORD_INFO | jq -r '.result[0].content')
    
    if [ "$CURRENT_IP" == "$CF_RECORD_IP" ]; then exit 0; fi
    
    curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${CF_RECORD_ID}" -H "Authorization: Bearer ${CF_API_TOKEN}" -H "Content-Type: application/json" --data "{\"type\":\"A\",\"name\":\"${CF_RECORD_NAME}\",\"content\":\"${CURRENT_IP}\",\"ttl\":120,\"proxied\":true}"
    ```

3.  **Install `jq` and Make Script Executable:**
    ```bash
    sudo apt-get update && sudo apt-get install -y jq
    chmod +x update-cloudflare-dns.sh
    ```

4.  **Automate with a Cron Job:**
    Run `crontab -e` and add this line to run the script every 5 minutes:
    ```
    */5 * * * * /path/to/update-cloudflare-dns.sh > /dev/null 2>&1
    ```

---

## Part 3: Restrict Access with UFW Firewall

**Justification:** This step prevents attackers from bypassing Cloudflare and targeting your server's IP directly by ensuring only Cloudflare can access your web ports.

**Best Practice:** Automate the firewall update script to run daily to sync with any changes to Cloudflare's IP ranges.

### Step-by-Step Instructions

1.  **Create the Firewall Update Script (`update-ufw-for-cloudflare.sh`):**
    ```bash
    #!/bin/bash
    sudo ufw allow 22/tcp # Ensure SSH is allowed
    
    CF_IPV4=$(curl -s https://www.cloudflare.com/ips-v4)
    CF_IPV6=$(curl -s https://www.cloudflare.com/ips-v6)
    
    sudo ufw delete allow 80/tcp
    sudo ufw delete allow 443/tcp
    
    for ip in $CF_IPV4; do sudo ufw allow from $ip to any port 80,443 proto tcp; done
    for ip in $CF_IPV6; do sudo ufw allow from $ip to any port 80,443 proto tcp; done
    
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    yes | sudo ufw enable
    sudo ufw status verbose
    ```

2.  **Make Script Executable and Run:**
    ```bash
    chmod +x update-ufw-for-cloudflare.sh
    sudo ./update-ufw-for-cloudflare.sh
    ```

3.  **Automate with a Cron Job:**
    Run `sudo crontab -e` and add this line to run daily at midnight:
    ```
    0 0 * * * /path/to/update-ufw-for-cloudflare.sh > /var/log/ufw-update.log 2>&1
    ```

---

## Part 4: Set up Nginx as a Reverse Proxy

**Justification:** Nginx acts as a secure gateway, handling SSL/TLS, rate limiting traffic, adding security headers, and hiding your n8n instance's internal port.

**Best Practice:** Use a free Cloudflare Origin Certificate for end-to-end encryption between Cloudflare and your server. Set Cloudflare's SSL/TLS mode to **Full (Strict)**.

### Step-by-Step Instructions

1.  **Install Nginx:**
    ```bash
    sudo apt-get update && sudo apt-get install -y nginx
    ```

2.  **Obtain and Install Cloudflare Origin Certificate:**
    *   In Cloudflare (**SSL/TLS** > **Origin Server**), create a certificate.
    *   Save the certificate as `/etc/nginx/ssl/n8n.kroeungcyber.com.pem` and the private key as `/etc/nginx/ssl/n8n.kroeungcyber.com.key` on your server.
    *   Secure the private key: `sudo chmod 600 /etc/nginx/ssl/n8n.kroeungcyber.com.key`.

3.  **Create Nginx Configuration (`/etc/nginx/sites-available/n8n.kroeungcyber.com`):**
    ```nginx
    limit_req_zone $binary_remote_addr zone=n8n_limit:10m rate=10r/s;
    
    server {
        listen 80;
        server_name n8n.kroeungcyber.com;
        return 301 https://$host$request_uri;
    }
    
    server {
        listen 443 ssl http2;
        server_name n8n.kroeungcyber.com;
    
        ssl_certificate /etc/nginx/ssl/n8n.kroeungcyber.com.pem;
        ssl_certificate_key /etc/nginx/ssl/n8n.kroeungcyber.com.key;
        ssl_protocols TLSv1.2 TLSv1.3;
    
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
    
        location / {
            limit_req zone=n8n_limit burst=20 nodelay;
            proxy_pass http://localhost:5678;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
        }
    }
    ```

4.  **Enable Site and Restart Nginx:**
    ```bash
    sudo ln -s /etc/nginx/sites-available/n8n.kroeungcyber.com /etc/nginx/sites-enabled/
    sudo rm /etc/nginx/sites-enabled/default
    sudo nginx -t
    sudo systemctl restart nginx
    ```

---

## Part 5: Cloudflare WAF, Bot Management, and Zero Trust

**Justification:** This final layer leverages Cloudflare's global network to block threats before they reach your server and adds a robust, identity-aware authentication layer.

### A. WAF and Bot Management

1.  **Enable WAF:**
    *   In Cloudflare, go to **Security** > **WAF**.
    *   Enable the **Cloudflare Managed Ruleset**. Start in **Simulate** mode, then switch to **Block**.
2.  **Enable Bot Protection:**
    *   Go to **Security** > **Bots**.
    *   Enable **Bot Fight Mode**.

### B. Cloudflare Zero Trust Access Policy

1.  **Set up Zero Trust:**
    *   Navigate to the **Zero Trust** dashboard from the main Cloudflare menu.
2.  **Add a Self-hosted Application:**
    *   Go to **Access** > **Applications** > **Add an application** and select **Self-hosted**.
    *   **Application name:** `n8n Instance`
    *   **Application domain:** `n8n.kroeungcyber.com`
3.  **Create an Access Policy:**
    *   **Policy name:** `Allow My Domain`
    *   **Action:** `Allow`
    *   **Rule:** Create an "Include" rule for `Emails ending in` with the value `mydomain.com` (replace with your domain).
4.  **Save the Application.**

Now, users must authenticate via Cloudflare Access before reaching your n8n instance, providing an exceptionally strong front-line defense.
