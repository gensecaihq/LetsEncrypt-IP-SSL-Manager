# Security Guide

Comprehensive security best practices for the LetsEncrypt IP SSL Manager.

## 🛡️ Security Overview

The LetsEncrypt IP SSL Manager implements defense-in-depth security principles:

- **Input Validation**: All user inputs are sanitized and validated
- **Privilege Separation**: Minimal privileges required for each operation
- **Secure File Permissions**: Restrictive permissions on sensitive files
- **Audit Logging**: Complete audit trail of all security-relevant actions
- **Error Handling**: Secure error handling without information leakage
- **Code Review**: Security-focused code review and testing

## 🔒 Core Security Features

### Input Validation & Sanitization

**Email Validation:**
```bash
# Validates RFC 5322 compliance
# Checks for dangerous patterns
# Sanitizes special characters
validate_email "user@domain.com"
```

**IP Address Validation:**
```bash
# IPv4/IPv6 format validation
# Private IP range detection
# Reserved address checking
validate_ip_address "203.0.113.10"
```

**Path Validation:**
```bash
# Directory traversal prevention
# Special character sanitization
# Existence and permission checks
validate_path "/var/www/html"
```

**Command Input Validation:**
```bash
# Command injection prevention
# Special character filtering
# Whitelist validation
validate_command_input "user_input"
```

### Privilege Management

**Root Requirement Check:**
```bash
# Only certificate operations require root
# Information commands run as regular user
check_root()  # Called automatically
```

**Operations by Privilege Level:**

| Operation | Root Required | Reason |
|-----------|---------------|---------|
| Certificate generation | ✅ | File system access, certbot execution |
| Certificate renewal | ✅ | Certificate file modification |
| Configuration changes | ✅ | System file modification |
| Status information | ❌ | Read-only operation |
| Help/Version display | ❌ | No system access required |
| Integrity check | ❌ | Read-only system checking |

### File Permissions

**Configuration Security:**
```bash
/etc/letsencrypt-ip-manager/           # 750 root:root
/etc/letsencrypt-ip-manager/config.conf  # 640 root:root
```

**Log Security:**
```bash
/var/log/letsencrypt-ip-manager/       # 750 root:root
/var/log/letsencrypt-ip-manager/*.log  # 640 root:root
```

**Certificate Security:**
```bash
/etc/letsencrypt/live/YOUR_IP/privkey.pem  # 600 root:root (private key)
/etc/letsencrypt/live/YOUR_IP/*.pem        # 644 root:root (public certs)
```

## 🔐 Security Best Practices

### 1. System Hardening

**Firewall Configuration:**
```bash
# Only allow necessary ports
sudo ufw allow 22/tcp   # SSH
sudo ufw allow 80/tcp   # HTTP (required for certificate validation)
sudo ufw allow 443/tcp  # HTTPS
sudo ufw enable

# Or with iptables
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT
sudo iptables -A INPUT -j DROP
```

**SSH Hardening:**
```bash
# Disable root login
echo "PermitRootLogin no" >> /etc/ssh/sshd_config

# Use key-based authentication
echo "PasswordAuthentication no" >> /etc/ssh/sshd_config

# Restart SSH
sudo systemctl restart sshd
```

**System Updates:**
```bash
# Keep system updated
sudo apt update && sudo apt upgrade -y  # Debian/Ubuntu
sudo yum update -y                      # RHEL/CentOS
sudo dnf update -y                      # Fedora

# Enable automatic security updates
sudo dpkg-reconfigure unattended-upgrades  # Ubuntu
```

### 2. Email Security

**Secure Email Configuration:**
```bash
# Use dedicated email for certificates
USER_EMAIL="ssl-admin@yourdomain.com"

# Consider using role-based email
USER_EMAIL="security@yourdomain.com"

# Avoid personal emails for production
# Avoid shared accounts
```

**Email Account Security:**
- Enable two-factor authentication
- Use strong, unique passwords
- Monitor for unusual activity
- Set up email forwarding to security team

### 3. Network Security

**IP Address Validation:**
```bash
# Always validate your public IP
PUBLIC_IP=$(curl -s https://icanhazip.com)
echo "Public IP: $PUBLIC_IP"

# Verify IP ownership
whois $PUBLIC_IP | grep -i "your-organization"
```

