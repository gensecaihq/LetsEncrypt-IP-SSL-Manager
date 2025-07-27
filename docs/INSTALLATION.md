# Installation Guide

Complete installation instructions for the LetsEncrypt IP SSL Manager across all supported platforms.

## 📋 Prerequisites

### System Requirements

| Platform | Distributions | Status |
|----------|---------------|--------|
| **Linux** | Debian, Ubuntu, Mint, Kali | ✅ Fully Supported |
| **Linux** | RHEL, CentOS, Fedora, Rocky, Alma | ✅ Fully Supported |
| **Linux** | SUSE, openSUSE | ✅ Fully Supported |
| **Linux** | Arch, Manjaro | ✅ Fully Supported |
| **Linux** | Alpine | ✅ Fully Supported |
| **Linux** | Gentoo | ✅ Fully Supported |
| **BSD** | FreeBSD, OpenBSD, NetBSD, DragonFlyBSD | ✅ Fully Supported |
| **macOS** | All versions with Homebrew | ⚠️ Limited Support |

### Hardware Requirements
- **CPU**: Any x86_64 or ARM64 processor
- **RAM**: Minimum 512MB (1GB+ recommended)
- **Storage**: 100MB free space for installation
- **Network**: Internet connection for certificate validation

### Network Requirements
- **Public IP**: IPv4 or IPv6 public address (not behind NAT)
- **Port 80**: Must be accessible from the internet for HTTP-01 challenge
- **DNS**: Working DNS resolution
- **Firewall**: Configure to allow incoming connections on port 80

## 🚀 Quick Installation

### Method 1: Automated Setup (Recommended)

```bash
# Download and setup
git clone https://github.com/yourusername/letsencrypt-ip-manager.git
cd letsencrypt-ip-manager
chmod +x letsencrypt-ip-ssl-manager.sh

# One-command setup (handles everything)
sudo ./letsencrypt-ip-ssl-manager.sh --setup
```

This will:
- ✅ Detect your operating system
- ✅ Install all required dependencies
- ✅ Configure the environment
- ✅ Set up automatic renewal
- ✅ Create initial configuration

### Method 2: Step-by-Step Installation

```bash
# 1. Clone repository
git clone https://github.com/yourusername/letsencrypt-ip-manager.git
cd letsencrypt-ip-manager

# 2. Make executable
chmod +x letsencrypt-ip-ssl-manager.sh

# 3. Install dependencies
sudo ./letsencrypt-ip-ssl-manager.sh --install

# 4. Configure settings
sudo ./letsencrypt-ip-ssl-manager.sh --configure

# 5. Verify installation
sudo ./letsencrypt-ip-ssl-manager.sh --status
```

## 🐧 Platform-Specific Installation

### Debian/Ubuntu/Mint

```bash
# Update package lists
sudo apt update

# Install dependencies (if not using auto-installer)
sudo apt install -y curl openssl dnsutils python3 snapd

# Install Certbot via snap (recommended)
sudo snap install --classic certbot
sudo ln -sf /snap/bin/certbot /usr/bin/certbot

# Clone and setup
git clone https://github.com/yourusername/letsencrypt-ip-manager.git
cd letsencrypt-ip-manager
chmod +x letsencrypt-ip-ssl-manager.sh

# Run automated setup
sudo ./letsencrypt-ip-ssl-manager.sh --setup
```

### RHEL/CentOS/Fedora

```bash
# Enable EPEL (RHEL/CentOS only)
sudo yum install -y epel-release  # CentOS 7
sudo dnf install -y epel-release  # CentOS 8+/Fedora

# Install dependencies
sudo yum install -y curl openssl bind-utils python3 snapd  # RHEL/CentOS 7
sudo dnf install -y curl openssl bind-utils python3 snapd  # CentOS 8+/Fedora

# Enable snapd
sudo systemctl enable --now snapd.socket
sudo ln -sf /var/lib/snapd/snap /snap

# Install Certbot
sudo snap install --classic certbot
sudo ln -sf /snap/bin/certbot /usr/bin/certbot

# Setup script
git clone https://github.com/yourusername/letsencrypt-ip-manager.git
cd letsencrypt-ip-manager
chmod +x letsencrypt-ip-ssl-manager.sh
sudo ./letsencrypt-ip-ssl-manager.sh --setup
```

