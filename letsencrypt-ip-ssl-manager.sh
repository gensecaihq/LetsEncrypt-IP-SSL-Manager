#!/bin/bash
#
# Let's Encrypt IP Address Certificate Management Script
# 
# Description:
#   Production-grade script specifically for managing Let's Encrypt SSL certificates 
#   for IP addresses. As of July 2025, IP certificates are only available in the 
#   staging environment and require the 'shortlived' profile (6-day validity).
#
# Features:
#   - IPv4 and IPv6 address support
#   - Automatic OS detection (Debian/Ubuntu and RHEL/CentOS/Fedora)
#   - Mandatory shortlived profile enforcement
#   - Automatic renewal configuration (critical for 6-day certs)
#   - Comprehensive error handling and logging
#   - Security validations for IP addresses
#
# Requirements:
#   - Root/sudo access
#   - Public IP address (not private/local)
#   - Port 80 accessible for HTTP-01 challenge
#   - Valid email address for notifications
#   - Certbot with ACME profile support
#
# Author: System Administrator
# Version: 3.0.0
# Last Updated: July 2025
#
# License: MIT
#

# Exit on any error, undefined variable, or pipe failure
set -euo pipefail

# Enable debug mode if DEBUG environment variable is set
[[ "${DEBUG:-}" == "true" ]] && set -x

# ============================================================================
# GLOBAL CONFIGURATION
# ============================================================================

# Script metadata
readonly SCRIPT_VERSION="3.0.0"
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Logging configuration
readonly LOG_DIR="/var/log/letsencrypt-ip-manager"
readonly LOG_FILE="${LOG_DIR}/ip-certificate.log"
readonly ERROR_LOG="${LOG_DIR}/error.log"
readonly AUDIT_LOG="${LOG_DIR}/audit.log"
readonly RENEWAL_LOG="${LOG_DIR}/renewal.log"

# Certificate paths
readonly CERT_BASE_PATH="/etc/letsencrypt"
readonly CERT_LIVE_PATH="${CERT_BASE_PATH}/live"

# Default configuration values
readonly DEFAULT_WEBROOT="/var/www/html"
readonly DEFAULT_KEY_SIZE="4096"

# ACME configuration - IP certs only work in staging for now
readonly STAGING_ACME_URL="https://acme-staging-v02.api.letsencrypt.org/directory"
readonly REQUIRED_PROFILE="shortlived"  # Mandatory for IP certificates
readonly CERT_VALIDITY_DAYS=6          # Short-lived certificates

# Renewal configuration - aggressive schedule for 6-day certs
readonly RENEWAL_INTERVAL="0 */4 * * *"  # Every 4 hours
readonly RENEWAL_DEPLOY_HOOK="systemctl reload nginx 2>/dev/null || systemctl reload apache2 2>/dev/null || systemctl reload httpd 2>/dev/null || true"

# Lock file to prevent concurrent executions
readonly LOCK_FILE="/var/run/letsencrypt-ip-manager.lock"
readonly LOCK_TIMEOUT=300  # 5 minutes

# Certbot requirements
readonly CERTBOT_MIN_VERSION="2.0.0"

# ============================================================================
# TERMINAL COLORS AND FORMATTING
# ============================================================================

# Color codes for terminal output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color

# Unicode symbols for better UX
readonly CHECKMARK="✓"
readonly CROSS="✗"
readonly ARROW="→"
readonly WARNING="⚠"
readonly INFO="ℹ"

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Function: Initialize logging system
init_logging() {
    # Create log directory if it doesn't exist
    if [[ ! -d "$LOG_DIR" ]]; then
        mkdir -p "$LOG_DIR"
        chmod 750 "$LOG_DIR"
    fi
    
    # Create log files
    touch "$LOG_FILE" "$ERROR_LOG" "$AUDIT_LOG" "$RENEWAL_LOG"
    chmod 640 "$LOG_FILE" "$ERROR_LOG" "$AUDIT_LOG" "$RENEWAL_LOG"
    
    # Rotate logs if they're too large (>50MB for more frequent rotation)
    for log in "$LOG_FILE" "$ERROR_LOG" "$AUDIT_LOG" "$RENEWAL_LOG"; do
        if [[ -f "$log" ]] && [[ $(stat -f%z "$log" 2>/dev/null || stat -c%s "$log" 2>/dev/null) -gt 52428800 ]]; then
            mv "$log" "${log}.$(date +%Y%m%d_%H%M%S)"
            touch "$log"
            chmod 640 "$log"
        fi
    done
}

