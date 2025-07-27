# API Reference

Complete command-line interface reference for the LetsEncrypt IP SSL Manager.

## 📋 Command Syntax

```bash
./letsencrypt-ip-ssl-manager.sh [OPTIONS] [ARGUMENTS]
```

## 🎯 Core Certificate Operations

### `-i, --ip IP_ADDRESS`
Specify the public IP address for certificate generation.

**Usage:**
```bash
sudo ./letsencrypt-ip-ssl-manager.sh -i 203.0.113.10 -e admin@example.com
sudo ./letsencrypt-ip-ssl-manager.sh --ip 2001:db8::1 -e admin@example.com
```

**Requirements:**
- Must be a public IP address (IPv4 or IPv6)
- Cannot be private/reserved ranges (192.168.x.x, 10.x.x.x, etc.)
- Must be accessible from the internet on port 80

**Validation:**
- IPv4 format validation
- IPv6 format validation  
- Private IP range detection
- Network accessibility check

### `-e, --email EMAIL`
Email address for certificate notifications and account registration.

**Usage:**
```bash
sudo ./letsencrypt-ip-ssl-manager.sh -i 203.0.113.10 -e admin@example.com
sudo ./letsencrypt-ip-ssl-manager.sh -i IP --email user@domain.org
```

**Requirements:**
- Valid email format (user@domain.tld)
- Maximum 254 characters
- Will receive expiration notifications

**Validation:**
- RFC 5322 compliant email validation
- Domain format checking
- Security sanitization

### `-w, --webroot PATH`
Specify custom webroot path for HTTP-01 challenge.

**Usage:**
```bash
sudo ./letsencrypt-ip-ssl-manager.sh -i IP -e EMAIL -w /var/www/html
sudo ./letsencrypt-ip-ssl-manager.sh -i IP -e EMAIL --webroot /custom/path
```

**Default:** `/var/www/html`

**Requirements:**
- Directory must exist and be writable
- Web server must serve files from this location
- Must be accessible via HTTP on port 80

## 🎨 Interactive Setup Commands

### `--setup`
Run interactive setup wizard for new users.

**Usage:**
```bash
sudo ./letsencrypt-ip-ssl-manager.sh --setup
```

**Process:**
1. System detection and compatibility check
2. Dependency installation (if needed)
3. Email configuration
4. Webroot configuration
5. Optional certificate generation
6. Automatic renewal setup
7. System verification

**Requirements:**
- Root privileges required
- Internet connectivity
- Interactive terminal

### `--configure`
Launch interactive configuration wizard.

**Usage:**
```bash
sudo ./letsencrypt-ip-ssl-manager.sh --configure
```

**Configurable Options:**
- Default email address
- Default webroot path
- RSA key size (2048, 3072, 4096)
- Auto-renewal settings
- Notification preferences
- Web server detection
- Logging level

### `--show-config`
Display current configuration (no root required).

**Usage:**
```bash
./letsencrypt-ip-ssl-manager.sh --show-config
```

**Output Includes:**
- User preferences
- Renewal settings
- Logging configuration
- Advanced settings
- File locations

## ⚙️ Management Operations

### `--install`
Install required dependencies automatically.

**Usage:**
```bash
sudo ./letsencrypt-ip-ssl-manager.sh --install
```

**Installs:**
- Certbot 2.0.0+ (via snap or package manager)
- System utilities (curl, openssl, DNS tools)
- Python requirements
- Platform-specific dependencies

**Supported Platforms:**
- All major Linux distributions
- BSD systems (FreeBSD, OpenBSD, NetBSD)
- macOS (via Homebrew)

### `--renew`
Renew existing IP certificates.

**Usage:**
```bash
sudo ./letsencrypt-ip-ssl-manager.sh --renew
```

**Behavior:**
- Only renews certificates nearing expiration
- Respects normal renewal window
- Triggers deploy hooks after renewal
- Logs all activities

### `--force-renew`
Force renewal of all certificates regardless of expiration.

**Usage:**
```bash
sudo ./letsencrypt-ip-ssl-manager.sh --force-renew
```

