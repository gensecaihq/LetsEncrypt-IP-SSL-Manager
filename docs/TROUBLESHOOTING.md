# Troubleshooting Guide

Comprehensive troubleshooting guide for common issues with the LetsEncrypt IP SSL Manager.

## 📋 Quick Diagnostics

### First Steps for Any Issue

```bash
# 1. Check system status
./letsencrypt-ip-ssl-manager.sh --status

# 2. Run integrity check
./letsencrypt-ip-ssl-manager.sh --integrity-check  

# 3. Check recent logs
sudo tail -20 /var/log/letsencrypt-ip-manager/error.log

# 4. Enable debug mode and retry
sudo ./letsencrypt-ip-ssl-manager.sh --debug [your-command]
```

### Emergency Recovery

If the system is completely broken:

```bash
# Access emergency recovery mode
sudo ./letsencrypt-ip-ssl-manager.sh --emergency
```

## 🚨 Common Issues

### Installation Issues

#### Issue: "Permission denied" when running script

**Symptoms:**
```
bash: ./letsencrypt-ip-ssl-manager.sh: Permission denied
```

**Solutions:**
```bash
# Make script executable
chmod +x letsencrypt-ip-ssl-manager.sh

# If still failing, check file ownership
ls -la letsencrypt-ip-ssl-manager.sh
sudo chown $USER:$USER letsencrypt-ip-ssl-manager.sh
```

#### Issue: "This script must be run as root"

**Symptoms:**
```
✗ This script must be run as root or with sudo privileges
```

**Solutions:**
```bash
# Use sudo for certificate operations
sudo ./letsencrypt-ip-ssl-manager.sh -i YOUR_IP -e YOUR_EMAIL

# For info commands, no sudo needed
./letsencrypt-ip-ssl-manager.sh --help
./letsencrypt-ip-ssl-manager.sh --status
```

#### Issue: Certbot not found or wrong version

**Symptoms:**
```
✗ Certbot not found
Certbot version X.X.X is too old (minimum 2.0.0 required)
```

**Solutions:**
```bash
# Auto-install certbot
sudo ./letsencrypt-ip-ssl-manager.sh --install

# Manual snap installation
sudo snap install --classic certbot
sudo ln -sf /snap/bin/certbot /usr/bin/certbot

# Verify version
certbot --version
```

#### Issue: Dependencies missing

**Symptoms:**
```
curl: command not found
host: command not found  
openssl: command not found
```

**Solutions:**
```bash
# Auto-install dependencies
sudo ./letsencrypt-ip-ssl-manager.sh --install

# Manual installation by platform:

# Debian/Ubuntu
sudo apt update && sudo apt install -y curl openssl dnsutils

# RHEL/CentOS/Fedora  
sudo yum install -y curl openssl bind-utils  # or dnf

# Alpine
sudo apk add --no-cache curl openssl bind-tools

# FreeBSD
sudo pkg install curl openssl bind-tools
```

### Network and Connectivity Issues

#### Issue: "Port 80 is not accessible"

**Symptoms:**
```
✗ Port 80 accessibility check failed
Connection to IP:80 failed
```

**Diagnosis:**
```bash
# Test port 80 connectivity
telnet YOUR_IP 80
# or
nc -zv YOUR_IP 80

# Check if service is listening
sudo netstat -tlnp | grep :80
# or
sudo ss -tlnp | grep :80
```

**Solutions:**
```bash
# Check firewall (varies by system)
sudo ufw status        # Ubuntu
sudo firewall-cmd --list-all  # RHEL/CentOS
sudo iptables -L       # Generic

# Open port 80
sudo ufw allow 80/tcp  # Ubuntu
sudo firewall-cmd --add-port=80/tcp --permanent  # RHEL/CentOS
sudo firewall-cmd --reload

# Check web server status
sudo systemctl status nginx    # or apache2/httpd
sudo systemctl start nginx     # if stopped
```

#### Issue: "IP address appears to be private"

**Symptoms:**
```
⚠ IP address appears to be private or reserved: 192.168.1.100
✗ Let's Encrypt requires publicly routable IP addresses
```

**Solutions:**
```bash
# Find your public IP
curl -4 icanhazip.com    # IPv4
curl -6 icanhazip.com    # IPv6

# Verify IP is public, not private ranges:
# Private IPv4: 10.x.x.x, 172.16-31.x.x, 192.168.x.x
# Private IPv6: fc00::/7, fe80::/10
```

#### Issue: DNS resolution problems

**Symptoms:**
```
✗ DNS resolution failed for domain
nslookup: command not found
```

**Solutions:**
```bash
# Test DNS resolution
nslookup google.com
dig google.com
host google.com

# Install DNS tools if missing
sudo apt install -y dnsutils        # Debian/Ubuntu
sudo yum install -y bind-utils       # RHEL/CentOS
sudo apk add bind-tools              # Alpine

# Check DNS servers
cat /etc/resolv.conf

# Try different DNS servers
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
```