# Function: Enhanced logging with levels
log() {
    local level="${1:-INFO}"
    local message="${2:-}"
    local print_stdout="${3:-true}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_entry="[${timestamp}] [${level}] ${message}"
    
    # Write to appropriate log file
    case "$level" in
        ERROR)
            echo "$log_entry" >> "$ERROR_LOG"
            echo "$log_entry" >> "$LOG_FILE"
            [[ "$print_stdout" == "true" ]] && echo -e "${RED}${CROSS} ${message}${NC}" >&2
            ;;
        WARN)
            echo "$log_entry" >> "$LOG_FILE"
            [[ "$print_stdout" == "true" ]] && echo -e "${YELLOW}${WARNING} ${message}${NC}"
            ;;
        AUDIT)
            echo "$log_entry" >> "$AUDIT_LOG"
            echo "$log_entry" >> "$LOG_FILE"
            [[ "$print_stdout" == "true" ]] && echo -e "${CYAN}${INFO} ${message}${NC}"
            ;;
        DEBUG)
            [[ "${DEBUG:-}" == "true" ]] && echo "$log_entry" >> "$LOG_FILE"
            [[ "${DEBUG:-}" == "true" ]] && [[ "$print_stdout" == "true" ]] && echo -e "${MAGENTA}[DEBUG] ${message}${NC}"
            ;;
        *)
            echo "$log_entry" >> "$LOG_FILE"
            [[ "$print_stdout" == "true" ]] && echo -e "${GREEN}${CHECKMARK} ${message}${NC}"
            ;;
    esac
}

# Function: Acquire exclusive lock
acquire_lock() {
    local timeout="${1:-$LOCK_TIMEOUT}"
    local elapsed=0
    
    while [[ $elapsed -lt $timeout ]]; do
        if (set -C; echo $$ > "$LOCK_FILE") 2>/dev/null; then
            log "DEBUG" "Lock acquired (PID: $$)"
            return 0
        fi
        
        # Check if the process holding the lock is still running
        local lock_pid=$(cat "$LOCK_FILE" 2>/dev/null)
        if [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
            log "WARN" "Removing stale lock file (PID: $lock_pid)"
            rm -f "$LOCK_FILE"
            continue
        fi
        
        if [[ $elapsed -eq 0 ]]; then
            log "WARN" "Another instance is running (PID: $lock_pid). Waiting..."
        fi
        
        sleep 5
        elapsed=$((elapsed + 5))
    done
    
    log "ERROR" "Failed to acquire lock after ${timeout} seconds"
    return 1
}

# Function: Release lock
release_lock() {
    if [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$$" ]]; then
        rm -f "$LOCK_FILE"
        log "DEBUG" "Lock released (PID: $$)"
    fi
}

# Function: Cleanup on exit
cleanup() {
    local exit_code=$?
    release_lock
    
    if [[ $exit_code -ne 0 ]]; then
        log "ERROR" "Script exited with error code: $exit_code" "false"
    fi
    
    exit $exit_code
}

# Set trap for cleanup
trap cleanup EXIT INT TERM

# Function: Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "This script must be run as root or with sudo privileges"
        exit 1
    fi
}

# Function: Validate email address
validate_email() {
    local email="$1"
    local email_regex="^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"
    
    if [[ ! "$email" =~ $email_regex ]]; then
        log "ERROR" "Invalid email address: $email"
        return 1
    fi
    
    return 0
}

# ============================================================================
# OS DETECTION AND PACKAGE MANAGEMENT
# ============================================================================

# Function: Detect operating system
detect_os() {
    local os=""
    local version=""
    local distro_family=""
    local pkg_manager=""
    
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        os="$NAME"
        version="$VERSION_ID"
    elif command -v lsb_release >/dev/null 2>&1; then
        os=$(lsb_release -si)
        version=$(lsb_release -sr)
    elif [[ -f /etc/debian_version ]]; then
        os="Debian"
        version=$(cat /etc/debian_version)
    elif [[ -f /etc/redhat-release ]]; then
        os="RedHat"
        version=$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release | head -1)
    else
        log "ERROR" "Unable to detect operating system"
        exit 1
    fi
    
    # Determine distribution family and package manager
    case "${os,,}" in
        *ubuntu*|*debian*|*mint*)
            distro_family="debian"
            pkg_manager="apt-get"
            command -v apt >/dev/null 2>&1 && pkg_manager="apt"
            ;;
        *centos*|*rhel*|*red*hat*|*fedora*|*rocky*|*alma*)
            distro_family="redhat"
            pkg_manager="yum"
            command -v dnf >/dev/null 2>&1 && pkg_manager="dnf"
            ;;
        *)
            log "ERROR" "Unsupported operating system: $os"
            exit 1
            ;;
    esac
    
    export OS_NAME="$os"
    export OS_VERSION="$version"
    export DISTRO_FAMILY="$distro_family"
    export PKG_MANAGER="$pkg_manager"
    
    log "INFO" "Detected OS: $OS_NAME $OS_VERSION (Family: $DISTRO_FAMILY)"
}

