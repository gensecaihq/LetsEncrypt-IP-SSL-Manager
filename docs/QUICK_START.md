# Quick Start Guide

Get up and running with the LetsEncrypt IP SSL Manager in 5 minutes.

## 🎯 Prerequisites Check

Before starting, ensure you have:
- [ ] A server with a public IP address (IPv4 or IPv6)
- [ ] Root/sudo access to the server
- [ ] Port 80 accessible from the internet
- [ ] A valid email address for notifications

**Quick Test:**
```bash
# Check your public IP
curl -4 icanhazip.com  # IPv4
curl -6 icanhazip.com  # IPv6

# Test port 80 accessibility (from another machine)
telnet YOUR_PUBLIC_IP 80
```

## 🚀 Step 1: Download and Setup

```bash
# Clone the repository
git clone https://github.com/yourusername/letsencrypt-ip-manager.git
cd letsencrypt-ip-manager

# Make the script executable
chmod +x letsencrypt-ip-ssl-manager.sh

# Verify the script works
./letsencrypt-ip-ssl-manager.sh --version
```

**Expected Output:**
```
Let's Encrypt IP Certificate Manager
Version 3.0.0
```

## ⚡ Step 2: One-Command Setup (Recommended)

Run the interactive setup wizard:

```bash
sudo ./letsencrypt-ip-ssl-manager.sh --setup
```

This will:
1. ✅ Detect your operating system
2. ✅ Install required dependencies (certbot, curl, openssl, etc.)
3. ✅ Configure your email and preferences
4. ✅ Set up automatic renewal
5. ✅ Optionally generate your first certificate

**Follow the prompts:**
- Enter your email address for notifications
- Confirm your public IP address
- Choose webroot path (default: `/var/www/html`)
- Enable automatic renewal (recommended)

## 🔐 Step 3: Get Your First Certificate

If you didn't generate a certificate during setup:

```bash
# Replace with your actual IP and email
sudo ./letsencrypt-ip-ssl-manager.sh -i 203.0.113.10 -e admin@example.com
```

**Success Output:**
```
✅ Certificate obtained successfully for 203.0.113.10
📁 Certificate files saved to: /etc/letsencrypt/live/203.0.113.10/
🔄 Auto-renewal configured (every 4 hours)
```

## 🌐 Step 4: Configure Your Web Server

### For NGINX:

```bash
# Backup existing configuration
sudo cp /etc/nginx/sites-available/default /etc/nginx/sites-available/default.backup

# Create SSL configuration
sudo tee /etc/nginx/sites-available/default > /dev/null << 'EOF'
server {
    listen 80;
    server_name YOUR_IP;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name YOUR_IP;
    
    ssl_certificate /etc/letsencrypt/live/YOUR_IP/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/YOUR_IP/privkey.pem;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
    
    root /var/www/html;
    index index.html;
    
    location / {
        try_files $uri $uri/ =404;
    }
    
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
}
EOF

# Replace YOUR_IP with your actual IP
sudo sed -i 's/YOUR_IP/203.0.113.10/g' /etc/nginx/sites-available/default

# Test and reload NGINX
sudo nginx -t
sudo systemctl reload nginx
```

### For Apache:

```bash
# Enable SSL module
sudo a2enmod ssl

# Create SSL configuration
sudo tee /etc/apache2/sites-available/000-default-ssl.conf > /dev/null << 'EOF'
<VirtualHost YOUR_IP:443>
    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/YOUR_IP/cert.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/YOUR_IP/privkey.pem
    SSLCertificateChainFile /etc/letsencrypt/live/YOUR_IP/chain.pem
    
    DocumentRoot /var/www/html
    
    <Directory /var/www/html>
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>

<VirtualHost YOUR_IP:80>
    Redirect permanent / https://YOUR_IP/
</VirtualHost>
EOF

# Replace YOUR_IP with your actual IP
sudo sed -i 's/YOUR_IP/203.0.113.10/g' /etc/apache2/sites-available/000-default-ssl.conf

# Enable site and reload Apache
sudo a2ensite 000-default-ssl
sudo systemctl reload apache2
```

## ✅ Step 5: Verify Everything Works

### Test HTTPS Connection:
```bash
# Test HTTPS
curl -I https://YOUR_IP

# Expected: HTTP/2 200 with SSL information
```

### Check Certificate Details:
```bash
# View certificate information
sudo ./letsencrypt-ip-ssl-manager.sh --list
```