### SUSE/openSUSE

```bash
# Install dependencies
sudo zypper install -y curl openssl bind-utils python3 snapd

# Enable snapd
sudo systemctl enable --now snapd
sudo systemctl enable --now snapd.apparmor

# Install Certbot
sudo snap install --classic certbot
sudo ln -sf /snap/bin/certbot /usr/bin/certbot

# Setup script
git clone https://github.com/yourusername/letsencrypt-ip-manager.git
cd letsencrypt-ip-manager
chmod +x letsencrypt-ip-ssl-manager.sh
sudo ./letsencrypt-ip-ssl-manager.sh --setup
```

### Arch Linux

```bash
# Install dependencies
sudo pacman -Sy curl openssl bind python python-pip certbot

# Setup script
git clone https://github.com/yourusername/letsencrypt-ip-manager.git
cd letsencrypt-ip-manager
chmod +x letsencrypt-ip-ssl-manager.sh
sudo ./letsencrypt-ip-ssl-manager.sh --setup
```

### Alpine Linux

```bash
# Install dependencies
sudo apk add --no-cache curl openssl bind-tools python3 py3-pip certbot

# Setup script
git clone https://github.com/yourusername/letsencrypt-ip-manager.git
cd letsencrypt-ip-manager
chmod +x letsencrypt-ip-ssl-manager.sh
sudo ./letsencrypt-ip-ssl-manager.sh --setup
```

### FreeBSD

```bash
# Install dependencies
sudo pkg install -y curl openssl bind-tools python3 py39-certbot

# Setup script
git clone https://github.com/yourusername/letsencrypt-ip-manager.git
cd letsencrypt-ip-manager
chmod +x letsencrypt-ip-ssl-manager.sh
sudo ./letsencrypt-ip-ssl-manager.sh --setup
```

### macOS (Limited Support)

```bash
# Install Homebrew (if not already installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install dependencies
brew install curl openssl bind python3 certbot

# Setup script
git clone https://github.com/yourusername/letsencrypt-ip-manager.git
cd letsencrypt-ip-manager
chmod +x letsencrypt-ip-ssl-manager.sh
./letsencrypt-ip-ssl-manager.sh --setup  # Note: No sudo on macOS
```

## 🔧 Manual Installation

If you prefer manual installation or the automated installer fails:

### Step 1: Install Certbot

Choose one method based on your preference:

#### Option A: Via Snap (Recommended)
```bash
sudo snap install --classic certbot
sudo ln -sf /snap/bin/certbot /usr/bin/certbot
```

#### Option B: Via Package Manager
```bash
# Debian/Ubuntu
sudo apt install -y certbot

# RHEL/CentOS/Fedora
sudo yum install -y certbot  # or dnf

# Arch Linux
sudo pacman -S certbot

# Alpine
sudo apk add certbot

# FreeBSD
sudo pkg install py39-certbot
```

#### Option C: Via Pip
```bash
pip3 install certbot
```

### Step 2: Verify Certbot Version

```bash
certbot --version
# Should show 2.0.0 or higher for IP certificate support
```

### Step 3: Install System Dependencies

```bash
# Install required utilities
sudo apt install -y curl openssl dnsutils python3  # Debian/Ubuntu
sudo yum install -y curl openssl bind-utils python3  # RHEL/CentOS
sudo zypper install -y curl openssl bind-utils python3  # SUSE
sudo pacman -S curl openssl bind python3  # Arch
sudo apk add curl openssl bind-tools python3  # Alpine
sudo pkg install curl openssl bind-tools python3  # FreeBSD
```

### Step 4: Download and Setup Script

```bash
# Download
git clone https://github.com/yourusername/letsencrypt-ip-manager.git
cd letsencrypt-ip-manager

# Make executable
chmod +x letsencrypt-ip-ssl-manager.sh

# Create required directories
sudo mkdir -p /etc/letsencrypt-ip-manager
sudo mkdir -p /var/log/letsencrypt-ip-manager

# Set permissions
sudo chmod 750 /etc/letsencrypt-ip-manager
sudo chmod 750 /var/log/letsencrypt-ip-manager
```