# Function: Check and install system dependencies
check_dependencies() {
    local deps_missing=false
    local required_commands=("curl" "openssl" "host" "python3")
    
    log "INFO" "Checking system dependencies..."
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log "WARN" "Missing dependency: $cmd"
            deps_missing=true
        fi
    done
    
    if [[ "$deps_missing" == "true" ]]; then
        log "INFO" "Installing missing dependencies..."
        
        case "$DISTRO_FAMILY" in
            debian)
                $PKG_MANAGER update
                $PKG_MANAGER install -y curl openssl dnsutils python3 python3-pip
                ;;
            redhat)
                $PKG_MANAGER install -y curl openssl bind-utils python3 python3-pip
                ;;
        esac
    fi
}

# ============================================================================
# IP ADDRESS VALIDATION
# ============================================================================

# Function: Validate IPv4 address
validate_ipv4() {
    local ip="$1"
    
    # Check format
    if [[ ! "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        return 1
    fi
    
    # Validate each octet
    local IFS='.'
    read -ra octets <<< "$ip"
    for octet in "${octets[@]}"; do
        if ((octet > 255)); then
            return 1
        fi
    done
    
    # Check if it's a private IP
    if [[ "$ip" =~ ^10\. ]] || \
       [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[01])\. ]] || \
       [[ "$ip" =~ ^192\.168\. ]] || \
       [[ "$ip" =~ ^127\. ]] || \
       [[ "$ip" == "0.0.0.0" ]] || \
       [[ "$ip" == "255.255.255.255" ]]; then
        log "WARN" "IP address appears to be private or reserved: $ip"
        log "ERROR" "Let's Encrypt requires publicly routable IP addresses"
        return 1
    fi
    
    return 0
}

# Function: Validate IPv6 address
validate_ipv6() {
    local ip="$1"
    
    # Basic IPv6 validation (simplified but comprehensive)
    if [[ ! "$ip" =~ ^(([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]+|::(ffff(:0{1,4})?:)?((25[0-5]|(2[0-4]|1?[0-9])?[0-9])\.){3}(25[0-5]|(2[0-4]|1?[0-9])?[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1?[0-9])?[0-9])\.){3}(25[0-5]|(2[0-4]|1?[0-9])?[0-9]))$ ]]; then
        return 1
    fi
    
    # Check for private/local IPv6 addresses
    if [[ "$ip" =~ ^fe80: ]] || \
       [[ "$ip" =~ ^fc00: ]] || \
       [[ "$ip" =~ ^fd00: ]] || \
       [[ "$ip" == "::1" ]]; then
        log "WARN" "IPv6 address appears to be private or link-local: $ip"
        log "ERROR" "Let's Encrypt requires publicly routable IP addresses"
        return 1
    fi
    
    return 0
}

# Function: Comprehensive IP validation
validate_ip_address() {
    local ip="$1"
    
    # Try IPv4 first
    if validate_ipv4 "$ip"; then
        log "INFO" "Valid public IPv4 address: $ip"
        return 0
    fi
    
    # Try IPv6
    if validate_ipv6 "$ip"; then
        log "INFO" "Valid public IPv6 address: $ip"
        return 0
    fi
    
    log "ERROR" "Invalid or private IP address: $ip"
    return 1
}

# Function: Check IP accessibility
check_ip_accessibility() {
    local ip="$1"
    
    log "INFO" "Checking IP accessibility..."
    
    # Check if IP responds to ping (not all IPs do, so this is just informational)
    if ping -c 1 -W 2 "$ip" >/dev/null 2>&1; then
        log "INFO" "IP responds to ping"
    else
        log "WARN" "IP does not respond to ping (this may be normal)"
    fi
    
    # Check if port 80 is accessible (required for HTTP-01 challenge)
    if timeout 5 bash -c "echo >/dev/tcp/$ip/80" 2>/dev/null; then
        log "INFO" "Port 80 is accessible"
    else
        log "ERROR" "Port 80 is not accessible on $ip"
        log "ERROR" "HTTP-01 challenge requires port 80 to be open"
        return 1
    fi
    
    return 0
}