**Use Cases:**
- Testing renewal process
- Recovering from failed renewals
- Updating certificate parameters

**Warning:** May hit Let's Encrypt rate limits if used frequently.

### `--setup-renewal`
Configure automatic certificate renewal.

**Usage:**
```bash
sudo ./letsencrypt-ip-ssl-manager.sh --setup-renewal
```

**Creates:**
- SystemD timer (primary method)
- Cron job (fallback method)
- Deploy hooks for web server reload
- Logging configuration

**Schedule:** Every 4 hours (critical for 6-day certificates)

### `--list`
List all certificates and their status.

**Usage:**
```bash
sudo ./letsencrypt-ip-ssl-manager.sh --list
```

**Output Format:**
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

### `--check-profiles`
Display available ACME profiles.

**Usage:**
```bash
sudo ./letsencrypt-ip-ssl-manager.sh --check-profiles
```

**Output:**
- Available profiles from Let's Encrypt
- Profile requirements and features
- Compatibility information

## ℹ️ Information & Diagnostics

### `-h, --help`
Show comprehensive help message.

**Usage:**
```bash
./letsencrypt-ip-ssl-manager.sh --help
./letsencrypt-ip-ssl-manager.sh -h
```

**No root required**

### `-v, --version`
Display version information.

**Usage:**
```bash
./letsencrypt-ip-ssl-manager.sh --version
./letsencrypt-ip-ssl-manager.sh -v
```

**Output:**
- Script version
- Feature summary
- Usage instructions

**No root required**

### `--status`
Generate comprehensive system status report.

**Usage:**
```bash
./letsencrypt-ip-ssl-manager.sh --status
```

**Report Includes:**
- Script information (version, PID, user)
- System information (OS, architecture, init system)
- Dependencies status (versions, availability)
- Configuration status
- Certificate information
- Network connectivity tests
- Log file status
- Backup information

**No root required**

### `--integrity-check`
Perform system integrity verification.

**Usage:**
```bash
./letsencrypt-ip-ssl-manager.sh --integrity-check
```

**Checks:**
- Configuration file validity
- Log directory permissions
- Required dependencies
- Certificate file integrity
- Web server configuration
- Network connectivity

**Exit Codes:**
- `0`: All checks passed
- `1-99`: Number of issues found

**No root required**

### `--debug`
Enable debug logging for troubleshooting.

**Usage:**
```bash
sudo ./letsencrypt-ip-ssl-manager.sh --debug [command]
sudo DEBUG=true ./letsencrypt-ip-ssl-manager.sh [command]
```

**Debug Output:**
- Verbose command execution
- Function call tracing
- Variable state information
- Detailed error messages

## 🛠️ Maintenance & Recovery

### `--backup`
Create manual backup of configuration and certificates.

**Usage:**
```bash
sudo ./letsencrypt-ip-ssl-manager.sh --backup
```

**Backup Includes:**
- Configuration files
- Certificate data
- Log files
- System settings

**Location:** `/etc/letsencrypt-ip-manager/backup/`

**Retention:** Automatic rotation (default: 10 backups)

### `--restore`
Interactive restore from backup.

**Usage:**
```bash
sudo ./letsencrypt-ip-ssl-manager.sh --restore
```

**Process:**
1. List available backups
2. Select backup type (config/certificates)
3. Confirm restoration
4. Verify integrity after restore

**Backup Types:**
- `config`: Configuration files only
- `cert`: Certificate data only

### `--emergency`
Emergency recovery mode with guided restoration.

**Usage:**
```bash
sudo ./letsencrypt-ip-ssl-manager.sh --emergency
```

**Emergency Actions:**
- System state analysis
- Automatic backup creation
- Configuration recovery options
- Certificate recovery procedures
- Guided troubleshooting steps

**Use When:**
- System is severely broken
- Configuration is corrupted
- Certificates are missing
- Normal operations fail

## 🔧 Exit Codes

