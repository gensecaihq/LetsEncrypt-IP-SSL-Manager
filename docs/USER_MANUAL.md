# User Manual

Complete guide to using the LetsEncrypt IP SSL Manager for certificate management.

## 📖 Table of Contents

1. [Quick Start](#-quick-start)
2. [Basic Operations](#-basic-operations)
3. [Interactive Features](#-interactive-features)
4. [Certificate Management](#-certificate-management)
5. [System Management](#-system-management)
6. [Advanced Features](#-advanced-features)
7. [Configuration](#-configuration)
8. [Monitoring & Logs](#-monitoring--logs)
9. [Best Practices](#-best-practices)

## 🚀 Quick Start

### First-Time Setup

```bash
# 1. Download and make executable
git clone https://github.com/yourusername/letsencrypt-ip-manager.git
cd letsencrypt-ip-manager
chmod +x letsencrypt-ip-ssl-manager.sh

# 2. Run interactive setup
sudo ./letsencrypt-ip-ssl-manager.sh --setup
```

The interactive setup will:
- ✅ Detect your operating system
- ✅ Install required dependencies  
- ✅ Configure your preferences
- ✅ Set up automatic renewal
- ✅ Test the installation

### Your First Certificate

```bash
# Replace with your actual public IP and email
sudo ./letsencrypt-ip-ssl-manager.sh -i 203.0.113.10 -e admin@example.com
```

## 🎯 Basic Operations

### Getting Help

```bash
# Show complete help
./letsencrypt-ip-ssl-manager.sh --help

# Show version information
./letsencrypt-ip-ssl-manager.sh --version

# Check system status
./letsencrypt-ip-ssl-manager.sh --status
```

### Certificate Operations

#### Obtain a Certificate

```bash
# For IPv4 address
sudo ./letsencrypt-ip-ssl-manager.sh -i 203.0.113.10 -e admin@example.com

# For IPv6 address  
sudo ./letsencrypt-ip-ssl-manager.sh -i 2001:db8::1 -e admin@example.com

# With custom webroot
sudo ./letsencrypt-ip-ssl-manager.sh -i 203.0.113.10 -e admin@example.com -w /var/www/mysite
```

#### List Certificates

```bash
# Show all certificates and their status
sudo ./letsencrypt-ip-ssl-manager.sh --list
```

Example output:
```
📋 IP Certificate Status Report
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Certificate for 203.0.113.10:
  Status: ✅ Valid
  Expires: 2025-02-02 15:30:45 UTC (4 days remaining)
  Serial: 04:5e:7a:2c:8f:91:3b:d2
  Last Renewal: 2025-01-29 15:30:45 UTC
  Auto-Renewal: ✅ Enabled
```

#### Renew Certificates

```bash
# Renew all certificates (normal renewal)
sudo ./letsencrypt-ip-ssl-manager.sh --renew

# Force renewal of all certificates
sudo ./letsencrypt-ip-ssl-manager.sh --force-renew
```

### Check ACME Profiles

```bash
# View available ACME profiles
sudo ./letsencrypt-ip-ssl-manager.sh --check-profiles
```

## 🎨 Interactive Features

### Interactive Setup

The most user-friendly way to get started:

```bash
sudo ./letsencrypt-ip-ssl-manager.sh --setup
```

This wizard will guide you through:
1. **System Detection**: Automatically detect OS and configure dependencies
2. **Email Configuration**: Set your notification email address
3. **Webroot Setup**: Configure your web server document root
4. **Certificate Generation**: Optionally create your first certificate
5. **Auto-Renewal Setup**: Configure automatic certificate renewal
6. **Testing**: Verify everything is working correctly

### Configuration Wizard

Customize your settings interactively:

```bash
sudo ./letsencrypt-ip-ssl-manager.sh --configure
```

Configuration options:
- **Email Address**: For certificate notifications and recovery
- **Default Webroot**: Document root for HTTP-01 challenges
- **Key Size**: RSA key size (2048, 3072, 4096)
- **Auto-Renewal**: Enable/disable automatic renewal
- **Notifications**: Email notifications for renewals
- **Web Server**: Auto-detect and configure web server
- **Logging Level**: Control verbosity of logs

### View Current Configuration

```bash
# Display current settings (no root required)
./letsencrypt-ip-ssl-manager.sh --show-config
```

## 🔐 Certificate Management

### Understanding IP Certificates

IP certificates from Let's Encrypt have special characteristics:
- **Short-lived**: Valid for only 6 days
- **Staging Only**: Currently only available in staging environment
- **Public IPs Only**: Private/local IPs are not supported
- **HTTP-01 Challenge**: Only validation method supported
- **Aggressive Renewal**: Must renew every 4 hours

### Automatic Renewal Setup

**Critical for IP certificates due to 6-day expiration!**

```bash
# Setup automatic renewal (runs every 4 hours)
sudo ./letsencrypt-ip-ssl-manager.sh --setup-renewal
```

This creates:
- **SystemD Timer**: Primary renewal mechanism (modern systems)
- **Cron Job**: Fallback renewal mechanism (all systems)
- **Deploy Hooks**: Automatic web server reload after renewal

### Certificate Locations

After successful certificate generation:

```
/etc/letsencrypt/live/YOUR_IP/
├── cert.pem         # Certificate only
├── privkey.pem      # Private key
├── chain.pem        # Intermediate certificates
└── fullchain.pem    # Certificate + intermediates (use this)
```

### Web Server Configuration

#### Nginx Configuration

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

#### Apache Configuration

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

## ⚙️ System Management

### System Status

Get comprehensive system information:

```bash
./letsencrypt-ip-ssl-manager.sh --status
```

Status report includes:
- Script version and process information
- Operating system details and compatibility
- Dependency status and versions
- Configuration status
- Certificate information
- Network connectivity tests
- Log file status
- Backup information

### Integrity Check

Verify system integrity:

```bash
./letsencrypt-ip-ssl-manager.sh --integrity-check
```

Checks:
- Configuration file validity
- Log directory permissions
- Required dependencies
- Certificate file integrity
- Web server configuration
- Network connectivity

### Dependency Management

Install missing dependencies:

```bash
# Install all required dependencies
sudo ./letsencrypt-ip-ssl-manager.sh --install
```

Automatically detects and installs:
- Certbot with ACME profile support
- System utilities (curl, openssl, DNS tools)
- Python requirements
- Package manager updates

## 🔧 Advanced Features

### Backup and Recovery

#### Create Backup

```bash
# Manual backup
sudo ./letsencrypt-ip-ssl-manager.sh --backup
```

Backs up:
- Configuration files
- Certificate data
- Log files
- System settings

#### Restore from Backup

```bash
# Interactive restore
sudo ./letsencrypt-ip-ssl-manager.sh --restore
```

Lists available backups and allows selection for restoration.

#### Emergency Recovery

```bash
# Emergency recovery mode
sudo ./letsencrypt-ip-ssl-manager.sh --emergency
```

Emergency recovery provides:
- System state analysis
- Configuration restoration options
- Certificate recovery procedures
- Guided troubleshooting

### Debug Mode

Enable detailed logging for troubleshooting:

```bash
# Run any command with debug output
sudo ./letsencrypt-ip-ssl-manager.sh --debug --status
sudo DEBUG=true ./letsencrypt-ip-ssl-manager.sh -i IP -e EMAIL
```

Debug mode provides:
- Verbose command output
- Detailed error messages
- Function call tracing
- Variable state information

## ⚙️ Configuration

### Configuration File

Location: `/etc/letsencrypt-ip-manager/config.conf`

```bash
# User preferences
USER_EMAIL="admin@example.com"
USER_WEBROOT="/var/www/html"
USER_KEY_SIZE="4096"

# Renewal preferences  
AUTO_RENEWAL_ENABLED="true"
RENEWAL_NOTIFICATIONS="true"
RENEWAL_WEB_SERVER="auto"

# Logging preferences
LOG_LEVEL="INFO"
LOG_RETENTION_DAYS="30"

# Advanced settings
CHALLENGE_TYPE="http-01"
PREFERRED_CHAIN=""
DEPLOY_HOOK_CUSTOM=""
```

### Environment Variables

Override behavior with environment variables:

```bash
# Enable debug mode
export DEBUG=true

# Custom log level
export LOG_LEVEL="DEBUG"

# Custom config location
export CONFIG_FILE="/custom/path/config.conf"
```

### Command-Line Options

All configuration can be overridden via command line:

```bash
# Override webroot
sudo ./letsencrypt-ip-ssl-manager.sh -i IP -e EMAIL -w /custom/webroot

# Enable debug logging
sudo ./letsencrypt-ip-ssl-manager.sh --debug -i IP -e EMAIL
```

## 📊 Monitoring & Logs

### Log Files

| Log File | Purpose | Location |
|----------|---------|----------|
| **Main Log** | General operations | `/var/log/letsencrypt-ip-manager/ip-certificate.log` |
| **Error Log** | Errors and warnings | `/var/log/letsencrypt-ip-manager/error.log` |
| **Audit Log** | Security and config changes | `/var/log/letsencrypt-ip-manager/audit.log` |
| **Renewal Log** | Automatic renewal events | `/var/log/letsencrypt-ip-manager/renewal.log` |

### Monitoring Commands

```bash
# View recent activity
sudo tail -f /var/log/letsencrypt-ip-manager/ip-certificate.log

# Check for errors
sudo tail -20 /var/log/letsencrypt-ip-manager/error.log

# Monitor renewal attempts
sudo tail -f /var/log/letsencrypt-ip-manager/renewal.log

# View configuration changes
sudo cat /var/log/letsencrypt-ip-manager/audit.log
```

### Log Levels

Configure log verbosity in configuration:

- **DEBUG**: Detailed debugging information
- **INFO**: General information messages (default)
- **WARN**: Warning messages only
- **ERROR**: Error messages only

### Log Rotation

Logs are automatically rotated:
- **Size Limit**: 10MB per log file
- **Retention**: Configurable (default 30 days)
- **Compression**: Old logs are compressed
- **Cleanup**: Automatic removal of old logs

## 💡 Best Practices

### Security

1. **Use Strong Email Accounts**: Use a secure email for certificate notifications
2. **Monitor Logs**: Regularly check error and audit logs
3. **Backup Regularly**: Create frequent backups of configuration and certificates
4. **Update Frequently**: Keep the script and dependencies updated
5. **Restrict Access**: Limit access to configuration files and logs

### Reliability

1. **Test Renewals**: Regularly test the renewal process
2. **Monitor Expiration**: Set up additional monitoring for certificate expiration
3. **Multiple Mechanisms**: Use both SystemD timers and cron for renewal
4. **Fallback Plans**: Have manual renewal procedures documented
5. **Health Checks**: Use `--status` command in monitoring systems

### Performance

1. **Optimize Webroot**: Use a dedicated webroot for challenges
2. **Cache DNS**: Configure local DNS caching
3. **Monitor Resources**: Watch CPU and memory usage during operations
4. **Schedule Wisely**: Space out renewal attempts across time
5. **Network Tuning**: Ensure reliable internet connectivity

### Operational

1. **Documentation**: Keep records of your IP addresses and certificates
2. **Change Management**: Track configuration changes
3. **Testing Environment**: Test changes in staging before production
4. **Monitoring Integration**: Integrate with existing monitoring systems
5. **Incident Response**: Have procedures for certificate-related incidents

## 🔧 Common Workflows

### Setting Up New Server

```bash
# 1. Install script
git clone https://github.com/yourusername/letsencrypt-ip-manager.git
cd letsencrypt-ip-manager
chmod +x letsencrypt-ip-ssl-manager.sh

# 2. Run setup
sudo ./letsencrypt-ip-ssl-manager.sh --setup

# 3. Get certificate
sudo ./letsencrypt-ip-ssl-manager.sh -i YOUR_IP -e YOUR_EMAIL

# 4. Configure web server (see examples above)

# 5. Verify renewal
sudo ./letsencrypt-ip-ssl-manager.sh --list
```

### Migrating Certificates

```bash
# 1. Backup on old server
sudo ./letsencrypt-ip-ssl-manager.sh --backup

# 2. Copy backup to new server
scp backup.tar.gz newserver:/tmp/

# 3. On new server, restore
sudo ./letsencrypt-ip-ssl-manager.sh --restore

# 4. Test certificate
sudo ./letsencrypt-ip-ssl-manager.sh --list
```

### Troubleshooting Issues

```bash
# 1. Check system status
./letsencrypt-ip-ssl-manager.sh --status

# 2. Run integrity check
./letsencrypt-ip-ssl-manager.sh --integrity-check

# 3. Check logs
sudo tail -50 /var/log/letsencrypt-ip-manager/error.log

# 4. Try with debug mode
sudo ./letsencrypt-ip-ssl-manager.sh --debug --renew

# 5. If needed, emergency recovery
sudo ./letsencrypt-ip-ssl-manager.sh --emergency
```

---

*For more advanced topics, see the [API Reference](API_REFERENCE.md) and [Troubleshooting Guide](TROUBLESHOOTING.md).*