**Network Monitoring:**
```bash
# Monitor certificate validation attempts
sudo tail -f /var/log/nginx/access.log | grep "\.well-known/acme-challenge"

# Monitor for suspicious connections
sudo netstat -tulpn | grep :80
sudo ss -tulpn | grep :80
```

**DDoS Protection:**
```bash
# Rate limiting with iptables
sudo iptables -A INPUT -p tcp --dport 80 -m conntrack --ctstate NEW -m limit --limit 25/minute --limit-burst 1000 -j ACCEPT

# Or use fail2ban
sudo apt install fail2ban
sudo systemctl enable fail2ban
```

### 4. Certificate Security

**Certificate Monitoring:**
```bash
# Regular certificate checks
sudo ./letsencrypt-ip-ssl-manager.sh --list

# Monitor expiration dates
sudo ./letsencrypt-ip-ssl-manager.sh --status | grep -i expires

# Set up external monitoring
# - SSL Labs SSL Test: https://www.ssllabs.com/ssltest/
# - Certificate monitoring services
```

**Certificate Backup:**
```bash
# Regular certificate backups
sudo ./letsencrypt-ip-ssl-manager.sh --backup

# Verify backup integrity
sudo ./letsencrypt-ip-ssl-manager.sh --integrity-check

# Store backups securely (encrypted, off-site)
```

**Certificate Transparency Monitoring:**
```bash
# Monitor Certificate Transparency logs
# Use services like:
# - crt.sh: https://crt.sh/
# - Censys: https://censys.io/
# - Facebook CT Monitor
```

### 5. Log Security

**Log Monitoring:**
```bash
# Monitor security events
sudo grep -i "error\|fail\|attack" /var/log/letsencrypt-ip-manager/*.log

# Set up log rotation
sudo logrotate -f /etc/logrotate.conf

# Consider centralized logging
# - rsyslog to remote server
# - ELK stack
# - Splunk
```

**Log Integrity:**
```bash
# Protect log files from tampering
sudo chattr +a /var/log/letsencrypt-ip-manager/*.log  # Append-only

# Use remote logging for critical logs
echo "*.* @@log-server.example.com:514" >> /etc/rsyslog.conf
```

### 6. Backup Security

**Secure Backup Practices:**
```bash
# Encrypt backups
gpg --symmetric --cipher-algo AES256 backup.tar.gz

# Store backups securely
# - Off-site storage
# - Encrypted storage
# - Access controls
# - Regular restore testing
```

**Backup Verification:**
```bash
# Test backup restoration regularly
sudo ./letsencrypt-ip-ssl-manager.sh --restore

# Verify backup integrity
sha256sum backup.tar.gz > backup.tar.gz.sha256
sha256sum -c backup.tar.gz.sha256
```

## 🚨 Security Monitoring

### 1. Real-time Monitoring

**Log Monitoring:**
```bash
# Monitor for security events
sudo tail -f /var/log/letsencrypt-ip-manager/audit.log

# Watch for failed attempts
sudo grep -i "failed\|error" /var/log/letsencrypt-ip-manager/*.log | tail -10

# Monitor system logs
sudo journalctl -f | grep -i "letsencrypt\|certbot"
```

**Process Monitoring:**
```bash
# Monitor running processes
ps aux | grep -E "(certbot|letsencrypt)"

# Check for unexpected processes
sudo lsof -i :80
sudo lsof -i :443
```

### 2. Automated Monitoring

**Health Check Script:**
```bash
#!/bin/bash
# /usr/local/bin/ssl-health-check.sh

# Check certificate status
STATUS=$(./letsencrypt-ip-ssl-manager.sh --status)
ERRORS=$(echo "$STATUS" | grep -c "ERROR\|FAIL")

if [ "$ERRORS" -gt 0 ]; then
    echo "SSL Manager health check failed: $ERRORS errors found"
    echo "$STATUS" | grep "ERROR\|FAIL"
    exit 1
fi

echo "SSL Manager health check passed"
exit 0
```

**Cron Monitoring:**
```bash
# Add to crontab for regular checks
0 */6 * * * /usr/local/bin/ssl-health-check.sh

# Email alerts on failure
0 */6 * * * /usr/local/bin/ssl-health-check.sh || echo "SSL health check failed" | mail -s "SSL Alert" admin@example.com
```

