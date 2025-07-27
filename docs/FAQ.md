# Frequently Asked Questions (FAQ)

Common questions and answers about the LetsEncrypt IP SSL Manager.

## 🚀 Getting Started

### Q: What is the LetsEncrypt IP SSL Manager?
**A:** It's an enterprise-grade bash script that automates the process of obtaining and managing SSL certificates for IP addresses using Let's Encrypt. It's designed as a "Swiss Army Knife" tool with comprehensive features for production environments.

### Q: Why do I need SSL certificates for IP addresses?
**A:** SSL certificates for IP addresses enable HTTPS encryption when accessing services directly by IP address, which is common in:
- API servers accessed by IP
- Internal services without domain names
- Development and testing environments
- Microservices with direct IP communication
- Load balancers and reverse proxies

### Q: What makes this script different from using Certbot directly?
**A:** This script provides:
- Cross-platform compatibility (Linux, BSD, macOS)
- Interactive setup and configuration wizards
- Comprehensive error handling and recovery
- Automatic backup and restore capabilities
- System integrity checking
- Advanced logging and monitoring
- Production-ready automation features

## 📋 Requirements & Compatibility

### Q: What operating systems are supported?
**A:** Fully supported:
- **Linux**: Debian, Ubuntu, RHEL, CentOS, Fedora, SUSE, Arch, Alpine, Gentoo
- **BSD**: FreeBSD, OpenBSD, NetBSD, DragonFlyBSD
- **macOS**: Limited support via Homebrew

### Q: What's the minimum bash version required?
**A:** Bash 3.2+ is supported, making it compatible with older systems including macOS.

### Q: Do I need root privileges?
**A:** Root privileges are required for:
- Certificate generation and renewal
- System configuration changes
- Installing dependencies
- Managing services

No root required for:
- Viewing help and version information
- Checking system status
- Running integrity checks
- Viewing current configuration

### Q: What network requirements are there?
**A:** You need:
- A public IP address (IPv4 or IPv6) - private IPs are not supported
- Port 80 accessible from the internet for HTTP-01 validation
- Outbound internet connectivity for ACME server communication
- DNS resolution working properly

## 🔐 Certificates & Security

### Q: Why are IP certificates only valid for 6 days?
**A:** Let's Encrypt uses short-lived certificates for IP addresses to enhance security by:
- Limiting exposure window if private keys are compromised
- Encouraging automation and proper certificate management
- Aligning with modern security best practices
- Reducing the impact of certificate-related security incidents

### Q: How often do I need to renew IP certificates?
**A:** Due to the 6-day validity period, the script automatically attempts renewal every 4 hours. This aggressive schedule ensures certificates never expire.

### Q: Can I use private IP addresses like 192.168.1.1?
**A:** No, Let's Encrypt only issues certificates for publicly routable IP addresses. Private IP ranges are automatically detected and rejected:
- IPv4: 10.x.x.x, 172.16-31.x.x, 192.168.x.x, 127.x.x.x
- IPv6: fc00::/7, fe80::/10, ::1

### Q: Are IP certificates available in production?
**A:** Currently, IP certificates are only available in Let's Encrypt's staging environment. Production availability is expected later in 2025.

### Q: How do I test if my certificate is working?
**A:** Use these commands:
```bash
# Check certificate details
openssl x509 -in /etc/letsencrypt/live/YOUR_IP/cert.pem -text -noout

# Test HTTPS connectivity
curl -I https://YOUR_IP

# Verify certificate chain
openssl verify -CAfile /etc/letsencrypt/live/YOUR_IP/chain.pem /etc/letsencrypt/live/YOUR_IP/cert.pem
```

## ⚙️ Installation & Setup

### Q: How do I install the script?
**A:** The easiest method:
```bash
git clone https://github.com/yourusername/letsencrypt-ip-manager.git
cd letsencrypt-ip-manager
chmod +x letsencrypt-ip-ssl-manager.sh
sudo ./letsencrypt-ip-ssl-manager.sh --setup
```

### Q: What if the automatic installation fails?
**A:** Try these steps:
1. Check the [Troubleshooting Guide](TROUBLESHOOTING.md)
2. Run with debug mode: `sudo ./letsencrypt-ip-ssl-manager.sh --debug --install`
3. Check system compatibility: `./letsencrypt-ip-ssl-manager.sh --status`
4. Install dependencies manually following the [Installation Guide](INSTALLATION.md)