| Code | Meaning | Description |
|------|---------|-------------|
| `0` | Success | Command completed successfully |
| `1` | General Error | Generic error condition |
| `2` | Invalid Arguments | Command line arguments invalid |
| `3` | Permission Error | Insufficient privileges |
| `4` | Network Error | Network connectivity issues |
| `5` | Certificate Error | Certificate-related errors |
| `6` | Configuration Error | Configuration file issues |
| `7` | Dependency Error | Missing or invalid dependencies |
| `8` | System Error | System-level errors |
| `9` | Lock Error | Another instance running |
| `10-99` | Specific Errors | Context-specific error codes |

## 🌐 Environment Variables

### Configuration Override

| Variable | Description | Default |
|----------|-------------|---------|
| `DEBUG` | Enable debug logging | `false` |
| `LOG_LEVEL` | Set log level | `INFO` |
| `CONFIG_FILE` | Custom config file path | `/etc/letsencrypt-ip-manager/config.conf` |
| `LOG_DIR` | Custom log directory | `/var/log/letsencrypt-ip-manager` |

**Usage:**
```bash
export DEBUG=true
export LOG_LEVEL=DEBUG
sudo ./letsencrypt-ip-ssl-manager.sh [command]
```

### Runtime Behavior

| Variable | Description | Effect |
|----------|-------------|--------|
| `STAGING` | Use staging environment | Forces staging ACME server |
| `FORCE` | Skip confirmations | Bypasses interactive prompts |
| `QUIET` | Suppress output | Minimal console output |

## 📝 Configuration File Format

**Location:** `/etc/letsencrypt-ip-manager/config.conf`

**Format:** Shell variable format

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

# Backup information (auto-generated)
LAST_BACKUP="2025-01-29 10:30:45"
CONFIG_VERSION="3.0.0"
```

## 📊 Log Files

| Log File | Purpose | Location |
|----------|---------|----------|
| **ip-certificate.log** | General operations | `/var/log/letsencrypt-ip-manager/` |
| **error.log** | Errors and warnings | `/var/log/letsencrypt-ip-manager/` |
| **audit.log** | Security and config changes | `/var/log/letsencrypt-ip-manager/` |
| **renewal.log** | Automatic renewal events | `/var/log/letsencrypt-ip-manager/` |

**Log Format:**
```
[TIMESTAMP] [LEVEL] [PID] MESSAGE
[2025-01-29 10:30:45] [INFO] [12345] Certificate obtained successfully for 203.0.113.10
```

## 🔐 File Permissions

### Configuration Files
```bash
/etc/letsencrypt-ip-manager/           # 750 root:root
/etc/letsencrypt-ip-manager/config.conf  # 640 root:root
```

### Log Files
```bash
/var/log/letsencrypt-ip-manager/       # 750 root:root
/var/log/letsencrypt-ip-manager/*.log  # 640 root:root
```

### Certificate Files
```bash
/etc/letsencrypt/live/YOUR_IP/         # 755 root:root
/etc/letsencrypt/live/YOUR_IP/privkey.pem  # 600 root:root
/etc/letsencrypt/live/YOUR_IP/*.pem    # 644 root:root
```

## 🔗 Integration Examples

### Cron Integration
```bash
# Add to root crontab
0 */4 * * * /path/to/letsencrypt-ip-ssl-manager.sh --renew >/dev/null 2>&1
```

### SystemD Integration
```bash
# Check timer status
sudo systemctl status certbot-ip-renew.timer

# Manual timer control
sudo systemctl start certbot-ip-renew.timer
sudo systemctl stop certbot-ip-renew.timer
```

### Monitoring Integration
```bash
# Check status for monitoring
./letsencrypt-ip-ssl-manager.sh --status
echo $?  # Exit code for monitoring

# Log monitoring
tail -f /var/log/letsencrypt-ip-manager/error.log | grep ERROR
```

### Web Server Integration
```bash
# Deploy hook for Nginx
echo 'systemctl reload nginx' > /etc/letsencrypt/renewal-hooks/deploy/nginx-reload
chmod +x /etc/letsencrypt/renewal-hooks/deploy/nginx-reload
```

---

*For usage examples and workflows, see the [User Manual](USER_MANUAL.md).*