## ✅ Verification

After installation, verify everything is working:

### 1. Check Script Syntax
```bash
bash -n ./letsencrypt-ip-ssl-manager.sh
echo "Script syntax: $([[ $? -eq 0 ]] && echo "✅ Valid" || echo "❌ Invalid")"
```

### 2. Test Basic Commands
```bash
# Help command
./letsencrypt-ip-ssl-manager.sh --help

# Version information
./letsencrypt-ip-ssl-manager.sh --version

# System status
./letsencrypt-ip-ssl-manager.sh --status
```

### 3. Verify Dependencies
```bash
# Run integrity check
sudo ./letsencrypt-ip-ssl-manager.sh --integrity-check
```

### 4. Check Configuration
```bash
# View current configuration
./letsencrypt-ip-ssl-manager.sh --show-config
```

## 🔧 Configuration

After installation, you may want to customize settings:

### Interactive Configuration
```bash
sudo ./letsencrypt-ip-ssl-manager.sh --configure
```

### Manual Configuration
Edit the configuration file:
```bash
sudo nano /etc/letsencrypt-ip-manager/config.conf
```

Key settings:
- `USER_EMAIL`: Default email for certificates
- `USER_WEBROOT`: Default webroot path
- `AUTO_RENEWAL_ENABLED`: Enable automatic renewal
- `LOG_LEVEL`: Logging verbosity (DEBUG, INFO, WARN, ERROR)

## 🚨 Troubleshooting Installation

### Common Issues

#### 1. Permission Denied
```bash
# Fix: Add execute permission
chmod +x letsencrypt-ip-ssl-manager.sh
```

#### 2. Certbot Not Found
```bash
# Check if certbot is installed
which certbot
certbot --version

# If not found, install via snap
sudo snap install --classic certbot
sudo ln -sf /snap/bin/certbot /usr/bin/certbot
```

#### 3. Directory Creation Failed
```bash
# Manually create directories
sudo mkdir -p /etc/letsencrypt-ip-manager
sudo mkdir -p /var/log/letsencrypt-ip-manager
sudo chmod 750 /etc/letsencrypt-ip-manager
sudo chmod 750 /var/log/letsencrypt-ip-manager
```

#### 4. Snap Not Available
```bash
# Install certbot via pip as fallback
pip3 install --user certbot
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

#### 5. Network Issues
```bash
# Test connectivity
curl -I https://acme-staging-v02.api.letsencrypt.org/directory

# Check DNS resolution
nslookup letsencrypt.org
```

### Getting Help

If you encounter issues:

1. Check the [Troubleshooting Guide](TROUBLESHOOTING.md)
2. Run with debug mode: `sudo ./letsencrypt-ip-ssl-manager.sh --debug --status`
3. Check logs: `sudo tail -f /var/log/letsencrypt-ip-manager/error.log`
4. Open an issue on GitHub with:
   - Operating system and version
   - Complete error messages
   - Output of `--status` command

## 🔄 Updates

To update to the latest version:

```bash
# Backup current configuration
sudo ./letsencrypt-ip-ssl-manager.sh --backup

# Pull latest changes
git pull origin main

# Run integrity check
sudo ./letsencrypt-ip-ssl-manager.sh --integrity-check

# Update configuration if needed
sudo ./letsencrypt-ip-ssl-manager.sh --configure
```

## 🗑️ Uninstallation

To completely remove the script:

```bash
# Backup certificates (optional)
sudo ./letsencrypt-ip-ssl-manager.sh --backup

# Remove automatic renewal
sudo crontab -l | grep -v letsencrypt-ip | sudo crontab -
sudo systemctl disable certbot-ip-renew.timer 2>/dev/null || true
sudo rm -f /etc/systemd/system/certbot-ip-renew.* 2>/dev/null || true

# Remove configuration and logs
sudo rm -rf /etc/letsencrypt-ip-manager
sudo rm -rf /var/log/letsencrypt-ip-manager

# Remove script directory
rm -rf /path/to/letsencrypt-ip-manager
```

---

*Installation complete! Next: Read the [User Manual](USER_MANUAL.md) to get started.*