### Q: Can I use this script in Docker containers?
**A:** Yes, see the [Container Deployment](DEPLOYMENT.md#-container-deployment) section for complete examples including:
- Dockerfile configurations
- Docker Compose setups
- Volume mounting for certificates
- Automated renewal in containers

### Q: How do I update to the latest version?
**A:** Follow these steps:
```bash
# Backup current configuration
sudo ./letsencrypt-ip-ssl-manager.sh --backup

# Update code
git pull origin main

# Verify installation
sudo ./letsencrypt-ip-ssl-manager.sh --integrity-check

# Update configuration if needed
sudo ./letsencrypt-ip-ssl-manager.sh --configure
```

## 🔧 Configuration & Usage

### Q: Where are configuration files stored?
**A:** Key file locations:
- **Configuration**: `/etc/letsencrypt-ip-manager/config.conf`
- **Certificates**: `/etc/letsencrypt/live/YOUR_IP/`
- **Logs**: `/var/log/letsencrypt-ip-manager/`
- **Backups**: `/etc/letsencrypt-ip-manager/backup/`

### Q: How do I change my email address?
**A:** Use the interactive configuration:
```bash
sudo ./letsencrypt-ip-ssl-manager.sh --configure
```
Or edit the configuration file directly:
```bash
sudo nano /etc/letsencrypt-ip-manager/config.conf
```

### Q: Can I customize the webroot path?
**A:** Yes, in several ways:
```bash
# Command line
sudo ./letsencrypt-ip-ssl-manager.sh -i IP -e EMAIL -w /custom/path

# Configuration file
echo 'USER_WEBROOT="/custom/path"' | sudo tee -a /etc/letsencrypt-ip-manager/config.conf

# Interactive configuration
sudo ./letsencrypt-ip-ssl-manager.sh --configure
```

### Q: How do I enable debug logging?
**A:** Enable debug mode:
```bash
# Method 1: Command line flag
sudo ./letsencrypt-ip-ssl-manager.sh --debug [command]

# Method 2: Environment variable
sudo DEBUG=true ./letsencrypt-ip-ssl-manager.sh [command]

# Method 3: Configuration file
echo 'LOG_LEVEL="DEBUG"' | sudo tee -a /etc/letsencrypt-ip-manager/config.conf
```

## 🔄 Renewal & Automation

### Q: How do I set up automatic renewal?
**A:** Use the setup command:
```bash
sudo ./letsencrypt-ip-ssl-manager.sh --setup-renewal
```
This creates both SystemD timers and cron jobs for redundancy.

### Q: How can I check if automatic renewal is working?
**A:** Check renewal status:
```bash
# SystemD timer status
sudo systemctl status certbot-ip-renew.timer

# Cron job status
sudo crontab -l | grep certbot

# Check recent renewal attempts
sudo tail -f /var/log/letsencrypt-ip-manager/renewal.log

# Manual renewal test
sudo ./letsencrypt-ip-ssl-manager.sh --renew
```

### Q: What happens if renewal fails?
**A:** The script has multiple fallback mechanisms:
1. **Retry Logic**: Automatic retries with exponential backoff
2. **Multiple Schedulers**: Both SystemD and cron for redundancy
3. **Error Recovery**: Automatic backup restoration on failure
4. **Notifications**: Email alerts for persistent failures
5. **Emergency Mode**: Manual recovery procedures available

### Q: Can I integrate with my existing monitoring system?
**A:** Yes, the script provides several integration points:
```bash
# Exit codes for monitoring
./letsencrypt-ip-ssl-manager.sh --status
echo $?  # 0 = success, >0 = issues found

# Prometheus metrics export
./letsencrypt-ip-ssl-manager.sh --status | grep -E "(Certificate|Status|Error)"

# JSON output for APIs
./letsencrypt-ip-ssl-manager.sh --status --format=json  # Custom format
```

## 🛡️ Security & Best Practices

### Q: Is this script secure for production use?
**A:** Yes, the script implements multiple security measures:
- Input validation and sanitization
- Secure file permissions
- Privilege separation
- Audit logging
- Command injection prevention
- Comprehensive error handling

### Q: How should I secure my email account?
**A:** Follow these practices:
- Use a dedicated email account for SSL certificates
- Enable two-factor authentication
- Use strong, unique passwords
- Monitor for unusual activity
- Set up email forwarding to your security team

### Q: What are the recommended firewall settings?
**A:** Minimal required ports:
```bash
sudo ufw allow 22/tcp   # SSH
sudo ufw allow 80/tcp   # HTTP (required for ACME challenges)
sudo ufw allow 443/tcp  # HTTPS
sudo ufw enable
```

### Q: How do I backup and restore certificates?
**A:** Use the built-in backup system:
```bash
# Create backup
sudo ./letsencrypt-ip-ssl-manager.sh --backup

# List available backups
sudo ./letsencrypt-ip-ssl-manager.sh --restore

# Emergency recovery
sudo ./letsencrypt-ip-ssl-manager.sh --emergency
```

## 🚨 Troubleshooting

### Q: The script says "Port 80 is not accessible" - what do I do?
**A:** Check these common issues:
```bash
# Check if port 80 is open in firewall
sudo ufw status | grep 80
sudo iptables -L | grep 80

# Check if another service is using port 80
sudo netstat -tlnp | grep :80
sudo lsof -i :80

# Test external connectivity
curl -I http://YOUR_IP/.well-known/acme-challenge/test
```

### Q: I get "This script must be run as root" - why?
**A:** Some commands require root privileges:
- Certificate generation and renewal
- System configuration changes
- Installing dependencies

Use `sudo` for these operations:
```bash
sudo ./letsencrypt-ip-ssl-manager.sh -i IP -e EMAIL
```

### Q: Certificate generation fails with "Rate limit exceeded" - what now?
**A:** Let's Encrypt has rate limits:
- **Staging**: More lenient limits for testing
- **Production**: Stricter limits (currently N/A for IP certs)
- **Per IP**: Limited requests per IP per hour

Solutions:
- Wait for rate limit reset (usually 1 hour)
- Use staging environment for testing
- Avoid frequent forced renewals

### Q: My web server isn't reloading after renewal - how to fix?
**A:** Check deploy hooks:
```bash
# Verify deploy hook exists
ls -la /etc/letsencrypt/renewal-hooks/deploy/

# Test web server configuration
sudo nginx -t                  # Nginx
sudo apache2ctl configtest     # Apache

# Manual web server reload
sudo systemctl reload nginx
sudo systemctl reload apache2
```

### Q: How do I get more detailed error information?
**A:** Enable comprehensive debugging:
```bash
# Run with maximum verbosity
sudo ./letsencrypt-ip-ssl-manager.sh --debug [command]

# Check all log files
sudo tail -50 /var/log/letsencrypt-ip-manager/error.log

# Generate debug report
sudo ./letsencrypt-ip-ssl-manager.sh --status > debug_report.txt
```

## 🔗 Integration & Advanced Usage

### Q: Can I use this with load balancers?
**A:** Yes, see the [Load Balanced Environment](DEPLOYMENT.md#-load-balanced-environment) section for:
- HAProxy configuration
- NGINX load balancing
- SSL termination at load balancer
- ACME challenge handling

### Q: How do I integrate with Kubernetes?
**A:** Check the [Microservices Architecture](DEPLOYMENT.md#-microservices-architecture) section for:
- Kubernetes deployment manifests
- ConfigMap configurations
- Ingress controller setup
- Certificate synchronization

### Q: Can I use this in CI/CD pipelines?
**A:** Yes, the script supports automation:
```bash
# Non-interactive mode
FORCE=true ./letsencrypt-ip-ssl-manager.sh --install

# Programmatic configuration
echo 'USER_EMAIL="ci@example.com"' > /etc/letsencrypt-ip-manager/config.conf

# Exit code checking
./letsencrypt-ip-ssl-manager.sh --status
if [ $? -ne 0 ]; then
    echo "Certificate issues detected"
    exit 1
fi
```

### Q: How do I monitor certificate expiration externally?
**A:** Use Certificate Transparency monitoring:
- **crt.sh**: https://crt.sh/?q=YOUR_IP
- **Censys**: Search for your IP certificates
- **Custom monitoring**: Query CT logs programmatically

Example monitoring script:
```bash
#!/bin/bash
CERT_COUNT=$(curl -s "https://crt.sh/?q=YOUR_IP&output=json" | jq length)
if [ "$CERT_COUNT" -gt 1 ]; then
    echo "Multiple certificates detected for YOUR_IP" | mail -s "Certificate Alert" admin@example.com
fi
```

## 📞 Getting Help

### Q: Where can I get support?
**A:** Support channels:
1. **Documentation**: Check this FAQ and other docs in `/docs/`
2. **GitHub Issues**: Report bugs and request features
3. **Troubleshooting Guide**: [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
4. **Community Forums**: Let's Encrypt community forums

### Q: How do I report a security issue?
**A:** For security-sensitive issues:
- **DO NOT** open public GitHub issues
- Email: security@project.com
- Include: Detailed description and reproduction steps
- Response: We aim to respond within 24 hours

### Q: How can I contribute to the project?
**A:** Contributions welcome:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

### Q: What information should I include in bug reports?
**A:** Include this information:
```bash
# System information
./letsencrypt-ip-ssl-manager.sh --status > bug_report.txt

# Error logs
sudo tail -50 /var/log/letsencrypt-ip-manager/error.log >> bug_report.txt

# Command that failed
echo "Failed command: [your exact command]" >> bug_report.txt

# Expected vs actual behavior
echo "Expected: [what should happen]" >> bug_report.txt
echo "Actual: [what actually happened]" >> bug_report.txt
```

---

*Still have questions? Check the [User Manual](USER_MANUAL.md) or [Troubleshooting Guide](TROUBLESHOOTING.md), or open an issue on GitHub.*