# ============================================================================
# CERTBOT MANAGEMENT
# ============================================================================

# Function: Check certbot version
check_certbot_version() {
    if ! command -v certbot >/dev/null 2>&1; then
        log "WARN" "Certbot is not installed"
        return 1
    fi
    
    local version=$(certbot --version 2>&1 | grep -oP 'certbot \K[0-9.]+' || echo "0.0.0")
    log "INFO" "Current certbot version: $version"
    
    # Check for minimum version
    if [[ "$(printf '%s\n' "$CERTBOT_MIN_VERSION" "$version" | sort -V | head -n1)" != "$CERTBOT_MIN_VERSION" ]]; then
        log "ERROR" "Certbot version $version is too old"
        log "ERROR" "Minimum required version: $CERTBOT_MIN_VERSION"
        log "ERROR" "ACME profile support requires Certbot 2.0.0 or higher"
        return 1
    fi
    
    # Check if certbot supports profiles
    if ! certbot --help 2>&1 | grep -q -- --profile; then
        log "ERROR" "Your certbot version doesn't support ACME profiles"
        log "ERROR" "Please upgrade certbot to version 2.0.0 or higher"
        return 1
    fi
    
    return 0
}

# Function: Install certbot
install_certbot() {
    log "INFO" "Installing certbot with ACME profile support..."
    log "AUDIT" "User ${SUDO_USER:-root} initiated certbot installation"
    
    # Remove any existing installations first
    log "INFO" "Removing existing certbot installations..."
    
    case "$DISTRO_FAMILY" in
        debian)
            $PKG_MANAGER remove -y certbot python3-certbot-* 2>/dev/null || true
            ;;
        redhat)
            $PKG_MANAGER remove -y certbot python3-certbot-* 2>/dev/null || true
            ;;
    esac
    
    # Install via snap (recommended for latest version)
    if command -v snap >/dev/null 2>&1; then
        log "INFO" "Installing certbot via snap..."
        
        # Ensure snapd is running
        systemctl enable --now snapd.socket 2>/dev/null || true
        sleep 2
        
        # Install certbot
        if snap install --classic certbot; then
            ln -sf /snap/bin/certbot /usr/bin/certbot 2>/dev/null || true
            log "INFO" "Certbot installed successfully via snap"
        fi
    else
        # Install snapd first
        log "INFO" "Installing snap package manager..."
        
        case "$DISTRO_FAMILY" in
            debian)
                $PKG_MANAGER update
                $PKG_MANAGER install -y snapd
                ;;
            redhat)
                $PKG_MANAGER install -y snapd
                systemctl enable --now snapd.socket
                ;;
        esac
        
        # Wait for snap to be ready
        sleep 5
        
        # Install certbot via snap
        snap install --classic certbot
        ln -sf /snap/bin/certbot /usr/bin/certbot 2>/dev/null || true
    fi
    
    # Verify installation and version
    if command -v certbot >/dev/null 2>&1; then
        if check_certbot_version; then
            log "INFO" "Certbot installation completed successfully"
            log "AUDIT" "Certbot with profile support installed"
        else
            log "ERROR" "Installed certbot version doesn't meet requirements"
            exit 1
        fi
    else
        log "ERROR" "Certbot installation failed"
        exit 1
    fi
}

# ============================================================================
# CERTIFICATE OPERATIONS
# ============================================================================

# Function: Prepare webroot for HTTP-01 challenge
prepare_webroot() {
    local webroot="$1"
    
    log "INFO" "Preparing webroot for HTTP-01 challenge..."
    
    # Create webroot directory structure
    mkdir -p "$webroot"
    mkdir -p "${webroot}/.well-known/acme-challenge"
    
    # Set proper permissions
    chmod 755 "$webroot" "${webroot}/.well-known" "${webroot}/.well-known/acme-challenge"
    
    # Create test file
    local test_token="test-${RANDOM}-$(date +%s)"
    echo "$test_token" > "${webroot}/.well-known/acme-challenge/${test_token}.txt"
    
    log "INFO" "Webroot prepared at: $webroot"
    log "DEBUG" "Test token created: ${test_token}.txt"
    
    # Clean up test file after a delay
    (sleep 10 && rm -f "${webroot}/.well-known/acme-challenge/${test_token}.txt") &
}