### 3. External Monitoring

**Certificate Monitoring Services:**
- SSL Labs SSL Test (https://www.ssllabs.com/ssltest/)
- Qualys SSL Server Test
- Hardenize
- SecurityHeaders.com

**Uptime Monitoring:**
- Pingdom
- UptimeRobot
- StatusCake
- Site24x7

## 🔧 Security Configuration

### 1. Web Server Security

**Nginx Security Headers:**
```nginx
server {
    listen 443 ssl http2;
    
    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/YOUR_IP/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/YOUR_IP/privkey.pem;
    
    # Security Headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options DENY;
    add_header X-XSS-Protection "1; mode=block";
    add_header Referrer-Policy "strict-origin-when-cross-origin";
    
    # Modern SSL Configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    
    # OCSP Stapling
    ssl_stapling on;
    ssl_stapling_verify on;
    ssl_trusted_certificate /etc/letsencrypt/live/YOUR_IP/chain.pem;
    resolver 8.8.8.8 8.8.4.4 valid=300s;
    resolver_timeout 5s;
}
```

**Apache Security Headers:**
```apache
<VirtualHost YOUR_IP:443>
    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/YOUR_IP/cert.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/YOUR_IP/privkey.pem
    SSLCertificateChainFile /etc/letsencrypt/live/YOUR_IP/chain.pem
    
    # Security Headers
    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"
    Header always set X-Content-Type-Options nosniff
    Header always set X-Frame-Options DENY
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"
    
    # Modern SSL Configuration
    SSLProtocol -all +TLSv1.2 +TLSv1.3
    SSLCipherSuite ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384
    SSLHonorCipherOrder off
    
    # OCSP Stapling
    SSLUseStapling on
</VirtualHost>
```

### 2. System Security Configuration

**Secure Script Configuration:**
```bash
# /etc/letsencrypt-ip-manager/config.conf

# Security settings
LOG_LEVEL="INFO"              # Don't use DEBUG in production
AUTO_RENEWAL_ENABLED="true"   # Ensure automatic renewal
RENEWAL_NOTIFICATIONS="true"  # Enable notifications

# Restrict custom hooks for security
DEPLOY_HOOK_CUSTOM=""         # Only use trusted commands
```

**Environment Security:**
```bash
# Secure environment variables
unset HISTFILE                # Disable command history
umask 077                    # Restrictive file creation mask

# Secure shell options
set +H                       # Disable history expansion
```

## 🚨 Incident Response

### 1. Security Incident Detection

**Signs of Compromise:**
- Unexpected certificate changes
- Unusual network activity on ports 80/443
- Failed authentication attempts in logs
- Suspicious processes or files
- Changes to configuration files

**Immediate Response:**
```bash
# 1. Isolate the system
sudo iptables -A INPUT -j DROP    # Block all incoming traffic

# 2. Preserve evidence
sudo cp -r /var/log/letsencrypt-ip-manager /tmp/incident-logs
sudo cp /etc/letsencrypt-ip-manager/config.conf /tmp/

# 3. Check for unauthorized changes
sudo find /etc/letsencrypt -type f -mtime -1 -ls
sudo find /var/log/letsencrypt-ip-manager -type f -mtime -1 -ls

# 4. Review recent activity
sudo grep -i "$(date +'%Y-%m-%d')" /var/log/letsencrypt-ip-manager/*.log
```

### 2. Certificate Compromise Response

**If Private Key Compromised:**
```bash
# 1. Revoke certificate immediately
sudo certbot revoke --cert-path /etc/letsencrypt/live/YOUR_IP/cert.pem

# 2. Generate new certificate
sudo ./letsencrypt-ip-ssl-manager.sh -i YOUR_IP -e YOUR_EMAIL

# 3. Update web server configuration
sudo systemctl reload nginx  # or apache2

# 4. Monitor for unauthorized use
# Check Certificate Transparency logs for your IP
```

**Certificate Monitoring:**
```bash
# Monitor for unauthorized certificates
curl -s "https://crt.sh/?q=YOUR_IP&output=json" | jq -r '.[].common_name'

# Set up automated monitoring
echo "*/30 * * * * curl -s 'https://crt.sh/?q=YOUR_IP&output=json' | jq length > /tmp/cert_count && [ \$(cat /tmp/cert_count) -gt 1 ] && echo 'Multiple certificates detected for YOUR_IP' | mail -s 'Certificate Alert' admin@example.com" | crontab -
```

### 3. Recovery Procedures

**System Recovery:**
```bash
# 1. Create emergency backup
sudo ./letsencrypt-ip-ssl-manager.sh --emergency

# 2. Restore from known good backup
sudo ./letsencrypt-ip-ssl-manager.sh --restore

# 3. Verify system integrity
sudo ./letsencrypt-ip-ssl-manager.sh --integrity-check

# 4. Update all credentials
# - Change email passwords
# - Rotate SSH keys
# - Update API keys

# 5. Review and update security measures
```

## 📋 Security Checklist

### Pre-deployment Security Review

- [ ] **System Hardening**
  - [ ] Firewall configured and enabled
  - [ ] SSH hardened (key-based auth, no root login)
  - [ ] System updates current
  - [ ] Unnecessary services disabled

- [ ] **Script Security**
  - [ ] Latest script version installed
  - [ ] Configuration file permissions correct (640)
  - [ ] Log directory permissions correct (750)
  - [ ] No sensitive data in configuration

- [ ] **Network Security**
  - [ ] Public IP verified and owned
  - [ ] Port 80 accessible for validation
  - [ ] Network monitoring configured
  - [ ] DDoS protection in place

- [ ] **Certificate Security**
  - [ ] Strong email account configured
  - [ ] Automatic renewal enabled
  - [ ] Certificate monitoring configured
  - [ ] Backup procedures tested

### Ongoing Security Maintenance

- [ ] **Weekly Tasks**
  - [ ] Review security logs
  - [ ] Check certificate status
  - [ ] Verify backup integrity
  - [ ] Monitor external certificate transparency logs

- [ ] **Monthly Tasks**
  - [ ] Security patch updates
  - [ ] Rotate backup media
  - [ ] Review access controls
  - [ ] Test incident response procedures

- [ ] **Quarterly Tasks**
  - [ ] Full security assessment
  - [ ] Update security documentation
  - [ ] Review and update monitoring alerts
  - [ ] Conduct security training

## 🔐 Advanced Security Features

### 1. Multi-Factor Authentication

While the script itself doesn't support MFA, secure the underlying systems:

```bash
# Enable MFA for SSH
sudo apt install libpam-google-authenticator  # Ubuntu
google-authenticator  # Configure for user

# Add to SSH configuration
echo "AuthenticationMethods publickey,keyboard-interactive" >> /etc/ssh/sshd_config
echo "ChallengeResponseAuthentication yes" >> /etc/ssh/sshd_config
```

### 2. Certificate Pinning

Implement certificate pinning in applications:

```javascript
// Example: HTTP Public Key Pinning header
const expectedPin = 'pin-sha256="HASH_OF_YOUR_CERTIFICATE"';
response.setHeader('Public-Key-Pins', `${expectedPin}; max-age=86400; includeSubDomains`);
```

### 3. Security Automation

```bash
#!/bin/bash
# Automated security monitoring script

# Check for certificate changes
CERT_HASH=$(openssl x509 -in /etc/letsencrypt/live/YOUR_IP/cert.pem -noout -fingerprint -sha256)
EXPECTED_HASH_FILE="/etc/ssl/expected_cert_hash"

if [ -f "$EXPECTED_HASH_FILE" ]; then
    EXPECTED_HASH=$(cat "$EXPECTED_HASH_FILE")
    if [ "$CERT_HASH" != "$EXPECTED_HASH" ]; then
        echo "Certificate change detected!" | mail -s "Security Alert" admin@example.com
    fi
else
    echo "$CERT_HASH" > "$EXPECTED_HASH_FILE"
fi

# Check for unauthorized configuration changes
find /etc/letsencrypt-ip-manager -type f -newer /tmp/last_security_check 2>/dev/null | while read file; do
    echo "Configuration file changed: $file" | mail -s "Security Alert" admin@example.com
done

touch /tmp/last_security_check
```

---

*For additional security concerns, contact security@project.com or review the [Troubleshooting Guide](TROUBLESHOOTING.md) for security-related issues.*