### Verify Auto-Renewal:
```bash
# Check renewal status
sudo ./letsencrypt-ip-ssl-manager.sh --status | grep -A5 "Auto-Renewal"

# Test renewal process
sudo ./letsencrypt-ip-ssl-manager.sh --renew
```

## 🔧 Step 6: Create a Test Page (Optional)

```bash
# Create a simple test page
sudo tee /var/www/html/index.html > /dev/null << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>SSL Certificate Test</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; margin-top: 100px; }
        .success { color: green; font-size: 24px; }
        .info { color: blue; margin-top: 20px; }
    </style>
</head>
<body>
    <div class="success">🔒 SSL Certificate Working!</div>
    <div class="info">
        <p>Your IP address SSL certificate is properly configured.</p>
        <p>Server IP: <strong>YOUR_IP</strong></p>
        <p>Certificate issued by Let's Encrypt</p>
    </div>
</body>
</html>
EOF

# Replace YOUR_IP in the HTML
sudo sed -i 's/YOUR_IP/203.0.113.10/g' /var/www/html/index.html
```

Now visit `https://YOUR_IP` in your browser to see the test page.

## 📊 Step 7: Monitor and Maintain

### Check System Status:
```bash
# Comprehensive status report
./letsencrypt-ip-ssl-manager.sh --status
```

### Monitor Logs:
```bash
# View recent activity
sudo tail -f /var/log/letsencrypt-ip-manager/ip-certificate.log

# Check for errors
sudo tail -20 /var/log/letsencrypt-ip-manager/error.log
```

### Set Up Monitoring (Optional):
```bash
# Add to crontab for daily status checks
echo "0 9 * * * /path/to/letsencrypt-ip-ssl-manager.sh --status | grep -i error && echo 'SSL Manager Issues Detected' | mail -s 'SSL Alert' admin@example.com" | sudo crontab -
```

## 🚨 Common Quick Fixes

### If Port 80 Test Fails:
```bash
# Check firewall
sudo ufw allow 80/tcp
sudo ufw reload

# Check if web server is running
sudo systemctl status nginx    # or apache2
sudo systemctl start nginx     # if stopped
```

### If Certificate Generation Fails:
```bash
# Run with debug mode
sudo ./letsencrypt-ip-ssl-manager.sh --debug -i YOUR_IP -e YOUR_EMAIL

# Check system integrity
./letsencrypt-ip-ssl-manager.sh --integrity-check
```

### If Auto-Renewal Isn't Working:
```bash
# Re-setup renewal
sudo ./letsencrypt-ip-ssl-manager.sh --setup-renewal

# Check timer status
sudo systemctl status certbot-ip-renew.timer
```

## 🎯 Next Steps

Congratulations! You now have a working SSL certificate for your IP address. Here's what to do next:

1. **📚 Learn More**: Read the [User Manual](USER_MANUAL.md) for advanced features
2. **🛡️ Secure Your Setup**: Follow the [Security Guide](SECURITY.md) for best practices
3. **🚀 Scale Up**: Check [Deployment Examples](DEPLOYMENT.md) for complex setups
4. **🔧 Customize**: Use `--configure` to adjust settings
5. **📊 Monitor**: Set up proper monitoring and alerting

### Useful Commands to Remember:

```bash
# Check certificate status
sudo ./letsencrypt-ip-ssl-manager.sh --list

# Force renewal (if needed)
sudo ./letsencrypt-ip-ssl-manager.sh --force-renew

# View configuration
./letsencrypt-ip-ssl-manager.sh --show-config

# Get help
./letsencrypt-ip-ssl-manager.sh --help

# Emergency recovery
sudo ./letsencrypt-ip-ssl-manager.sh --emergency
```

## 📞 Need Help?

If you encounter issues:

1. **Check the [FAQ](FAQ.md)** for common questions
2. **Review [Troubleshooting Guide](TROUBLESHOOTING.md)** for detailed solutions
3. **Run diagnostic**: `./letsencrypt-ip-ssl-manager.sh --status`
4. **Enable debug mode**: `sudo ./letsencrypt-ip-ssl-manager.sh --debug [command]`
5. **Open an issue** on GitHub with detailed information

---

**🎉 You're now ready to use HTTPS with your IP address!** Your certificate will automatically renew every 4 hours, ensuring continuous SSL protection.