# Function: Detect web server
detect_web_server() {
    local web_server=""
    
    if systemctl is-active --quiet nginx 2>/dev/null; then
        web_server="nginx"
        log "INFO" "Detected nginx web server"
    elif systemctl is-active --quiet apache2 2>/dev/null || systemctl is-active --quiet httpd 2>/dev/null; then
        web_server="apache"
        log "INFO" "Detected Apache web server"
    else
        log "WARN" "No active web server detected"
        log "WARN" "Using standalone mode - certbot will start its own web server"
    fi
    
    echo "$web_server"
}

# Function: Check available ACME profiles
check_profiles() {
    log "INFO" "Checking available ACME profiles in staging environment..."
    
    local response=$(curl -s --connect-timeout 10 --max-time 30 "$STAGING_ACME_URL" 2>/dev/null)
    
    if [[ $? -eq 0 ]] && [[ -n "$response" ]]; then
        echo -e "\n${GREEN}Available ACME Profiles:${NC}"
        
        if command -v python3 >/dev/null 2>&1; then
            python3 -c "
import json
import sys
try:
    data = json.loads('''$response''')
    profiles = data.get('meta', {}).get('profiles', {})
    if profiles:
        for key, desc in profiles.items():
            status = '✓ REQUIRED' if key == 'shortlived' else '  '
            print(f'{status} {key}: {desc}')
    else:
        print('No profiles found in response')
except Exception as e:
    print(f'Error parsing response: {e}')
    sys.exit(1)
"
            echo -e "\n${YELLOW}Note: IP certificates require the 'shortlived' profile${NC}"
        else
            echo "$response" | grep -A 10 '"profiles"' || echo "Unable to parse response"
        fi
    else
        log "ERROR" "Failed to query ACME directory"
        return 1
    fi
}

# Function: Obtain IP certificate
obtain_ip_certificate() {
    local ip_address="$1"
    local email="$2"
    local webroot="$3"
    
    log "INFO" "Starting IP certificate request process..."
    log "AUDIT" "Requesting certificate for IP: $ip_address, Email: $email"
    
    # Validate inputs
    if [[ -z "$ip_address" ]] || [[ -z "$email" ]]; then
        log "ERROR" "IP address and email are required"
        return 1
    fi
    
    # Validate email
    if ! validate_email "$email"; then
        return 1
    fi
    
    # Validate IP address
    if ! validate_ip_address "$ip_address"; then
        return 1
    fi
    
    # Check IP accessibility
    if ! check_ip_accessibility "$ip_address"; then
        log "ERROR" "Please ensure port 80 is open and accessible"
        return 1
    fi
    
    # Check certbot version
    if ! check_certbot_version; then
        log "ERROR" "Please install or upgrade certbot first"
        return 1
    fi
    
    # Prepare webroot
    prepare_webroot "$webroot"
    
    # Detect web server
    local web_server=$(detect_web_server)
    
    # Build certbot command
    local certbot_cmd=(certbot certonly)
    
    # Choose plugin based on web server
    if [[ -n "$web_server" ]]; then
        certbot_cmd+=(--"$web_server")
    else
        # Use standalone mode if no web server detected
        certbot_cmd+=(--standalone)
    fi
    
    # Add required parameters for IP certificates
    certbot_cmd+=(
        -d "$ip_address"
        --email "$email"
        --agree-tos
        --non-interactive
        --staging  # IP certs only work in staging for now
        --profile "$REQUIRED_PROFILE"  # Must use shortlived profile
        --rsa-key-size "$DEFAULT_KEY_SIZE"
    )
    
    # If using webroot, add the path
    if [[ -z "$web_server" ]] && [[ "${certbot_cmd[1]}" != "--standalone" ]]; then
        certbot_cmd=(certbot certonly --webroot -w "$webroot" "${certbot_cmd[@]:2}")
    fi
    
    # Log the command
    log "AUDIT" "Executing certbot for IP certificate"
    log "DEBUG" "Command: ${certbot_cmd[*]}"
    
    # Show important notice
    echo -e "\n${CYAN}${INFO} IP Certificate Request Details:${NC}"
    echo -e "  • IP Address: ${WHITE}$ip_address${NC}"
    echo -e "  • Environment: ${YELLOW}STAGING${NC} (IP certs only available in staging)"
    echo -e "  • Profile: ${YELLOW}$REQUIRED_PROFILE${NC} (6-day validity)"
    echo -e "  • Challenge: HTTP-01 (port 80 required)"
    echo -e "\n${YELLOW}${WARNING} This certificate will expire in 6 days!${NC}"
    echo -e "${YELLOW}Automatic renewal will be configured after issuance.${NC}\n"
    
    # Execute certbot
    if "${certbot_cmd[@]}"; then
        log "INFO" "IP certificate obtained successfully!"
        log "AUDIT" "Certificate issued for IP: $ip_address"
        
        # Display certificate information
        echo -e "\n${GREEN}${CHECKMARK} Certificate Details:${NC}"
        certbot certificates -d "$ip_address" | grep -E "(Certificate Name|Domains|Expiry Date|Certificate Path|Private Key Path)" | while IFS= read -r line; do
            echo "  $line"
        done
        
        # Important reminder about renewal
        echo -e "\n${RED}CRITICAL: Configure automatic renewal immediately!${NC}"
        echo -e "${YELLOW}Run: $0 --setup-renewal${NC}"
        echo -e "${YELLOW}Short-lived certificates expire in just 6 days!${NC}\n"
        
        return 0
    else
        log "ERROR" "Failed to obtain IP certificate"
        
        # Provide troubleshooting guidance
        echo -e "\n${RED}Troubleshooting Guide:${NC}"
        echo "1. Verify IP address is public (not private/local)"
        echo "2. Ensure port 80 is open in firewall"
        echo "3. Check that no other service is using port 80"
        echo "4. Verify the IP is assigned to this server"
        echo "5. Check certbot logs: /var/log/letsencrypt/letsencrypt.log"
        echo "6. Ensure certbot version supports profiles (2.0.0+)"
        
        return 1
    fi
}