### Certificate Issues

#### Issue: "Challenge validation failed"

**Symptoms:**
```
✗ Challenge validation failed
The following errors were reported by the server:
Domain: YOUR_IP
Type: connection
Detail: Fetching http://YOUR_IP/.well-known/acme-challenge/...
```

**Diagnosis:**
```bash
# Test challenge path manually
curl -v http://YOUR_IP/.well-known/acme-challenge/test

# Check webroot permissions
ls -la /var/www/html/.well-known/acme-challenge/
sudo chmod 755 /var/www/html/.well-known/acme-challenge/
```

**Solutions:**
```bash
# Verify webroot is correct
sudo ./letsencrypt-ip-ssl-manager.sh -i YOUR_IP -e YOUR_EMAIL -w /path/to/webroot

# Check web server configuration
sudo nginx -t           # Nginx
sudo apache2ctl -t      # Apache

# Restart web server
sudo systemctl restart nginx    # or apache2
```

#### Issue: "Certificate already exists"

**Symptoms:**
```
Certificate already exists for this IP address
```

**Solutions:**
```bash
# Force renewal
sudo ./letsencrypt-ip-ssl-manager.sh --force-renew

# Or check existing certificates
sudo ./letsencrypt-ip-ssl-manager.sh --list

# Remove old certificate if needed
sudo certbot delete --cert-name YOUR_IP
```

#### Issue: "Rate limit exceeded"

**Symptoms:**
```
Rate limit exceeded
Too many requests for this IP address
```

**Solutions:**
```bash
# Wait for rate limit reset (usually 1 hour)
# Check rate limits at: https://letsencrypt.org/docs/rate-limits/

# For testing, use staging environment
sudo certbot certonly --staging --standalone -d YOUR_IP
```

### Renewal Issues

#### Issue: Automatic renewal not working

**Symptoms:**
```
Certificate expired
No automatic renewal attempts in logs
```

**Diagnosis:**
```bash
# Check renewal setup
sudo ./letsencrypt-ip-ssl-manager.sh --status

# Check systemd timer (if applicable)
sudo systemctl status certbot-ip-renew.timer
sudo systemctl list-timers | grep certbot

# Check cron job
sudo crontab -l | grep certbot
cat /etc/cron.d/certbot-ip-renew
```

**Solutions:**
```bash
# Re-setup automatic renewal
sudo ./letsencrypt-ip-ssl-manager.sh --setup-renewal

# Test renewal manually
sudo ./letsencrypt-ip-ssl-manager.sh --renew

# Check renewal logs
sudo tail -50 /var/log/letsencrypt-ip-manager/renewal.log
```

#### Issue: "Deploy hook failed"

**Symptoms:**
```
✗ Deploy hook execution failed
Web server reload failed
```

**Solutions:**
```bash
# Check web server status
sudo systemctl status nginx    # or apache2/httpd

# Test web server configuration
sudo nginx -t                  # Nginx
sudo apache2ctl configtest     # Apache

# Manually reload web server
sudo systemctl reload nginx
sudo systemctl reload apache2
```

### Configuration Issues

#### Issue: "Configuration file not found"

**Symptoms:**
```
⚠ Configuration file missing
No configuration file found
```

**Solutions:**
```bash
# Create configuration interactively
sudo ./letsencrypt-ip-ssl-manager.sh --configure

# Or manually create directories
sudo mkdir -p /etc/letsencrypt-ip-manager
sudo chmod 750 /etc/letsencrypt-ip-manager

# Check configuration
./letsencrypt-ip-ssl-manager.sh --show-config
```

#### Issue: "Invalid email address format"

**Symptoms:**
```
✗ Invalid email address format: your_email
```

**Solutions:**
```bash
# Use proper email format
sudo ./letsencrypt-ip-ssl-manager.sh -i YOUR_IP -e user@domain.com

# Check email in configuration
./letsencrypt-ip-ssl-manager.sh --show-config

# Update email interactively
sudo ./letsencrypt-ip-ssl-manager.sh --configure
```

### Log and Permission Issues

#### Issue: "Log directory not writable"

**Symptoms:**
```
✗ Log directory not writable
Warning: Using fallback log directory
```

**Solutions:**
```bash
# Check log directory permissions
ls -ld /var/log/letsencrypt-ip-manager

# Fix permissions
sudo mkdir -p /var/log/letsencrypt-ip-manager
sudo chmod 750 /var/log/letsencrypt-ip-manager
sudo chown root:root /var/log/letsencrypt-ip-manager

# Check disk space
df -h /var/log/
```

#### Issue: "Lock file exists"

**Symptoms:**
```
✗ Another instance is already running
Lock file exists: /var/run/letsencrypt-ip-manager.lock
```

