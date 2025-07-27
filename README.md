# Let's Encrypt IP Certificate Manager

<div align="center">

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Version](https://img.shields.io/badge/version-3.0.0-green.svg)
![Bash](https://img.shields.io/badge/bash-3.2%2B-orange.svg)
![Certbot](https://img.shields.io/badge/certbot-2.0.0%2B-red.svg)
![Production Ready](https://img.shields.io/badge/production-ready-brightgreen.svg)
![Cross Platform](https://img.shields.io/badge/cross--platform-linux%20|%20bsd%20|%20macos-blue.svg)

**Enterprise-grade Swiss Army Knife for managing Let's Encrypt SSL certificates for IP addresses**

[Features](#features) • [Quick Start](#quick-start) • [Documentation](#documentation) • [Installation](#installation) • [Usage](#usage) • [FAQ](#faq) • [Contributing](#contributing)

</div>

---

## 🎉 Announcement

As of July 2025, [Let's Encrypt now supports SSL certificates for IP addresses](https://letsencrypt.org/2025/07/01/issuing-our-first-ip-address-certificate/)! This is a significant milestone that enables HTTPS for services accessed directly via IP address.

This tool simplifies the process of obtaining and managing these IP certificates with automatic renewal, comprehensive validation, and production-ready features.

## 🙏 Acknowledgments

This project is made possible by [Let's Encrypt](https://letsencrypt.org/), a free, automated, and open Certificate Authority. We extend our gratitude to:

- **[Let's Encrypt](https://letsencrypt.org/)** - For providing free SSL certificates and pioneering IP address certificate support
- **[Internet Security Research Group (ISRG)](https://www.abetterinternet.org/)** - For operating Let's Encrypt
- **[Electronic Frontier Foundation (EFF)](https://www.eff.org/)** - For their contributions to Certbot and web security

## ⚠️ Important Notes

- **Staging Environment Only**: IP certificates are currently available only in Let's Encrypt's staging environment
- **Short-lived Certificates**: IP certificates are valid for only 6 days (requires aggressive renewal)
- **ACME Profile Support**: Requires Certbot 2.0.0+ with [ACME profile support](https://letsencrypt.org/2025/01/09/acme-profiles/)
- **Public IPs Only**: Private or local IP addresses are not supported

## 🚀 Quick Start

```bash
# Clone and setup
git clone https://github.com/yourusername/letsencrypt-ip-manager.git
cd letsencrypt-ip-manager
chmod +x letsencrypt-ip-ssl-manager.sh

# Interactive setup (recommended for new users)
sudo ./letsencrypt-ip-ssl-manager.sh --setup

# Or quick certificate generation
sudo ./letsencrypt-ip-ssl-manager.sh -i YOUR_PUBLIC_IP -e your@email.com
```

## 📚 Documentation

- **[📖 User Manual](docs/USER_MANUAL.md)** - Complete usage guide
- **[🔧 Installation Guide](docs/INSTALLATION.md)** - Step-by-step setup
- **[🛠️ API Reference](docs/API_REFERENCE.md)** - All commands and options
- **[🔍 Troubleshooting](docs/TROUBLESHOOTING.md)** - Common issues and solutions
- **[🛡️ Security Guide](docs/SECURITY.md)** - Security best practices
- **[🚀 Deployment Examples](docs/DEPLOYMENT.md)** - Production deployment scenarios

## ✨ Features

### 🌟 Core Capabilities
- 🌐 **Universal IP Support**: IPv4 and IPv6 addresses with comprehensive validation
- 🔒 **Smart Validation**: Ensures public IP addresses only, rejects private/reserved ranges
- ⚡ **Aggressive Renewal**: Every 4 hours for 6-day certificates with multiple fallback mechanisms
- 🎯 **Interactive Setup**: User-friendly configuration wizard with persistent settings

### 🛡️ Enterprise Security
- 🔐 **Input Sanitization**: Comprehensive validation preventing injection attacks
- 🔒 **Secure Permissions**: Proper file permissions and access controls
- 📋 **Audit Logging**: Complete audit trail for compliance and monitoring
- 🚨 **Emergency Recovery**: Automatic backup and restore capabilities

### 🌍 Cross-Platform Excellence  
- 🐧 **Linux Distributions**: Debian, Ubuntu, RHEL, CentOS, Fedora, SUSE, Arch, Alpine, Gentoo
- 🔺 **BSD Systems**: FreeBSD, OpenBSD, NetBSD, DragonFlyBSD  
- 🍎 **macOS Support**: Limited support with Homebrew
- ⚙️ **Multi-Init Systems**: SystemD, OpenRC, SysV, BSD RC, launchd

### 🔧 Swiss Army Knife Tools
- 📊 **System Monitoring**: Comprehensive status reports and health checks
- 🗃️ **Backup Management**: Automated backup rotation with configurable retention
- 🔄 **Auto-Recovery**: Intelligent error recovery with rollback capabilities
- 🎨 **User Experience**: Colored output, progress indicators, helpful messages
- 📈 **Dependency Management**: Automatic dependency detection and installation
- 🔍 **Integrity Checking**: System integrity verification and validation

## 📋 Requirements

### System Requirements
- **Operating System**: Linux (Debian/Ubuntu/RHEL/CentOS/Fedora/SUSE/Arch/Alpine/Gentoo), BSD (FreeBSD/OpenBSD/NetBSD), or macOS
- **Privileges**: Root or sudo access for certificate operations
- **Network**: Public IP address (IPv4 or IPv6) accessible from the internet
- **Firewall**: Port 80 accessible for HTTP-01 challenge validation

### Software Requirements
- **Shell**: Bash 3.2+ (compatible with older systems)
- **Certbot**: 2.0.0+ with ACME profile support (auto-installed if missing)
- **Python**: 3.6+ (usually pre-installed)
- **Utilities**: curl, openssl, DNS tools (auto-detected and installed)

## 🚀 Installation

### 🎯 Automated Installation (Recommended)

```bash
# Clone the repository
git clone https://github.com/yourusername/letsencrypt-ip-manager.git
cd letsencrypt-ip-manager

# Make the script executable
chmod +x letsencrypt-ip-ssl-manager.sh

# Interactive setup (handles everything automatically)
sudo ./letsencrypt-ip-ssl-manager.sh --setup
```

### ⚡ Quick Installation

```bash
# Clone and install dependencies
git clone https://github.com/yourusername/letsencrypt-ip-manager.git
cd letsencrypt-ip-manager
chmod +x letsencrypt-ip-ssl-manager.sh

# Install certbot and dependencies automatically
sudo ./letsencrypt-ip-ssl-manager.sh --install

# Configure settings interactively
sudo ./letsencrypt-ip-ssl-manager.sh --configure
```

### Manual Installation

1. **Install Dependencies** (if not using the script's auto-installer):

   **Debian/Ubuntu:**
   ```bash
   sudo apt update
   sudo apt install -y snapd python3 curl openssl dnsutils
   sudo snap install --classic certbot
   sudo ln -s /snap/bin/certbot /usr/bin/certbot
   ```

   **RHEL/CentOS/Fedora:**
   ```bash
   sudo yum install -y snapd python3 curl openssl bind-utils
   sudo systemctl enable --now snapd.socket
   sudo snap install --classic certbot
   sudo ln -s /snap/bin/certbot /usr/bin/certbot
   ```

2. **Verify Certbot Version**:
   ```bash
   certbot --version  # Should be 2.0.0 or higher
   ```

## 📖 Usage

### 🎯 Essential Commands

```bash
# Interactive setup for new users
sudo ./letsencrypt-ip-ssl-manager.sh --setup

# Get certificate for IPv4 address  
sudo ./letsencrypt-ip-ssl-manager.sh -i 203.0.113.10 -e admin@example.com

# Get certificate for IPv6 address
sudo ./letsencrypt-ip-ssl-manager.sh -i 2001:db8::1 -e admin@example.com

# Setup automatic renewal (CRITICAL for 6-day certs!)
sudo ./letsencrypt-ip-ssl-manager.sh --setup-renewal

# Check system status and health
sudo ./letsencrypt-ip-ssl-manager.sh --status

# View current configuration
./letsencrypt-ip-ssl-manager.sh --show-config
```

### 🔧 Management Commands

```bash
# List all certificates and expiration status
sudo ./letsencrypt-ip-ssl-manager.sh --list

# Force renewal of all certificates
sudo ./letsencrypt-ip-ssl-manager.sh --force-renew

# Check available ACME profiles
sudo ./letsencrypt-ip-ssl-manager.sh --check-profiles

# Create manual backup
sudo ./letsencrypt-ip-ssl-manager.sh --backup

# Emergency recovery mode
sudo ./letsencrypt-ip-ssl-manager.sh --emergency

# System integrity check
./letsencrypt-ip-ssl-manager.sh --integrity-check
```

### 📚 Complete Command Reference

| Command | Description | Root Required |
|---------|-------------|---------------|
| **Certificate Operations** |
| `-i, --ip IP_ADDRESS` | Public IP address (IPv4 or IPv6) for certificate | ✅ |
| `-e, --email EMAIL` | Email address for certificate notifications | ✅ |
| `-w, --webroot PATH` | Webroot path for HTTP-01 challenge (default: /var/www/html) | ✅ |
| **Interactive Setup** |
| `--setup` | Quick interactive setup for new users | ✅ |
| `--configure` | Interactive configuration wizard | ✅ |
| `--show-config` | Display current configuration | ❌ |
| **Management Operations** |
| `--install` | Install certbot with profile support | ✅ |
| `--renew` | Renew existing IP certificates | ✅ |
| `--force-renew` | Force renewal of all certificates | ✅ |
| `--setup-renewal` | Configure automatic renewal (every 4 hours) | ✅ |
| `--list` | List all certificates and expiration status | ✅ |
| `--check-profiles` | Show available ACME profiles | ✅ |
| **Information & Diagnostics** |
| `-h, --help` | Show comprehensive help message | ❌ |
| `-v, --version` | Show version information | ❌ |
| `--status` | Generate comprehensive system status report | ❌ |
| `--integrity-check` | Perform system integrity verification | ❌ |
| `--debug` | Enable debug logging for troubleshooting | ❌ |
| **Maintenance & Recovery** |
| `--backup` | Create manual backup of configuration and certificates | ✅ |
| `--restore` | Interactive restore from backup | ✅ |
| `--emergency` | Emergency recovery mode with guided restoration | ✅ |

### Complete Workflow Example

```bash
# 1. Clone and setup (recommended)
git clone https://github.com/yourusername/letsencrypt-ip-manager.git
cd letsencrypt-ip-manager
chmod +x letsencrypt-ip-ssl-manager.sh
sudo ./letsencrypt-ip-ssl-manager.sh --setup

# 2. Or manual steps
sudo ./letsencrypt-ip-ssl-manager.sh --install
curl -4 icanhazip.com  # Check your public IPv4
sudo ufw allow 80/tcp  # Open port 80 if using ufw
sudo ./letsencrypt-ip-ssl-manager.sh -i YOUR_PUBLIC_IP -e your-email@example.com
sudo ./letsencrypt-ip-ssl-manager.sh --setup-renewal

# 3. Verify everything is working
sudo ./letsencrypt-ip-ssl-manager.sh --status
sudo ./letsencrypt-ip-ssl-manager.sh --list
```

## 📁 File Locations

### Certificates
- **Live certificates**: `/etc/letsencrypt/live/YOUR_IP/`
  - `cert.pem` - Certificate
  - `privkey.pem` - Private key
  - `chain.pem` - Intermediate certificates
  - `fullchain.pem` - Certificate + intermediates

### Logs
- **Main log**: `/var/log/letsencrypt-ip-manager/ip-certificate.log`
- **Error log**: `/var/log/letsencrypt-ip-manager/error.log`
- **Audit log**: `/var/log/letsencrypt-ip-manager/audit.log`
- **Renewal log**: `/var/log/letsencrypt-ip-manager/renewal.log`

### Configuration
- **Systemd timer**: `/etc/systemd/system/certbot-ip-renew.timer`
- **Systemd service**: `/etc/systemd/system/certbot-ip-renew.service`
- **Cron job**: `/etc/cron.d/certbot-ip-renew`

## 🔧 Web Server Configuration

### Nginx Example

```nginx
server {
    listen YOUR_IP:443 ssl http2;
    
    ssl_certificate /etc/letsencrypt/live/YOUR_IP/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/YOUR_IP/privkey.pem;
    
    # Modern SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    
    location / {
        root /var/www/html;
        index index.html;
    }
}

# HTTP to HTTPS redirect
server {
    listen YOUR_IP:80;
    return 301 https://$host$request_uri;
}
```

### Apache Example

```apache
<VirtualHost YOUR_IP:443>
    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/YOUR_IP/cert.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/YOUR_IP/privkey.pem
    SSLCertificateChainFile /etc/letsencrypt/live/YOUR_IP/chain.pem
    
    # Modern SSL configuration
    SSLProtocol -all +TLSv1.2 +TLSv1.3
    SSLCipherSuite ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384
    
    DocumentRoot /var/www/html
</VirtualHost>

# HTTP to HTTPS redirect
<VirtualHost YOUR_IP:80>
    Redirect permanent / https://YOUR_IP/
</VirtualHost>
```

## ❓ FAQ

### Why are IP certificates only available in staging?
Let's Encrypt is gradually rolling out IP certificate support. Production availability is expected later in 2025.

### Why do IP certificates only last 6 days?
Short-lived certificates enhance security by limiting the window of exposure if a private key is compromised. They also align with Let's Encrypt's automation philosophy.

### Can I use this for private IP addresses?
No, Let's Encrypt only issues certificates for publicly routable IP addresses. Private IPs (192.168.x.x, 10.x.x.x, etc.) are not supported.

### What happens if renewal fails?
The script sets up multiple renewal mechanisms (systemd timer + cron) running every 4 hours. It also logs all renewal attempts for troubleshooting.

### Can I use DNS-01 challenge instead of HTTP-01?
No, DNS-01 challenge is not supported for IP address certificates.

## 🐛 Troubleshooting

### Common Issues

1. **"Port 80 is not accessible"**
   - Ensure firewall allows port 80: `sudo ufw allow 80/tcp`
   - Check if another service is using port 80: `sudo netstat -tlnp | grep :80`

2. **"IP address appears to be private"**
   - Verify you're using your public IP: `curl -4 icanhazip.com`
   - Check if you're behind NAT/proxy

3. **"Certbot version too old"**
   - Update certbot: `sudo snap refresh certbot`
   - Or reinstall: `sudo ./letsencrypt-ip-manager.sh --install`

4. **"Certificate expired"**
   - Check renewal timer: `sudo systemctl status certbot-ip-renew.timer`
   - Force renewal: `sudo ./letsencrypt-ip-manager.sh --force-renew`

### Debug Mode

Enable detailed logging:
```bash
sudo DEBUG=true ./letsencrypt-ip-manager.sh -i YOUR_IP -e your@email.com
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🔗 Resources

- [Let's Encrypt - IP Address Certificates Announcement](https://letsencrypt.org/2025/07/01/issuing-our-first-ip-address-certificate/)
- [Let's Encrypt - ACME Profiles](https://letsencrypt.org/2025/01/09/acme-profiles/)
- [Let's Encrypt - Staging Environment](https://letsencrypt.org/docs/staging-environment/)
- [Certbot Documentation](https://certbot.eff.org/)
- [ACME Protocol Specification](https://datatracker.ietf.org/doc/html/rfc8555)

## ⭐ Star History

If you find this tool useful, please consider giving it a star on GitHub!

---

<div align="center">

Made with ❤️ for the community by developers who believe in a secure and open internet.

Special thanks to [Let's Encrypt](https://letsencrypt.org/) for making HTTPS accessible to everyone.

</div>