# Function: Renew IP certificates
renew_ip_certificates() {
    local force="${1:-false}"
    
    log "INFO" "Starting IP certificate renewal check..."
    log "AUDIT" "Certificate renewal initiated by: ${SUDO_USER:-root}"
    
    # Build renewal command
    local renew_cmd=(certbot renew --non-interactive)
    
    # Add force flag if requested
    [[ "$force" == "true" ]] && renew_cmd+=(--force-renewal)
    
    # Add post-hook for web server reload
    renew_cmd+=(--deploy-hook "$RENEWAL_DEPLOY_HOOK")
    
    # Test renewal first
    log "INFO" "Testing renewal process (dry run)..."
    if certbot renew --dry-run; then
        log "INFO" "Renewal test successful"
        
        # Perform actual renewal
        log "INFO" "Performing certificate renewal..."
        if "${renew_cmd[@]}" 2>&1 | tee -a "$RENEWAL_LOG"; then
            log "INFO" "Certificate renewal completed"
            log "AUDIT" "Renewal process completed"
            
            # Check renewal results
            if grep -q "Cert not yet due for renewal" "$RENEWAL_LOG"; then
                log "INFO" "No certificates were due for renewal"
            elif grep -q "Congratulations, all renewals succeeded" "$RENEWAL_LOG"; then
                log "INFO" "All certificates renewed successfully"
            fi
        else
            log "ERROR" "Certificate renewal failed"
            return 1
        fi
    else
        log "ERROR" "Renewal test failed"
        return 1
    fi
}