**Solutions:**
```bash
# Check if process is actually running
ps aux | grep letsencrypt-ip

# If no process, remove stale lock
sudo rm -f /var/run/letsencrypt-ip-manager.lock

# If process exists, wait for completion or kill if hung
sudo kill [PID]
```

### Platform-Specific Issues

#### macOS Issues

**Issue: "command not found" errors**

**Solutions:**
```bash
# Install Homebrew if not present
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install dependencies via Homebrew
brew install curl openssl bind certbot

# Update PATH
echo 'export PATH="/opt/homebrew/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

#### BSD Issues

**Issue: Package manager not found**

**Solutions:**
```bash
# FreeBSD
sudo pkg install curl openssl bind-tools py39-certbot

# OpenBSD  
sudo pkg_add curl openssl-- bind-utils python3

# NetBSD
sudo pkgin install curl openssl bind-utils python38
```

#### Alpine Linux Issues

**Issue: "bash not found"**

**Solutions:**
```bash
# Install bash
sudo apk add bash

# Or run with sh (might have limited functionality)
sh ./letsencrypt-ip-ssl-manager.sh --help
```

## 🔍 Advanced Debugging

### Enable Comprehensive Debugging

```bash
# Method 1: Command line flag
sudo ./letsencrypt-ip-ssl-manager.sh --debug [command]

# Method 2: Environment variable
sudo DEBUG=true ./letsencrypt-ip-ssl-manager.sh [command]

# Method 3: Enable bash debugging
sudo bash -x ./letsencrypt-ip-ssl-manager.sh [command]
```

### Analyzing Log Files

```bash
# Check all log files for errors
sudo grep -i error /var/log/letsencrypt-ip-manager/*.log

# Monitor real-time log activity
sudo tail -f /var/log/letsencrypt-ip-manager/ip-certificate.log

# Check specific time periods
sudo grep "2025-01-29" /var/log/letsencrypt-ip-manager/*.log

# Check certificate-specific logs
sudo grep "YOUR_IP" /var/log/letsencrypt-ip-manager/*.log
```

### Network Debugging

```bash
# Test HTTP connectivity
curl -v http://YOUR_IP/.well-known/acme-challenge/test

# Test HTTPS connectivity  
curl -v https://YOUR_IP/

# Check routing
traceroute YOUR_IP

# Test from external source
# Use online tools like:
# - https://www.whatsmydns.net/
# - https://downforeveryoneorjustme.com/
```

### System Resource Debugging

```bash
# Check disk space
df -h

# Check memory usage
free -h

# Check running processes
ps aux | grep -E "(certbot|letsencrypt)"

# Check system load
uptime
top
```

## 📞 Getting Help

### Information to Collect

Before seeking help, collect this information:

```bash
# 1. System information
./letsencrypt-ip-ssl-manager.sh --status > debug_info.txt

# 2. Error logs
sudo tail -50 /var/log/letsencrypt-ip-manager/error.log >> debug_info.txt

# 3. Configuration
./letsencrypt-ip-ssl-manager.sh --show-config >> debug_info.txt

# 4. System details
uname -a >> debug_info.txt
echo "OS: $(lsb_release -d 2>/dev/null || cat /etc/os-release | head -1)" >> debug_info.txt

# 5. Certbot version
certbot --version >> debug_info.txt 2>&1
```

### Support Channels

1. **GitHub Issues**: Open detailed bug reports with debug info
2. **Documentation**: Check [User Manual](USER_MANUAL.md) and [FAQ](FAQ.md)  
3. **Community Forums**: Let's Encrypt community forums
4. **Security Issues**: Email security@project.com for sensitive issues

### Creating a Bug Report

Include in your bug report:
- **Operating System**: Distribution and version
- **Script Version**: Output of `--version`
- **Command Used**: Exact command that failed
- **Error Message**: Complete error output
- **Debug Info**: Output from debug info collection above
- **Expected Behavior**: What you expected to happen
- **Actual Behavior**: What actually happened

### Temporary Workarounds

#### If automatic renewal fails:
```bash
# Manual renewal
sudo certbot renew --cert-name YOUR_IP

# Or regenerate certificate
sudo certbot certonly --standalone -d YOUR_IP --email YOUR_EMAIL
```

#### If web server integration fails:
```bash
# Use standalone mode temporarily
sudo certbot certonly --standalone -d YOUR_IP --email YOUR_EMAIL

# Then manually configure web server
```

#### If script is completely broken:
```bash
# Use certbot directly
sudo certbot certonly --standalone -d YOUR_IP --email YOUR_EMAIL --server https://acme-staging-v02.api.letsencrypt.org/directory

# Setup manual cron job
echo "0 */4 * * * root certbot renew --quiet" | sudo tee /etc/cron.d/certbot-manual
```

---

*Still having issues? Check the [FAQ](FAQ.md) or open an issue on GitHub with detailed debug information.*