# Function: Setup automatic renewal
setup_auto_renewal() {
    log "INFO" "Setting up automatic renewal for short-lived IP certificates..."
    log "AUDIT" "Auto-renewal configuration initiated by: ${SUDO_USER:-root}"
    
    # Create systemd timer (preferred method)
    if command -v systemctl >/dev/null 2>&1; then
        log "INFO" "Creating systemd timer for aggressive renewal schedule..."
        
        # Create service unit
        cat > /etc/systemd/system/certbot-ip-renew.service << EOF
[Unit]
Description=Let's Encrypt IP Certificate Renewal
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/certbot renew --non-interactive --deploy-hook "$RENEWAL_DEPLOY_HOOK"
StandardOutput=append:$RENEWAL_LOG
StandardError=append:$RENEWAL_LOG
PrivateTmp=yes
NoNewPrivileges=yes
EOF

        # Create timer unit for aggressive schedule
        cat > /etc/systemd/system/certbot-ip-renew.timer << EOF
[Unit]
Description=Let's Encrypt IP Certificate Renewal Timer (6-day certs)
Requires=network-online.target

[Timer]
# Run every 4 hours for 6-day certificates
OnCalendar=*-*-* 00,04,08,12,16,20:00:00
RandomizedDelaySec=300
Persistent=true

[Install]
WantedBy=timers.target
EOF

        # Enable and start timer
        systemctl daemon-reload
        systemctl enable certbot-ip-renew.timer
        systemctl start certbot-ip-renew.timer
        
        log "INFO" "Systemd timer configured and started"
    fi
    
    # Also setup cron as fallback
    log "INFO" "Creating cron job for renewal fallback..."
    
    cat > /etc/cron.d/certbot-ip-renew << EOF
# Let's Encrypt IP Certificate Renewal (6-day certificates)
# Runs every 4 hours with random delay
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

$RENEWAL_INTERVAL root sleep \$((RANDOM \% 300)); /usr/bin/certbot renew --non-interactive --deploy-hook "$RENEWAL_DEPLOY_HOOK" >> $RENEWAL_LOG 2>&1

# Also check at system startup
@reboot root sleep 60; /usr/bin/certbot renew --non-interactive >> $RENEWAL_LOG 2>&1
EOF

    chmod 644 /etc/cron.d/certbot-ip-renew
    
    # Restart cron
    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        systemctl restart cron
    else
        systemctl restart crond
    fi
    
    log "INFO" "Automatic renewal configured successfully"
    
    # Show configuration summary
    echo -e "\n${GREEN}${CHECKMARK} Automatic Renewal Configured:${NC}"
    echo -e "  • Systemd Timer: ${WHITE}certbot-ip-renew.timer${NC}"
    echo -e "  • Schedule: ${YELLOW}Every 4 hours${NC} (critical for 6-day certs)"
    echo -e "  • Cron Backup: ${WHITE}/etc/cron.d/certbot-ip-renew${NC}"
    echo -e "  • Renewal Log: ${WHITE}$RENEWAL_LOG${NC}"
    
    # Show timer status
    if command -v systemctl >/dev/null 2>&1; then
        echo -e "\n${CYAN}Timer Status:${NC}"
        systemctl status certbot-ip-renew.timer --no-pager | grep -E "(Loaded|Active|Trigger)" || true
    fi
    
    # Create first renewal check
    log "INFO" "Running initial renewal check..."
    renew_ip_certificates
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Function: List IP certificates
list_ip_certificates() {
    log "INFO" "Listing all certificates..."
    
    if command -v certbot >/dev/null 2>&1; then
        echo -e "\n${GREEN}Current Certificates:${NC}"
        
        # Get certificate list and highlight IP certificates
        certbot certificates 2>/dev/null | while IFS= read -r line; do
            if [[ "$line" =~ ^Certificate\ Name: ]] || [[ "$line" =~ [0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3} ]] || [[ "$line" =~ ([0-9a-fA-F]{1,4}:){1,7}[0-9a-fA-F]{1,4} ]]; then
                echo -e "${YELLOW}$line${NC}"
            else
                echo "  $line"
            fi
        done
        
        # Check for expiring certificates
        echo -e "\n${CYAN}Checking expiration status...${NC}"
        local expiring=$(certbot certificates 2>/dev/null | grep -B2 "INVALID: EXPIRED" | grep "Certificate Name" | cut -d: -f2)
        
        if [[ -n "$expiring" ]]; then
            echo -e "${RED}${WARNING} Expired certificates found:${NC}"
            echo "$expiring"
        else
            local soon=$(certbot certificates 2>/dev/null | grep -B2 "expiry" | grep -E "([0-5]) days" || true)
            if [[ -n "$soon" ]]; then
                echo -e "${YELLOW}${WARNING} Certificates expiring soon!${NC}"
                echo -e "${YELLOW}Run renewal immediately: $0 --renew${NC}"
            else
                echo -e "${GREEN}${CHECKMARK} All certificates are valid${NC}"
            fi
        fi
    else
        log "ERROR" "Certbot is not installed"
        return 1
    fi
}

# Function: Show version
show_version() {
    cat << EOF
${GREEN}Let's Encrypt IP Certificate Manager${NC}
${WHITE}Version ${SCRIPT_VERSION}${NC}

Specialized tool for managing Let's Encrypt certificates for IP addresses.
Currently supports staging environment only (production coming soon).

Features:
  • IPv4 and IPv6 address support
  • Mandatory short-lived certificates (6-day validity)
  • Automatic renewal every 4 hours
  • Public IP validation
  • HTTP-01 challenge support

For help: $0 --help
EOF
}

# Function: Display usage
usage() {
    cat << EOF
${GREEN}Let's Encrypt IP Certificate Manager v${SCRIPT_VERSION}${NC}

${WHITE}USAGE:${NC}
    $0 [OPTIONS]

${WHITE}OPTIONS:${NC}
    ${CYAN}Certificate Operations:${NC}
    -i, --ip IP_ADDRESS       Public IP address (IPv4 or IPv6) for certificate
    -e, --email EMAIL         Email address for certificate notifications
    -w, --webroot PATH        Webroot path for HTTP-01 challenge
                             (default: $DEFAULT_WEBROOT)
    
    ${CYAN}Management Operations:${NC}
    --install                 Install certbot with profile support
    --renew                   Renew existing IP certificates
    --force-renew            Force renewal of all certificates
    --setup-renewal          Configure automatic renewal (every 4 hours)
    --list                   List all certificates and expiration status
    --check-profiles         Show available ACME profiles
    
    ${CYAN}Information:${NC}
    -h, --help               Show this help message
    -v, --version            Show version information
    --debug                  Enable debug logging

${WHITE}EXAMPLES:${NC}
    ${CYAN}# Install certbot${NC}
    $0 --install

    ${CYAN}# Check available ACME profiles${NC}
    $0 --check-profiles

    ${CYAN}# Obtain certificate for IPv4 address${NC}
    $0 -i 203.0.113.10 -e admin@example.com

    ${CYAN}# Obtain certificate for IPv6 address${NC}
    $0 -i 2001:db8::1 -e admin@example.com

    ${CYAN}# Setup automatic renewal (CRITICAL!)${NC}
    $0 --setup-renewal

    ${CYAN}# List certificates and check expiration${NC}
    $0 --list

    ${CYAN}# Force renewal of certificates${NC}
    $0 --force-renew

${WHITE}IMPORTANT NOTES:${NC}
    ${RED}• IP certificates are currently STAGING ONLY${NC}
    ${RED}• Certificates are valid for only 6 DAYS${NC}
    ${RED}• Automatic renewal is MANDATORY${NC}
    ${YELLOW}• Requires public IP address (not private/local)${NC}
    ${YELLOW}• Port 80 must be accessible${NC}
    ${YELLOW}• DNS-01 challenge is not supported${NC}

${WHITE}REQUIREMENTS:${NC}
    • Root/sudo access
    • Certbot 2.0.0+ with profile support
    • Public IP address
    • Open port 80

${WHITE}LOG FILES:${NC}
    • Main: $LOG_FILE
    • Errors: $ERROR_LOG
    • Audit: $AUDIT_LOG
    • Renewal: $RENEWAL_LOG

For more information about IP certificates:
https://letsencrypt.org/2025/07/01/issuing-our-first-ip-address-certificate/

EOF
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

main() {
    # Initialize
    init_logging
    check_root
    
    # Default values
    local ip_address=""
    local email=""
    local webroot="$DEFAULT_WEBROOT"
    local operation=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            -i|--ip)
                ip_address="$2"
                shift 2
                ;;
            -e|--email)
                email="$2"
                shift 2
                ;;
            -w|--webroot)
                webroot="$2"
                shift 2
                ;;
            --install)
                operation="install"
                shift
                ;;
            --renew)
                operation="renew"
                shift
                ;;
            --force-renew)
                operation="force_renew"
                shift
                ;;
            --setup-renewal)
                operation="setup_renewal"
                shift
                ;;
            --list)
                operation="list"
                shift
                ;;
            --check-profiles)
                operation="check_profiles"
                shift
                ;;
            --debug)
                export DEBUG=true
                set -x
                shift
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Acquire lock
    if ! acquire_lock; then
        exit 1
    fi
    
    # Detect OS
    detect_os
    
    # Execute requested operation
    case "$operation" in
        install)
            check_dependencies
            install_certbot
            ;;
        renew)
            renew_ip_certificates false
            ;;
        force_renew)
            renew_ip_certificates true
            ;;
        setup_renewal)
            setup_auto_renewal
            ;;
        list)
            list_ip_certificates
            ;;
        check_profiles)
            check_profiles
            ;;
        *)
            # Default: obtain certificate
            if [[ -n "$ip_address" ]] && [[ -n "$email" ]]; then
                check_dependencies
                obtain_ip_certificate "$ip_address" "$email" "$webroot"
            else
                usage
                exit 0
            fi
            ;;
    esac
    
    # Log completion
    log "AUDIT" "Script completed successfully"
}

# ============================================================================
# SCRIPT ENTRY POINT
# ============================================================================

# Display banner for IP certificate focus
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${WHITE}    Let's Encrypt IP Address Certificate Manager    ${NC}"
echo -e "${YELLOW}         Staging Environment Only (July 2025)       ${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Run main function
main "$@"

# Exit successfully
exit 0