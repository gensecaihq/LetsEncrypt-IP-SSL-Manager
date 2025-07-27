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

# Production-ready error handling
set -euo pipefail  # Exit on error, undefined vars, pipe failures
set -o errtrace    # Inherit ERR trap in functions and subshells

# Enable debug mode if DEBUG environment variable is set
[[ "${DEBUG:-}" == "true" ]] && set -x

# Global error tracking
SCRIPT_ERRORS=0
WARNINGS_COUNT=0
CRITICAL_ERRORS=()
RECOVERY_ACTIONS=()

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

# Configuration file path
readonly CONFIG_FILE="/etc/letsencrypt-ip-manager/config.conf"
readonly BACKUP_DIR="/etc/letsencrypt-ip-manager/backup"
readonly MAX_BACKUPS=10

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
# CONFIGURATION MANAGEMENT
# ============================================================================

# Function: Load configuration from file
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log "DEBUG" "Loading configuration from $CONFIG_FILE"
        source "$CONFIG_FILE"
    fi
}

# Function: Create backup with rotation
create_backup() {
    local source_file="$1"
    local backup_type="${2:-config}"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="${BACKUP_DIR}/${backup_type}_${timestamp}.backup"
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    chmod 750 "$BACKUP_DIR"
    
    # Create backup if source exists
    if [[ -f "$source_file" ]]; then
        if cp "$source_file" "$backup_file" 2>/dev/null; then
            chmod 640 "$backup_file"
            log "INFO" "Backup created: $backup_file"
            
            # Rotate old backups
            rotate_backups "$backup_type"
            return 0
        else
            log "WARN" "Failed to create backup of $source_file"
            return 1
        fi
    fi
    
    return 0
}

# Function: Rotate backups to maintain MAX_BACKUPS limit
rotate_backups() {
    local backup_type="$1"
    local backup_pattern="${BACKUP_DIR}/${backup_type}_*.backup"
    
    # Count existing backups
    local backup_count=$(ls -1 "$backup_pattern" 2>/dev/null | wc -l)
    
    if [[ $backup_count -gt $MAX_BACKUPS ]]; then
        log "DEBUG" "Rotating backups (current: $backup_count, max: $MAX_BACKUPS)"
        
        # Remove oldest backups
        ls -1t "$backup_pattern" 2>/dev/null | tail -n +$((MAX_BACKUPS + 1)) | while read -r old_backup; do
            rm -f "$old_backup"
            log "DEBUG" "Removed old backup: $old_backup"
        done
    fi
}

# Function: Save configuration to file with backup
save_config() {
    local config_dir="$(dirname "$CONFIG_FILE")"
    mkdir -p "$config_dir"
    chmod 750 "$config_dir"
    
    # Create backup of existing configuration
    create_backup "$CONFIG_FILE" "config"
    
    # Validate configuration values before saving
    if [[ -n "${USER_EMAIL:-}" ]] && ! validate_email "$USER_EMAIL"; then
        log "ERROR" "Invalid email in configuration, not saving"
        return 1
    fi
    
    if [[ -n "${USER_WEBROOT:-}" ]] && ! validate_path "$USER_WEBROOT" "any"; then
        log "ERROR" "Invalid webroot path in configuration, not saving"
        return 1
    fi
    
    # Create new configuration file
    if ! cat > "$CONFIG_FILE" << EOF
# Let's Encrypt IP Manager Configuration
# Generated on $(date)
# PID: $$

# User preferences
USER_EMAIL="${USER_EMAIL:-}"
USER_WEBROOT="${USER_WEBROOT:-$DEFAULT_WEBROOT}"
USER_KEY_SIZE="${USER_KEY_SIZE:-$DEFAULT_KEY_SIZE}"

# Renewal preferences
AUTO_RENEWAL_ENABLED="${AUTO_RENEWAL_ENABLED:-true}"
RENEWAL_NOTIFICATIONS="${RENEWAL_NOTIFICATIONS:-true}"
RENEWAL_WEB_SERVER="${RENEWAL_WEB_SERVER:-auto}"

# Logging preferences
LOG_LEVEL="${LOG_LEVEL:-INFO}"
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-30}"

# Advanced settings
CHALLENGE_TYPE="${CHALLENGE_TYPE:-http-01}"
PREFERRED_CHAIN="${PREFERRED_CHAIN:-}"
DEPLOY_HOOK_CUSTOM="${DEPLOY_HOOK_CUSTOM:-}"

# Backup information
LAST_BACKUP="$(date)"
CONFIG_VERSION="$SCRIPT_VERSION"
EOF
    then
        chmod 640 "$CONFIG_FILE"
        log "INFO" "Configuration saved to $CONFIG_FILE"
        log "AUDIT" "Configuration updated by user ${SUDO_USER:-root}"
        return 0
    else
        log "ERROR" "Failed to save configuration"
        restore_backup "config"
        return 1
    fi
}

# Function: Restore from backup
restore_backup() {
    local backup_type="$1"
    local specific_backup="$2"
    local backup_file=""
    
    if [[ -n "$specific_backup" ]]; then
        backup_file="$specific_backup"
    else
        # Find most recent backup
        backup_file=$(ls -1t "${BACKUP_DIR}/${backup_type}_"*.backup 2>/dev/null | head -1)
    fi
    
    if [[ -n "$backup_file" ]] && [[ -f "$backup_file" ]]; then
        local target_file=""
        
        case "$backup_type" in
            config)
                target_file="$CONFIG_FILE"
                ;;
            cert)
                target_file="$2"  # Second parameter should be target path for cert backups
                ;;
        esac
        
        if [[ -n "$target_file" ]]; then
            if cp "$backup_file" "$target_file" 2>/dev/null; then
                log "INFO" "Restored from backup: $backup_file -> $target_file"
                log "AUDIT" "Configuration restored from backup by ${SUDO_USER:-root}"
                return 0
            else
                log "ERROR" "Failed to restore from backup: $backup_file"
                return 1
            fi
        fi
    else
        log "ERROR" "No backup found for type: $backup_type"
        return 1
    fi
}

# Function: List available backups
list_backups() {
    local backup_type="${1:-all}"
    
    log "INFO" "Available backups:"
    
    if [[ "$backup_type" == "all" ]]; then
        ls -la "$BACKUP_DIR"/*.backup 2>/dev/null | while read -r backup; do
            echo "  $backup"
        done
    else
        ls -la "${BACKUP_DIR}/${backup_type}_"*.backup 2>/dev/null | while read -r backup; do
            echo "  $backup"
        done
    fi
}

# Function: Emergency recovery mode
emergency_recovery() {
    log "WARN" "Entering emergency recovery mode..."
    log "AUDIT" "Emergency recovery initiated by ${SUDO_USER:-root}"
    
    # Stop any running renewal services
    case "$INIT_SYSTEM" in
        systemd)
            systemctl stop certbot-ip-renew.timer 2>/dev/null || true
            systemctl stop certbot-ip-renew.service 2>/dev/null || true
            ;;
        openrc)
            rc-service certbot-ip-renew stop 2>/dev/null || true
            ;;
        sysv)
            service certbot-ip-renew stop 2>/dev/null || true
            ;;
    esac
    
    # Create emergency backup of current state
    local emergency_backup="${BACKUP_DIR}/emergency_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$emergency_backup"
    
    # Backup configuration
    [[ -f "$CONFIG_FILE" ]] && cp "$CONFIG_FILE" "$emergency_backup/" 2>/dev/null
    
    # Backup certificates
    if [[ -d "$CERT_LIVE_PATH" ]]; then
        cp -r "$CERT_LIVE_PATH" "$emergency_backup/" 2>/dev/null || true
    fi
    
    # Backup logs
    cp -r "$LOG_DIR" "$emergency_backup/" 2>/dev/null || true
    
    log "INFO" "Emergency backup created at: $emergency_backup"
    
    # Offer recovery options
    echo -e "\n${YELLOW}Emergency Recovery Options:${NC}"
    echo "1. Restore configuration from backup"
    echo "2. Reset configuration to defaults"
    echo "3. Check system integrity"
    echo "4. Exit recovery mode"
    
    read -p "Select option (1-4): " recovery_option
    
    case "$recovery_option" in
        1)
            list_backups "config"
            read -p "Enter backup filename to restore: " backup_file
            restore_backup "config" "$backup_file"
            ;;
        2)
            reset_configuration
            ;;
        3)
            perform_system_integrity_check
            ;;
        4)
            log "INFO" "Exiting recovery mode"
            ;;
        *)
            log "ERROR" "Invalid option selected"
            ;;
    esac
}

# Function: Reset configuration to defaults
reset_configuration() {
    log "WARN" "Resetting configuration to defaults..."
    
    # Backup current config
    create_backup "$CONFIG_FILE" "pre_reset"
    
    # Clear all user variables
    unset USER_EMAIL USER_WEBROOT USER_KEY_SIZE
    unset AUTO_RENEWAL_ENABLED RENEWAL_NOTIFICATIONS RENEWAL_WEB_SERVER
    unset LOG_LEVEL LOG_RETENTION_DAYS
    unset CHALLENGE_TYPE PREFERRED_CHAIN DEPLOY_HOOK_CUSTOM
    
    # Save defaults
    save_config
    
    log "INFO" "Configuration reset to defaults"
    log "AUDIT" "Configuration reset by ${SUDO_USER:-root}"
}

# Function: System integrity check
perform_system_integrity_check() {
    log "INFO" "Performing system integrity check..."
    
    local issues_found=0
    
    # Check configuration file
    if [[ -f "$CONFIG_FILE" ]]; then
        if source "$CONFIG_FILE" 2>/dev/null; then
            log "INFO" "Configuration file is valid"
        else
            log "ERROR" "Configuration file is corrupted"
            issues_found=$((issues_found + 1))
        fi
    else
        log "WARN" "Configuration file missing"
        issues_found=$((issues_found + 1))
    fi
    
    # Check certificate directory permissions
    if [[ -d "$CERT_BASE_PATH" ]]; then
        if [[ ! -r "$CERT_BASE_PATH" ]]; then
            log "ERROR" "Certificate directory not readable"
            issues_found=$((issues_found + 1))
        fi
    fi
    
    # Check log directory
    if [[ ! -w "$LOG_DIR" ]]; then
        log "ERROR" "Log directory not writable"
        issues_found=$((issues_found + 1))
    fi
    
    # Check certbot
    if ! command -v certbot >/dev/null 2>&1; then
        log "ERROR" "Certbot not found"
        issues_found=$((issues_found + 1))
    fi
    
    if [[ $issues_found -eq 0 ]]; then
        log "INFO" "System integrity check passed"
    else
        log "WARN" "System integrity check found $issues_found issues"
    fi
    
    return $issues_found
}

# Function: Interactive configuration wizard
interactive_config() {
    echo -e "\n${CYAN}${INFO} Let's Encrypt IP Manager - Configuration Wizard${NC}"
    echo -e "${YELLOW}This wizard will help you configure the SSL manager with your preferences.${NC}\n"
    
    # Email configuration
    while true; do
        echo -e "${WHITE}Email Configuration:${NC}"
        read -p "Enter your email address for certificate notifications: " user_email
        if validate_email "$user_email"; then
            USER_EMAIL="$user_email"
            break
        fi
        echo -e "${RED}Please enter a valid email address.${NC}\n"
    done
    
    # Webroot configuration
    echo -e "\n${WHITE}Webroot Configuration:${NC}"
    echo -e "Current default: ${YELLOW}$DEFAULT_WEBROOT${NC}"
    read -p "Enter custom webroot path (or press Enter for default): " user_webroot
    USER_WEBROOT="${user_webroot:-$DEFAULT_WEBROOT}"
    
    # Key size configuration
    echo -e "\n${WHITE}RSA Key Size Configuration:${NC}"
    echo -e "Available options: ${YELLOW}2048, 4096${NC}"
    echo -e "Current default: ${YELLOW}$DEFAULT_KEY_SIZE${NC}"
    while true; do
        read -p "Enter RSA key size (2048/4096) [default: $DEFAULT_KEY_SIZE]: " user_key_size
        user_key_size="${user_key_size:-$DEFAULT_KEY_SIZE}"
        if [[ "$user_key_size" == "2048" ]] || [[ "$user_key_size" == "4096" ]]; then
            USER_KEY_SIZE="$user_key_size"
            break
        fi
        echo -e "${RED}Please enter 2048 or 4096.${NC}"
    done
    
    # Auto-renewal configuration
    echo -e "\n${WHITE}Auto-Renewal Configuration:${NC}"
    echo -e "${YELLOW}Note: Auto-renewal is critical for 6-day IP certificates!${NC}"
    while true; do
        read -p "Enable automatic renewal? (y/n) [default: y]: " auto_renewal
        auto_renewal="${auto_renewal:-y}"
        case "$auto_renewal" in
            y|Y|yes|YES)
                AUTO_RENEWAL_ENABLED="true"
                break
                ;;
            n|N|no|NO)
                AUTO_RENEWAL_ENABLED="false"
                echo -e "${RED}${WARNING} Warning: Manual renewal required every 6 days!${NC}"
                break
                ;;
            *)
                echo -e "${RED}Please enter y or n.${NC}"
                ;;
        esac
    done
    
    # Renewal notifications
    echo -e "\n${WHITE}Notification Configuration:${NC}"
    while true; do
        read -p "Enable renewal notifications via email? (y/n) [default: y]: " notifications
        notifications="${notifications:-y}"
        case "$notifications" in
            y|Y|yes|YES)
                RENEWAL_NOTIFICATIONS="true"
                break
                ;;
            n|N|no|NO)
                RENEWAL_NOTIFICATIONS="false"
                break
                ;;
            *)
                echo -e "${RED}Please enter y or n.${NC}"
                ;;
        esac
    done
    
    # Web server detection/preference
    echo -e "\n${WHITE}Web Server Configuration:${NC}"
    echo -e "Available options: ${YELLOW}auto, nginx, apache, standalone${NC}"
    echo -e "  • auto: Automatically detect running web server"
    echo -e "  • nginx: Use nginx plugin"
    echo -e "  • apache: Use apache plugin"
    echo -e "  • standalone: Use certbot's built-in server"
    while true; do
        read -p "Select web server preference [default: auto]: " web_server
        web_server="${web_server:-auto}"
        case "$web_server" in
            auto|nginx|apache|standalone)
                RENEWAL_WEB_SERVER="$web_server"
                break
                ;;
            *)
                echo -e "${RED}Please enter auto, nginx, apache, or standalone.${NC}"
                ;;
        esac
    done
    
    # Logging configuration
    echo -e "\n${WHITE}Logging Configuration:${NC}"
    echo -e "Available log levels: ${YELLOW}DEBUG, INFO, WARN, ERROR${NC}"
    while true; do
        read -p "Select log level [default: INFO]: " log_level
        log_level="${log_level:-INFO}"
        case "$log_level" in
            DEBUG|INFO|WARN|ERROR)
                LOG_LEVEL="$log_level"
                break
                ;;
            *)
                echo -e "${RED}Please enter DEBUG, INFO, WARN, or ERROR.${NC}"
                ;;
        esac
    done
    
    # Log retention
    echo -e "\n${WHITE}Log Retention Configuration:${NC}"
    while true; do
        read -p "Log retention period in days [default: 30]: " retention
        retention="${retention:-30}"
        if [[ "$retention" =~ ^[0-9]+$ ]] && [[ "$retention" -gt 0 ]] && [[ "$retention" -le 365 ]]; then
            LOG_RETENTION_DAYS="$retention"
            break
        fi
        echo -e "${RED}Please enter a number between 1 and 365.${NC}"
    done
    
    # Custom deploy hook
    echo -e "\n${WHITE}Custom Deploy Hook (Advanced):${NC}"
    echo -e "Enter a custom command to run after certificate deployment"
    echo -e "Examples: 'docker restart nginx', 'systemctl reload haproxy'"
    read -p "Custom deploy hook (optional): " custom_hook
    DEPLOY_HOOK_CUSTOM="$custom_hook"
    
    # Save configuration
    save_config
    
    # Configuration summary
    echo -e "\n${GREEN}${CHECKMARK} Configuration Summary:${NC}"
    echo -e "  ${CYAN}Email:${NC} $USER_EMAIL"
    echo -e "  ${CYAN}Webroot:${NC} $USER_WEBROOT"
    echo -e "  ${CYAN}Key Size:${NC} $USER_KEY_SIZE bits"
    echo -e "  ${CYAN}Auto-Renewal:${NC} $AUTO_RENEWAL_ENABLED"
    echo -e "  ${CYAN}Notifications:${NC} $RENEWAL_NOTIFICATIONS"
    echo -e "  ${CYAN}Web Server:${NC} $RENEWAL_WEB_SERVER"
    echo -e "  ${CYAN}Log Level:${NC} $LOG_LEVEL"
    echo -e "  ${CYAN}Log Retention:${NC} $LOG_RETENTION_DAYS days"
    [[ -n "$DEPLOY_HOOK_CUSTOM" ]] && echo -e "  ${CYAN}Custom Hook:${NC} $DEPLOY_HOOK_CUSTOM"
    
    echo -e "\n${YELLOW}Configuration saved to: $CONFIG_FILE${NC}"
}

# Function: Quick IP certificate setup
quick_setup() {
    local ip_address=""
    
    echo -e "\n${CYAN}${INFO} Quick IP Certificate Setup${NC}"
    echo -e "${YELLOW}This will guide you through obtaining an IP certificate quickly.${NC}\n"
    
    # Check if configuration exists
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo -e "${YELLOW}No configuration found. Running configuration wizard first...${NC}"
        interactive_config
        echo ""
    else
        load_config
        echo -e "${GREEN}Using existing configuration.${NC}"
        echo -e "Email: ${USER_EMAIL:-Not configured}"
        echo -e "To reconfigure, run: $0 --configure\n"
    fi
    
    # Get IP address
    while true; do
        echo -e "${WHITE}IP Address Configuration:${NC}"
        echo -e "You can:"
        echo -e "  1. Enter an IP address manually"
        echo -e "  2. Auto-detect your public IPv4"
        echo -e "  3. Auto-detect your public IPv6"
        echo ""
        read -p "Choose option (1/2/3): " ip_choice
        
        case "$ip_choice" in
            1)
                read -p "Enter your public IP address: " ip_address
                if validate_ip_address "$ip_address"; then
                    break
                fi
                ;;
            2)
                echo "Detecting public IPv4..."
                ip_address=$(curl -s -4 --connect-timeout 5 icanhazip.com 2>/dev/null || curl -s -4 --connect-timeout 5 ipv4.icanhazip.com 2>/dev/null)
                if [[ -n "$ip_address" ]] && validate_ip_address "$ip_address"; then
                    echo -e "${GREEN}Detected IPv4: $ip_address${NC}"
                    break
                else
                    echo -e "${RED}Failed to detect IPv4 address. Please try manually.${NC}"
                fi
                ;;
            3)
                echo "Detecting public IPv6..."
                ip_address=$(curl -s -6 --connect-timeout 5 icanhazip.com 2>/dev/null || curl -s -6 --connect-timeout 5 ipv6.icanhazip.com 2>/dev/null)
                if [[ -n "$ip_address" ]] && validate_ip_address "$ip_address"; then
                    echo -e "${GREEN}Detected IPv6: $ip_address${NC}"
                    break
                else
                    echo -e "${RED}Failed to detect IPv6 address. Please try manually.${NC}"
                fi
                ;;
            *)
                echo -e "${RED}Please enter 1, 2, or 3.${NC}"
                ;;
        esac
    done
    
    # Final confirmation
    echo -e "\n${WHITE}Certificate Request Summary:${NC}"
    echo -e "  ${CYAN}IP Address:${NC} $ip_address"
    echo -e "  ${CYAN}Email:${NC} ${USER_EMAIL:-$email}"
    echo -e "  ${CYAN}Webroot:${NC} ${USER_WEBROOT:-$DEFAULT_WEBROOT}"
    echo -e "  ${CYAN}Environment:${NC} ${YELLOW}STAGING${NC} (6-day certificates)"
    echo ""
    
    while true; do
        read -p "Proceed with certificate request? (y/n): " confirm
        case "$confirm" in
            y|Y|yes|YES)
                # Proceed with certificate request
                check_dependencies
                obtain_ip_certificate "$ip_address" "${USER_EMAIL:-$email}" "${USER_WEBROOT:-$DEFAULT_WEBROOT}"
                
                # Setup auto-renewal if enabled
                if [[ "${AUTO_RENEWAL_ENABLED:-true}" == "true" ]]; then
                    echo -e "\n${YELLOW}Setting up automatic renewal...${NC}"
                    setup_auto_renewal
                fi
                
                return 0
                ;;
            n|N|no|NO)
                echo -e "${YELLOW}Certificate request cancelled.${NC}"
                return 0
                ;;
            *)
                echo -e "${RED}Please enter y or n.${NC}"
                ;;
        esac
    done
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Function: Initialize logging system
init_logging() {
    # Skip logging setup for non-root users running info commands
    if [[ $EUID -ne 0 ]] && [[ "${1:-}" =~ ^(help|version|show_config)$ ]]; then
        return 0
    fi
    
    # Create log directory if it doesn't exist
    if [[ ! -d "$LOG_DIR" ]]; then
        if ! mkdir -p "$LOG_DIR" 2>/dev/null; then
            # Fallback to user's home directory for non-root users
            if [[ $EUID -ne 0 ]]; then
                local fallback_log_dir="$HOME/.letsencrypt-ip-manager/logs"
                mkdir -p "$fallback_log_dir"
                # Use fallback locations without changing readonly variables
                echo "Warning: Using fallback log directory: $fallback_log_dir" >&2
            else
                echo "Error: Cannot create log directory $LOG_DIR" >&2
                return 1
            fi
        fi
        chmod 750 "$LOG_DIR" 2>/dev/null || true
    fi
    
    # Create log files
    touch "$LOG_FILE" "$ERROR_LOG" "$AUDIT_LOG" "$RENEWAL_LOG" 2>/dev/null || true
    chmod 640 "$LOG_FILE" "$ERROR_LOG" "$AUDIT_LOG" "$RENEWAL_LOG" 2>/dev/null || true
    
    # Rotate logs if they're too large (>50MB for more frequent rotation)
    for log in "$LOG_FILE" "$ERROR_LOG" "$AUDIT_LOG" "$RENEWAL_LOG"; do
        if [[ -f "$log" ]] && [[ $(stat -f%z "$log" 2>/dev/null || stat -c%s "$log" 2>/dev/null || echo 0) -gt 52428800 ]]; then
            mv "$log" "${log}.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
            touch "$log" 2>/dev/null || true
            chmod 640 "$log" 2>/dev/null || true
        fi
    done
}

# Function: Enhanced logging with levels and error tracking
log() {
    local level="${1:-INFO}"
    local message="${2:-}"
    local print_stdout="${3:-true}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_entry="[${timestamp}] [${level}] [$$] ${message}"
    
    # Update counters
    case "$level" in
        WARN) WARNINGS_COUNT=$((WARNINGS_COUNT + 1)) ;;
        ERROR) SCRIPT_ERRORS=$((SCRIPT_ERRORS + 1)) ;;
    esac
    
    # Check log level setting
    local current_log_level="${LOG_LEVEL:-INFO}"
    local log_levels=("DEBUG" "INFO" "WARN" "ERROR")
    local current_level_num=1
    local message_level_num=1
    
    # Get numeric values for comparison
    for i in "${!log_levels[@]}"; do
        [[ "${log_levels[$i]}" == "$current_log_level" ]] && current_level_num=$i
        [[ "${log_levels[$i]}" == "$level" ]] && message_level_num=$i
    done
    
    # Only log if message level is >= current log level
    if [[ $message_level_num -lt $current_level_num ]]; then
        return 0
    fi
    
    # Write to appropriate log file (with robust error handling)
    case "$level" in
        ERROR)
            {
                [[ -w "${ERROR_LOG%/*}" ]] && echo "$log_entry" >> "$ERROR_LOG"
                [[ -w "${LOG_FILE%/*}" ]] && echo "$log_entry" >> "$LOG_FILE"
            } 2>/dev/null || {
                # Fallback to stderr if logs fail
                echo "[$timestamp] [ERROR] [$$] $message" >&2
            }
            [[ "${print_stdout:-true}" == "true" ]] && echo -e "${RED}${CROSS} ${message}${NC}" >&2
            
            # Add to syslog if available
            command -v logger >/dev/null 2>&1 && logger -p user.err -t "letsencrypt-ip-manager[$$]" "$message" || true
            ;;
        WARN)
            {
                [[ -w "${LOG_FILE%/*}" ]] && echo "$log_entry" >> "$LOG_FILE"
            } 2>/dev/null || true
            [[ "${print_stdout:-true}" == "true" ]] && echo -e "${YELLOW}${WARNING} ${message}${NC}"
            
            # Add to syslog if available
            command -v logger >/dev/null 2>&1 && logger -p user.warning -t "letsencrypt-ip-manager[$$]" "$message" || true
            ;;
        AUDIT)
            {
                [[ -w "${AUDIT_LOG%/*}" ]] && echo "$log_entry" >> "$AUDIT_LOG"
                [[ -w "${LOG_FILE%/*}" ]] && echo "$log_entry" >> "$LOG_FILE"
            } 2>/dev/null || true
            [[ "${print_stdout:-true}" == "true" ]] && echo -e "${CYAN}${INFO} ${message}${NC}"
            
            # Add to syslog if available
            command -v logger >/dev/null 2>&1 && logger -p user.info -t "letsencrypt-ip-manager[$$]" "AUDIT: $message" || true
            ;;
        DEBUG)
            if [[ "${DEBUG:-}" == "true" || "$current_log_level" == "DEBUG" ]]; then
                {
                    [[ -w "${LOG_FILE%/*}" ]] && echo "$log_entry" >> "$LOG_FILE"
                } 2>/dev/null || true
                [[ "${print_stdout:-true}" == "true" ]] && echo -e "${MAGENTA}[DEBUG] ${message}${NC}"
            fi
            ;;
        *)
            {
                [[ -w "${LOG_FILE%/*}" ]] && echo "$log_entry" >> "$LOG_FILE"
            } 2>/dev/null || true
            [[ "${print_stdout:-true}" == "true" ]] && echo -e "${GREEN}${CHECKMARK} ${message}${NC}"
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

# Function: Enhanced error handler
error_handler() {
    local exit_code=$?
    local line_number=$1
    local bash_lineno=$2
    local last_command="${3:-unknown}"
    local function_stack=("${FUNCNAME[@]:1}")
    
    SCRIPT_ERRORS=$((SCRIPT_ERRORS + 1))
    
    # Log detailed error information
    log "ERROR" "Script error occurred:" "false"
    log "ERROR" "  Exit Code: $exit_code" "false"
    log "ERROR" "  Line: $line_number" "false"
    log "ERROR" "  Command: $last_command" "false"
    log "ERROR" "  Function Stack: ${function_stack[*]}" "false"
    
    # Add to critical errors if severe
    if [[ $exit_code -ge 1 ]]; then
        CRITICAL_ERRORS+=("Line $line_number: $last_command (exit $exit_code)")
    fi
    
    # Attempt recovery for known issues
    case "$last_command" in
        *"systemctl"*)
            RECOVERY_ACTIONS+=("Check if systemd is available and running")
            ;;
        *"certbot"*)
            RECOVERY_ACTIONS+=("Verify certbot installation and version")
            ;;
        *"curl"*)
            RECOVERY_ACTIONS+=("Check network connectivity and DNS resolution")
            ;;
    esac
    
    return $exit_code
}

# Function: Enhanced cleanup with error reporting
cleanup() {
    local exit_code=$?
    local cleanup_errors=0
    
    # Release lock safely
    if ! release_lock; then
        cleanup_errors=$((cleanup_errors + 1))
        log "WARN" "Failed to release lock during cleanup" "false"
    fi
    
    # Generate error summary if there were issues (but not for help/info commands)
    case "${CURRENT_OPERATION:-}" in
        help|version|show_config|status|integrity_check)
            # Skip error reporting for informational commands
            ;;
        *)
            if [[ $SCRIPT_ERRORS -gt 0 ]] || [[ $exit_code -ne 0 ]]; then
                generate_error_report "$exit_code"
            fi
            ;;
    esac
    
    # Final status
    if [[ $exit_code -eq 0 ]]; then
        log "INFO" "Script completed successfully" "false"
        [[ $WARNINGS_COUNT -gt 0 ]] && log "WARN" "Completed with $WARNINGS_COUNT warnings" "false"
    else
        log "ERROR" "Script failed with exit code: $exit_code" "false"
        log "ERROR" "Total errors encountered: $SCRIPT_ERRORS" "false"
    fi
    
    exit $exit_code
}

# Function: Generate comprehensive error report
generate_error_report() {
    local exit_code=$1
    local report_file="${LOG_DIR}/error_report_$(date +%Y%m%d_%H%M%S).log"
    
    # Create error report
    cat > "$report_file" 2>/dev/null << EOF || true
================================================================
LetsEncrypt IP SSL Manager - Error Report
Generated: $(date)
================================================================

EXECUTION SUMMARY:
- Exit Code: $exit_code
- Total Errors: $SCRIPT_ERRORS
- Warnings: $WARNINGS_COUNT
- OS: $OS_NAME $OS_VERSION ($DISTRO_FAMILY)
- Architecture: $OS_ARCH
- Init System: $INIT_SYSTEM

CRITICAL ERRORS:
$(printf '%s\n' "${CRITICAL_ERRORS[@]}")

SUGGESTED RECOVERY ACTIONS:
$(printf '- %s\n' "${RECOVERY_ACTIONS[@]}")

SYSTEM INFORMATION:
- Hostname: $(hostname 2>/dev/null || echo "unknown")
- Uptime: $(uptime 2>/dev/null || echo "unknown")
- Memory: $(free -h 2>/dev/null | head -2 || echo "unknown")
- Disk Space: $(df -h / 2>/dev/null || echo "unknown")

RECENT LOG ENTRIES:
$(tail -20 "$LOG_FILE" 2>/dev/null || echo "No log entries available")

================================================================
EOF
    
    if [[ -f "$report_file" ]]; then
        log "INFO" "Error report generated: $report_file"
    fi
}

# Enhanced trap setup
trap 'error_handler ${LINENO} ${BASH_LINENO} "${BASH_COMMAND}"' ERR
trap cleanup EXIT INT TERM QUIT
trap 'log "WARN" "Received SIGUSR1 signal"; generate_status_report' USR1

# Function: Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "This script must be run as root or with sudo privileges"
        exit 1
    fi
}

# Function: Comprehensive input validation and sanitization
sanitize_input() {
    local input="$1"
    local input_type="${2:-general}"
    
    # Remove any null bytes and control characters
    input=$(printf '%s' "$input" | tr -d '\0\001\002\003\004\005\006\007\010\013\014\016\017\020\021\022\023\024\025\026\027\030\031\032\033\034\035\036\037')
    
    # Trim whitespace
    input=$(echo "$input" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    case "$input_type" in
        email)
            # Remove potentially dangerous characters for email (preserve @ and valid email chars)
            input=$(echo "$input" | tr -d ';<>|`$(){}[]')
            ;;
        path)
            # Basic path sanitization
            input=$(echo "$input" | tr -d ';|&<>()`${}[]')
            ;;
        ip)
            # IP address should only contain digits, dots, and colons
            input=$(echo "$input" | tr -cd '0-9a-fA-F.:')
            ;;
        domain)
            # Domain names - alphanumeric, dots, and hyphens only
            input=$(echo "$input" | tr -cd 'a-zA-Z0-9.-')
            ;;
    esac
    
    echo "$input"
}

# Function: Enhanced email validation with security checks
validate_email() {
    local email="$1"
    local sanitized_email
    
    # Input validation
    if [[ -z "$email" ]]; then
        log "ERROR" "Email address cannot be empty"
        return 1
    fi
    
    # Length check
    if [[ ${#email} -gt 254 ]]; then
        log "ERROR" "Email address too long (max 254 characters)"
        return 1
    fi
    
    # Sanitize input
    sanitized_email=$(sanitize_input "$email" "email")
    
    # Basic format validation
    local email_regex="^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"
    if [[ ! "$sanitized_email" =~ $email_regex ]]; then
        log "ERROR" "Invalid email address format: $email"
        return 1
    fi
    
    # Check for dangerous patterns
    local dangerous_patterns=("\.\." "@\." "\.@" "@@" "^\.+" "\.$")
    for pattern in "${dangerous_patterns[@]}"; do
        if [[ "$sanitized_email" =~ $pattern ]]; then
            log "ERROR" "Email contains invalid pattern: $email"
            return 1
        fi
    done
    
    # Validate domain part
    local domain="${sanitized_email##*@}"
    if [[ ${#domain} -gt 253 ]]; then
        log "ERROR" "Email domain too long: $domain"
        return 1
    fi
    
    # Check if domain has at least one dot
    if [[ ! "$domain" =~ \. ]]; then
        log "ERROR" "Email domain must contain at least one dot: $domain"
        return 1
    fi
    
    log "DEBUG" "Email validation passed: $sanitized_email"
    return 0
}

# Function: Enhanced path validation
validate_path() {
    local path="$1"
    local path_type="${2:-file}"  # file, directory, or any
    
    # Input validation
    if [[ -z "$path" ]]; then
        log "ERROR" "Path cannot be empty"
        return 1
    fi
    
    # Length check
    if [[ ${#path} -gt 4096 ]]; then
        log "ERROR" "Path too long (max 4096 characters)"
        return 1
    fi
    
    # Sanitize path
    local sanitized_path
    sanitized_path=$(sanitize_input "$path" "path")
    
    # Security checks
    local dangerous_patterns=("\.\./\.\." ";\s*rm\s" ";\s*cat\s" "\$\(" "`" "|" "&")
    for pattern in "${dangerous_patterns[@]}"; do
        if [[ "$sanitized_path" =~ $pattern ]]; then
            log "ERROR" "Path contains dangerous pattern: $path"
            return 1
        fi
    done
    
    # Must be absolute path for system operations
    if [[ "$path_type" == "system" ]] && [[ ! "$sanitized_path" =~ ^/ ]]; then
        log "ERROR" "System path must be absolute: $path"
        return 1
    fi
    
    # Check if path exists (if required)
    case "$path_type" in
        directory)
            if [[ ! -d "$sanitized_path" ]]; then
                log "WARN" "Directory does not exist: $sanitized_path"
            fi
            ;;
        file)
            if [[ ! -f "$sanitized_path" ]]; then
                log "WARN" "File does not exist: $sanitized_path"
            fi
            ;;
    esac
    
    log "DEBUG" "Path validation passed: $sanitized_path"
    return 0
}

# Function: Validate command input for safety
validate_command_input() {
    local input="$1"
    local command_type="${2:-general}"
    
    # Check for command injection patterns
    local injection_patterns=(
        ";\s*(rm|cat|echo|touch|mkdir|cp|mv)\s"
        "\|\s*(rm|cat|echo|touch|mkdir|cp|mv)\s"
        "&&\s*(rm|cat|echo|touch|mkdir|cp|mv)\s"
        "\$\("
        "`"
        ">"
        "<"
        "|"
        "&"
        ";"
    )
    
    for pattern in "${injection_patterns[@]}"; do
        if [[ "$input" =~ $pattern ]]; then
            log "ERROR" "Input contains potentially dangerous pattern: $input"
            return 1
        fi
    done
    
    return 0
}

# Function: Validate numeric input
validate_numeric() {
    local input="$1"
    local min_val="${2:-0}"
    local max_val="${3:-2147483647}"
    
    # Check if it's a number
    if ! [[ "$input" =~ ^[0-9]+$ ]]; then
        log "ERROR" "Input must be numeric: $input"
        return 1
    fi
    
    # Range check
    if [[ "$input" -lt "$min_val" ]] || [[ "$input" -gt "$max_val" ]]; then
        log "ERROR" "Input out of range ($min_val-$max_val): $input"
        return 1
    fi
    
    return 0
}

# ============================================================================
# OS DETECTION AND PACKAGE MANAGEMENT
# ============================================================================

# Function: Detect operating system with broad server OS support
detect_os() {
    local os=""
    local version=""
    local distro_family=""
    local pkg_manager=""
    local init_system=""
    local arch=$(uname -m)
    
    log "DEBUG" "Detecting operating system and architecture: $arch"
    
    # Primary OS detection methods
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        os="$NAME"
        version="${VERSION_ID:-unknown}"
        log "DEBUG" "OS detection via /etc/os-release: $os $version"
    elif command -v lsb_release >/dev/null 2>&1; then
        os=$(lsb_release -si)
        version=$(lsb_release -sr)
        log "DEBUG" "OS detection via lsb_release: $os $version"
    elif [[ -f /etc/debian_version ]]; then
        os="Debian"
        version=$(cat /etc/debian_version)
        log "DEBUG" "OS detection via /etc/debian_version: $os $version"
    elif [[ -f /etc/redhat-release ]]; then
        os=$(sed 's/^\(.*\) release.*/\1/' /etc/redhat-release)
        version=$(grep -oE '[0-9]+(\.[0-9]+)*' /etc/redhat-release | head -1)
        log "DEBUG" "OS detection via /etc/redhat-release: $os $version"
    elif [[ -f /etc/centos-release ]]; then
        os="CentOS"
        version=$(grep -oE '[0-9]+(\.[0-9]+)*' /etc/centos-release | head -1)
    elif [[ -f /etc/alpine-release ]]; then
        os="Alpine Linux"
        version=$(cat /etc/alpine-release)
    elif [[ -f /etc/arch-release ]]; then
        os="Arch Linux"
        version="rolling"
    elif [[ -f /etc/gentoo-release ]]; then
        os="Gentoo"
        version=$(cat /etc/gentoo-release | cut -d' ' -f5)
    elif [[ -f /etc/SuSE-release ]] || [[ -f /etc/SUSE-brand ]]; then
        os="SUSE"
        version=$(grep VERSION /etc/SuSE-release 2>/dev/null | cut -d'=' -f2 | tr -d ' ' || echo "unknown")
    elif [[ $(uname -s) == "FreeBSD" ]]; then
        os="FreeBSD"
        version=$(freebsd-version | cut -d'-' -f1)
    elif [[ $(uname -s) == "OpenBSD" ]]; then
        os="OpenBSD"
        version=$(uname -r)
    elif [[ $(uname -s) == "NetBSD" ]]; then
        os="NetBSD"
        version=$(uname -r)
    elif [[ $(uname -s) == "DragonFly" ]]; then
        os="DragonFlyBSD"
        version=$(uname -r)
    elif [[ $(uname -s) == "Darwin" ]]; then
        os="macOS"
        version=$(sw_vers -productVersion 2>/dev/null || echo "unknown")
    else
        # Fallback detection
        os=$(uname -s)
        version=$(uname -r)
        log "WARN" "Using fallback OS detection: $os $version"
    fi
    
    # Determine distribution family, package manager, and init system
    case "$(echo "$os" | tr '[:upper:]' '[:lower:]')" in
        *ubuntu*|*debian*|*mint*|*kali*|*parrot*|*elementary*|*pop*)
            distro_family="debian"
            pkg_manager="apt-get"
            command -v apt >/dev/null 2>&1 && pkg_manager="apt"
            ;;
        *centos*|*rhel*|*red*hat*|*fedora*|*rocky*|*alma*|*oracle*|*scientific*)
            distro_family="redhat"
            pkg_manager="yum"
            command -v dnf >/dev/null 2>&1 && pkg_manager="dnf"
            ;;
        *suse*|*opensuse*|*sles*)
            distro_family="suse"
            pkg_manager="zypper"
            ;;
        *arch*|*manjaro*|*endeavour*)
            distro_family="arch"
            pkg_manager="pacman"
            ;;
        *alpine*)
            distro_family="alpine"
            pkg_manager="apk"
            ;;
        *gentoo*)
            distro_family="gentoo"
            pkg_manager="emerge"
            ;;
        *freebsd*)
            distro_family="freebsd"
            pkg_manager="pkg"
            ;;
        *openbsd*)
            distro_family="openbsd"
            pkg_manager="pkg_add"
            ;;
        *netbsd*)
            distro_family="netbsd"
            pkg_manager="pkgin"
            ;;
        *dragonfly*)
            distro_family="dragonfly"
            pkg_manager="pkg"
            ;;
        *macos*|*darwin*)
            distro_family="macos"
            pkg_manager="brew"
            ;;
        *)
            # Try to detect package managers for unknown distributions
            if command -v apt >/dev/null 2>&1 || command -v apt-get >/dev/null 2>&1; then
                distro_family="debian"
                pkg_manager="apt"
                command -v apt-get >/dev/null 2>&1 && pkg_manager="apt-get"
            elif command -v yum >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1; then
                distro_family="redhat"
                pkg_manager="yum"
                command -v dnf >/dev/null 2>&1 && pkg_manager="dnf"
            elif command -v zypper >/dev/null 2>&1; then
                distro_family="suse"
                pkg_manager="zypper"
            elif command -v pacman >/dev/null 2>&1; then
                distro_family="arch"
                pkg_manager="pacman"
            elif command -v apk >/dev/null 2>&1; then
                distro_family="alpine"
                pkg_manager="apk"
            elif command -v emerge >/dev/null 2>&1; then
                distro_family="gentoo"
                pkg_manager="emerge"
            elif command -v pkg >/dev/null 2>&1; then
                # Could be FreeBSD or DragonFly
                if [[ $(uname -s) == "FreeBSD" ]] || [[ $(uname -s) == "DragonFly" ]]; then
                    distro_family="bsd"
                    pkg_manager="pkg"
                else
                    distro_family="unknown"
                    pkg_manager="unknown"
                fi
            else
                log "WARN" "Unknown operating system: $os"
                distro_family="unknown"
                pkg_manager="unknown"
            fi
            ;;
    esac
    
    # Detect init system
    if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
        init_system="systemd"
    elif [[ -f /sbin/openrc ]] || [[ -d /etc/runlevels ]]; then
        init_system="openrc"
    elif [[ -f /etc/rc.conf ]] && [[ $(uname -s) =~ BSD ]]; then
        init_system="bsd_rc"
    elif [[ -d /etc/init.d ]] && [[ -f /sbin/service ]]; then
        init_system="sysv"
    elif [[ -d /Library/LaunchDaemons ]] && [[ $(uname -s) == "Darwin" ]]; then
        init_system="launchd"
    elif command -v rc-service >/dev/null 2>&1; then
        init_system="openrc"
    elif command -v service >/dev/null 2>&1; then
        init_system="sysv"
    else
        init_system="unknown"
        log "WARN" "Unknown init system"
    fi
    
    # Export variables
    export OS_NAME="$os"
    export OS_VERSION="$version"
    export DISTRO_FAMILY="$distro_family"
    export PKG_MANAGER="$pkg_manager"
    export INIT_SYSTEM="$init_system"
    export OS_ARCH="$arch"
    
    log "INFO" "Detected OS: $OS_NAME $OS_VERSION ($DISTRO_FAMILY family)"
    log "INFO" "Package Manager: $PKG_MANAGER | Init System: $INIT_SYSTEM | Architecture: $OS_ARCH"
    
    # Validate if this OS can run the script effectively
    case "$distro_family" in
        debian|redhat|suse|arch|alpine|gentoo)
            log "INFO" "Operating system is fully supported (Linux)"
            ;;
        freebsd|openbsd|netbsd|dragonfly)
            log "INFO" "Operating system is supported (BSD family)"
            log "WARN" "Some package names may differ on BSD systems"
            ;;
        macos)
            log "WARN" "macOS detected - limited support available"
            log "WARN" "This script is designed for Linux and BSD server environments"
            log "WARN" "Consider using Homebrew for dependencies"
            ;;
        unknown)
            log "WARN" "Unknown operating system - proceeding with best effort"
            log "WARN" "Manual dependency installation may be required"
            log "INFO" "Detected package manager: ${pkg_manager:-none}"
            ;;
    esac
    
    # Additional compatibility checks
    if [[ "$arch" =~ ^(arm|aarch64) ]]; then
        log "INFO" "ARM architecture detected: $arch"
        log "WARN" "Ensure certbot supports your ARM platform"
    elif [[ "$arch" =~ ^(i386|i686) ]]; then
        log "WARN" "32-bit architecture detected: $arch"
        log "WARN" "Modern certbot versions may not support 32-bit systems"
    fi
}

# Function: Comprehensive dependency management with validation and recovery
check_dependencies() {
    local deps_missing=false
    local required_commands=("curl" "openssl" "python3")
    local optional_commands=("host" "nslookup" "dig" "systemctl" "service" "crontab")
    local dns_cmd=""
    local missing_deps=()
    local failed_installs=()
    
    log "INFO" "Performing comprehensive dependency check..."
    
    # Pre-flight system checks
    perform_system_checks || {
        log "ERROR" "Critical system checks failed"
        return 1
    }
    
    # Check critical dependencies
    log "INFO" "Checking critical dependencies..."
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log "WARN" "Missing critical dependency: $cmd"
            missing_deps+=("$cmd")
            deps_missing=true
        else
            # Validate the command works
            if ! validate_command "$cmd"; then
                log "ERROR" "Command $cmd exists but is not functional"
                missing_deps+=("$cmd")
                deps_missing=true
            else
                log "DEBUG" "Validated dependency: $cmd"
            fi
        fi
    done
    
    # Check DNS lookup tools
    log "INFO" "Checking DNS resolution capabilities..."
    if command -v host >/dev/null 2>&1 && validate_dns_tool "host"; then
        dns_cmd="host"
    elif command -v nslookup >/dev/null 2>&1 && validate_dns_tool "nslookup"; then
        dns_cmd="nslookup"
    elif command -v dig >/dev/null 2>&1 && validate_dns_tool "dig"; then
        dns_cmd="dig"
    else
        log "WARN" "No functional DNS lookup tool found"
        missing_deps+=("dns-tools")
        deps_missing=true
    fi
    
    # Check optional but recommended tools
    log "INFO" "Checking optional dependencies..."
    for cmd in "${optional_commands[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            log "DEBUG" "Found optional tool: $cmd"
        else
            log "DEBUG" "Optional tool not available: $cmd"
        fi
    done
    
    # Install missing dependencies with retry logic
    if [[ "$deps_missing" == "true" ]]; then
        log "INFO" "Installing missing dependencies: ${missing_deps[*]}"
        
        if ! install_dependencies_with_retry "${missing_deps[@]}"; then
            log "ERROR" "Failed to install critical dependencies"
            log "ERROR" "Manual intervention required for: ${failed_installs[*]}"
            provide_manual_install_instructions "${failed_installs[@]}"
            return 1
        fi
        
        # Re-verify all dependencies after installation
        log "INFO" "Re-verifying dependencies after installation..."
        for cmd in "${required_commands[@]}"; do
            if ! command -v "$cmd" >/dev/null 2>&1; then
                log "ERROR" "Dependency still missing after installation: $cmd"
                failed_installs+=("$cmd")
            elif ! validate_command "$cmd"; then
                log "ERROR" "Dependency installed but not functional: $cmd"
                failed_installs+=("$cmd")
            fi
        done
        
        if [[ ${#failed_installs[@]} -gt 0 ]]; then
            log "ERROR" "Some dependencies failed to install or validate: ${failed_installs[*]}"
            return 1
        fi
        
        log "INFO" "All dependencies successfully installed and validated"
    else
        log "INFO" "All dependencies are already available and validated"
    fi
    
    # Export DNS command for later use
    export DNS_CMD="${dns_cmd:-host}"
    
    # Final system readiness check
    perform_readiness_check || {
        log "ERROR" "System readiness check failed"
        return 1
    }
    
    log "INFO" "Dependency check completed successfully"
    return 0
}

# Function: Pre-flight system checks
perform_system_checks() {
    log "DEBUG" "Performing pre-flight system checks..."
    
    # Check disk space
    local available_space=$(df /tmp 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
    if [[ "$available_space" -lt 100000 ]]; then  # Less than ~100MB
        log "WARN" "Low disk space in /tmp: ${available_space}KB available"
        log "WARN" "Certificate operations may fail"
    fi
    
    # Check memory
    if [[ -f /proc/meminfo ]]; then
        local available_mem=$(awk '/MemAvailable/ {print $2}' /proc/meminfo 2>/dev/null || echo "999999")
        if [[ "$available_mem" -lt 100000 ]]; then  # Less than ~100MB
            log "WARN" "Low available memory: ${available_mem}KB"
        fi
    fi
    
    # Check network connectivity
    if ! check_network_connectivity; then
        log "ERROR" "Network connectivity check failed"
        return 1
    fi
    
    # Check permissions
    if [[ $EUID -eq 0 ]]; then
        # Check if we can write to system directories
        for dir in "/etc" "/var/log" "/usr/local/bin"; do
            if [[ ! -w "$dir" ]]; then
                log "WARN" "Cannot write to system directory: $dir"
            fi
        done
    fi
    
    return 0
}

# Function: Check network connectivity
check_network_connectivity() {
    log "DEBUG" "Checking network connectivity..."
    
    # Test DNS resolution
    if command -v nslookup >/dev/null 2>&1; then
        if ! nslookup google.com >/dev/null 2>&1; then
            log "WARN" "DNS resolution test failed"
            return 1
        fi
    fi
    
    # Test HTTPS connectivity
    if command -v curl >/dev/null 2>&1; then
        if ! curl -s --connect-timeout 10 --max-time 15 https://www.google.com >/dev/null 2>&1; then
            log "WARN" "HTTPS connectivity test failed"
            return 1
        fi
    fi
    
    log "DEBUG" "Network connectivity verified"
    return 0
}

# Function: Validate command functionality
validate_command() {
    local cmd="$1"
    
    case "$cmd" in
        curl)
            curl --version >/dev/null 2>&1 && curl -s --connect-timeout 5 https://httpbin.org/get >/dev/null 2>&1
            ;;
        openssl)
            openssl version >/dev/null 2>&1
            ;;
        python3)
            python3 --version >/dev/null 2>&1 && python3 -c "import sys; print(sys.version)" >/dev/null 2>&1
            ;;
        *)
            # Generic validation - just check if command runs
            "$cmd" --version >/dev/null 2>&1 || "$cmd" -V >/dev/null 2>&1 || "$cmd" --help >/dev/null 2>&1
            ;;
    esac
}

# Function: Validate DNS tools
validate_dns_tool() {
    local tool="$1"
    
    case "$tool" in
        host)
            host google.com >/dev/null 2>&1
            ;;
        nslookup)
            nslookup google.com >/dev/null 2>&1
            ;;
        dig)
            dig google.com >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

# Function: Install dependencies with retry logic
install_dependencies_with_retry() {
    local deps=("$@")
    local max_retries=3
    local retry_count=0
    
    while [[ $retry_count -lt $max_retries ]]; do
        log "INFO" "Installation attempt $((retry_count + 1))/$max_retries"
        
        if install_dependencies_for_platform "${deps[@]}"; then
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        if [[ $retry_count -lt $max_retries ]]; then
            log "WARN" "Installation failed, retrying in 5 seconds..."
            sleep 5
        fi
    done
    
    log "ERROR" "Failed to install dependencies after $max_retries attempts"
    return 1
}

# Function: Platform-specific dependency installation
install_dependencies_for_platform() {
    local deps=("$@")
    
    case "$DISTRO_FAMILY" in
        debian)
            log "INFO" "Installing dependencies on Debian/Ubuntu..."
            $PKG_MANAGER update && \
            $PKG_MANAGER install -y curl openssl dnsutils python3 python3-pip ca-certificates
            ;;
        redhat)
            log "INFO" "Installing dependencies on RedHat/CentOS/Fedora..."
            if [[ "$PKG_MANAGER" == "dnf" ]]; then
                $PKG_MANAGER install -y curl openssl bind-utils python3 python3-pip ca-certificates
            else
                $PKG_MANAGER install -y curl openssl bind-utils python3 python3-pip ca-certificates
            fi
            ;;
        suse)
            log "INFO" "Installing dependencies on SUSE/openSUSE..."
            zypper refresh && \
            zypper install -y curl openssl bind-utils python3 python3-pip ca-certificates
            ;;
        arch)
            log "INFO" "Installing dependencies on Arch Linux..."
            pacman -Sy --noconfirm curl openssl bind-tools python python-pip ca-certificates
            ;;
        alpine)
            log "INFO" "Installing dependencies on Alpine Linux..."
            apk update && \
            apk add curl openssl bind-tools python3 py3-pip ca-certificates
            ;;
        gentoo)
            log "INFO" "Installing dependencies on Gentoo..."
            emerge --sync --quiet && \
            emerge -uDN net-misc/curl dev-libs/openssl net-dns/bind-tools dev-lang/python dev-python/pip app-misc/ca-certificates
            ;;
        freebsd)
            log "INFO" "Installing dependencies on FreeBSD..."
            pkg update && \
            pkg install -y curl openssl bind-tools python3 py39-pip ca_root_nss
            ;;
        openbsd)
            log "INFO" "Installing dependencies on OpenBSD..."
            pkg_add curl openssl python3 py3-pip
            ;;
        netbsd)
            log "INFO" "Installing dependencies on NetBSD..."
            pkgin update && \
            pkgin install -y curl openssl bind-utils python39 py39-pip mozilla-rootcerts
            ;;
        dragonfly)
            log "INFO" "Installing dependencies on DragonFlyBSD..."
            pkg update && \
            pkg install -y curl openssl bind-tools python3 py39-pip ca_root_nss
            ;;
        macos)
            log "INFO" "Installing dependencies on macOS via Homebrew..."
            if ! command -v brew >/dev/null 2>&1; then
                log "ERROR" "Homebrew not found. Please install Homebrew first:"
                log "ERROR" "/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
                return 1
            fi
            brew update && \
            brew install curl openssl bind python3 ca-certificates
            ;;
        *)
            log "ERROR" "Unknown distribution family: $DISTRO_FAMILY"
            return 1
            ;;
    esac
}

# Function: Provide manual installation instructions
provide_manual_install_instructions() {
    local failed_deps=("$@")
    
    log "ERROR" "Manual installation required for: ${failed_deps[*]}"
    log "ERROR" ""
    log "ERROR" "Please install the following packages manually:"
    
    case "$DISTRO_FAMILY" in
        debian)
            log "ERROR" "  sudo apt update && sudo apt install -y curl openssl dnsutils python3 python3-pip ca-certificates"
            ;;
        redhat)
            log "ERROR" "  sudo yum install -y curl openssl bind-utils python3 python3-pip ca-certificates"
            log "ERROR" "  # OR for newer systems:"
            log "ERROR" "  sudo dnf install -y curl openssl bind-utils python3 python3-pip ca-certificates"
            ;;
        *)
            log "ERROR" "  curl (HTTP client)"
            log "ERROR" "  openssl (Cryptographic library)"
            log "ERROR" "  DNS tools (host/nslookup/dig)"
            log "ERROR" "  python3 (Python interpreter)"
            log "ERROR" "  python3-pip (Python package manager)"
            log "ERROR" "  ca-certificates (Certificate authorities)"
            ;;
    esac
}

# Function: Final readiness check
perform_readiness_check() {
    log "DEBUG" "Performing final readiness check..."
    
    # Check that all critical commands are functional
    local critical_tests=(
        "curl --version"
        "openssl version"
        "python3 --version"
    )
    
    for test in "${critical_tests[@]}"; do
        if ! eval "$test" >/dev/null 2>&1; then
            log "ERROR" "Readiness check failed: $test"
            return 1
        fi
    done
    
    # Test network functionality
    if ! curl -s --connect-timeout 5 --max-time 10 https://httpbin.org/get >/dev/null 2>&1; then
        log "WARN" "Network readiness check failed - some features may not work"
    fi
    
    log "DEBUG" "System readiness check passed"
    return 0
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

# Function: Install certbot with cross-platform support
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
        suse)
            zypper remove -y python3-certbot 2>/dev/null || true
            ;;
        arch)
            pacman -Rns --noconfirm certbot 2>/dev/null || true
            ;;
        alpine)
            apk del certbot 2>/dev/null || true
            ;;
        freebsd|dragonfly)
            pkg delete -y py39-certbot 2>/dev/null || true
            ;;
        openbsd)
            pkg_delete certbot 2>/dev/null || true
            ;;
        netbsd)
            pkgin remove py39-certbot 2>/dev/null || true
            ;;
    esac
    
    # Choose installation method based on OS
    case "$DISTRO_FAMILY" in
        debian|redhat|suse)
            # Try snap first for systemd-based distributions
            if command -v snap >/dev/null 2>&1 && [[ "$INIT_SYSTEM" == "systemd" ]]; then
                install_certbot_snap
            else
                install_certbot_native
            fi
            ;;
        arch)
            log "INFO" "Installing certbot via pacman..."
            pacman -Sy --noconfirm certbot
            ;;
        alpine)
            log "INFO" "Installing certbot via apk..."
            apk add certbot
            ;;
        freebsd|dragonfly)
            log "INFO" "Installing certbot via pkg..."
            pkg install -y py39-certbot
            ;;
        openbsd)
            log "INFO" "Installing certbot via pkg_add..."
            pkg_add py3-certbot
            ;;
        netbsd)
            log "INFO" "Installing certbot via pkgin..."
            pkgin install -y py39-certbot
            ;;
        gentoo)
            log "INFO" "Installing certbot via emerge..."
            emerge -uDN app-crypt/certbot
            ;;
        macos)
            log "INFO" "Installing certbot via Homebrew..."
            brew install certbot
            ;;
        *)
            log "WARN" "Attempting pip installation for unknown distribution..."
            install_certbot_pip
            ;;
    esac
    
    # Verify installation and version
    if command -v certbot >/dev/null 2>&1; then
        if check_certbot_version; then
            log "INFO" "Certbot installation completed successfully"
            log "AUDIT" "Certbot with profile support installed"
        else
            log "ERROR" "Installed certbot version doesn't meet requirements"
            log "INFO" "Attempting pip upgrade..."
            install_certbot_pip
        fi
    else
        log "ERROR" "Certbot installation failed, trying pip installation..."
        install_certbot_pip
    fi
}

# Function: Install certbot via snap
install_certbot_snap() {
    log "INFO" "Installing certbot via snap..."
    
    # Check if snapd is available
    if ! command -v snap >/dev/null 2>&1; then
        log "INFO" "Installing snap package manager..."
        
        case "$DISTRO_FAMILY" in
            debian)
                $PKG_MANAGER update
                $PKG_MANAGER install -y snapd
                ;;
            redhat)
                $PKG_MANAGER install -y snapd
                ;;
            suse)
                zypper install -y snapd
                ;;
        esac
        
        # Enable snapd service based on init system
        case "$INIT_SYSTEM" in
            systemd)
                systemctl enable --now snapd.socket
                systemctl enable --now snapd
                ;;
            openrc)
                rc-service snapd start
                rc-update add snapd default
                ;;
            sysv)
                service snapd start
                chkconfig snapd on 2>/dev/null || true
                ;;
        esac
        
        # Wait for snap to be ready
        sleep 5
    fi
    
    # Install certbot
    if snap install --classic certbot; then
        # Create symlink in standard location
        ln -sf /snap/bin/certbot /usr/bin/certbot 2>/dev/null || true
        ln -sf /snap/bin/certbot /usr/local/bin/certbot 2>/dev/null || true
        log "INFO" "Certbot installed successfully via snap"
    else
        log "WARN" "Snap installation failed, trying native packages"
        install_certbot_native
    fi
}

# Function: Install certbot via native packages
install_certbot_native() {
    log "INFO" "Installing certbot via native package manager..."
    
    case "$DISTRO_FAMILY" in
        debian)
            $PKG_MANAGER update
            $PKG_MANAGER install -y python3-certbot
            ;;
        redhat)
            # Enable EPEL for CentOS/RHEL
            if [[ "$OS_NAME" =~ (CentOS|Red Hat|Rocky|AlmaLinux) ]]; then
                $PKG_MANAGER install -y epel-release
            fi
            $PKG_MANAGER install -y python3-certbot
            ;;
        suse)
            zypper install -y python3-certbot
            ;;
    esac
}

# Function: Install certbot via pip
install_certbot_pip() {
    log "INFO" "Installing certbot via pip..."
    
    # Ensure pip is available
    if ! command -v pip3 >/dev/null 2>&1 && ! command -v pip >/dev/null 2>&1; then
        log "ERROR" "pip is not available. Please install python3-pip first."
        return 1
    fi
    
    # Use pip3 if available, otherwise pip
    local pip_cmd="pip3"
    command -v pip3 >/dev/null 2>&1 || pip_cmd="pip"
    
    # Install certbot
    $pip_cmd install --upgrade certbot
    
    # Ensure certbot is in PATH
    local python_bin_dir
    if command -v python3 >/dev/null 2>&1; then
        python_bin_dir=$(python3 -c "import site; print(site.USER_BASE + '/bin')" 2>/dev/null || echo "/usr/local/bin")
    else
        python_bin_dir="/usr/local/bin"
    fi
    
    # Create symlinks if needed
    if [[ -f "$python_bin_dir/certbot" ]]; then
        ln -sf "$python_bin_dir/certbot" /usr/local/bin/certbot 2>/dev/null || true
        ln -sf "$python_bin_dir/certbot" /usr/bin/certbot 2>/dev/null || true
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

# Function: Detect web server with cross-platform support
detect_web_server() {
    local web_server=""
    local user_preference="${RENEWAL_WEB_SERVER:-auto}"
    
    # If user has specified a preference other than auto
    if [[ "$user_preference" != "auto" ]]; then
        case "$user_preference" in
            nginx|apache|standalone)
                web_server="$user_preference"
                log "INFO" "Using user-configured web server: $web_server"
                ;;
            *)
                log "WARN" "Invalid web server preference '$user_preference', falling back to auto-detection"
                user_preference="auto"
                ;;
        esac
    fi
    
    # Auto-detection if no valid preference set
    if [[ "$user_preference" == "auto" ]]; then
        # Check based on init system and OS
        case "$INIT_SYSTEM" in
            systemd)
                if systemctl is-active --quiet nginx 2>/dev/null; then
                    web_server="nginx"
                    log "INFO" "Detected nginx web server (systemd)"
                elif systemctl is-active --quiet apache2 2>/dev/null || systemctl is-active --quiet httpd 2>/dev/null; then
                    web_server="apache"
                    log "INFO" "Detected Apache web server (systemd)"
                fi
                ;;
            openrc)
                if rc-service nginx status 2>/dev/null | grep -q "started"; then
                    web_server="nginx"
                    log "INFO" "Detected nginx web server (OpenRC)"
                elif rc-service apache2 status 2>/dev/null | grep -q "started" || rc-service httpd status 2>/dev/null | grep -q "started"; then
                    web_server="apache"
                    log "INFO" "Detected Apache web server (OpenRC)"
                fi
                ;;
            sysv)
                if service nginx status 2>/dev/null | grep -q "running"; then
                    web_server="nginx"
                    log "INFO" "Detected nginx web server (SysV)"
                elif service apache2 status 2>/dev/null | grep -q "running" || service httpd status 2>/dev/null | grep -q "running"; then
                    web_server="apache"
                    log "INFO" "Detected Apache web server (SysV)"
                fi
                ;;
            bsd_rc)
                # BSD-style service detection
                if [[ "$DISTRO_FAMILY" =~ (freebsd|openbsd|netbsd|dragonfly) ]]; then
                    if pgrep -f nginx >/dev/null 2>&1; then
                        web_server="nginx"
                        log "INFO" "Detected nginx web server (BSD)"
                    elif pgrep -f "httpd|apache" >/dev/null 2>&1; then
                        web_server="apache"
                        log "INFO" "Detected Apache web server (BSD)"
                    fi
                fi
                ;;
            launchd)
                # macOS service detection
                if launchctl list | grep -q nginx 2>/dev/null; then
                    web_server="nginx"
                    log "INFO" "Detected nginx web server (macOS)"
                elif launchctl list | grep -q httpd 2>/dev/null; then
                    web_server="apache"
                    log "INFO" "Detected Apache web server (macOS)"
                fi
                ;;
            *)
                # Fallback: process-based detection
                if pgrep -f nginx >/dev/null 2>&1; then
                    web_server="nginx"
                    log "INFO" "Detected nginx web server (process check)"
                elif pgrep -f "httpd|apache" >/dev/null 2>&1; then
                    web_server="apache"
                    log "INFO" "Detected Apache web server (process check)"
                fi
                ;;
        esac
        
        # If no web server detected, use standalone
        if [[ -z "$web_server" ]]; then
            log "WARN" "No active web server detected"
            log "WARN" "Using standalone mode - certbot will start its own web server"
            web_server="standalone"
        fi
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
    local key_size="${USER_KEY_SIZE:-$DEFAULT_KEY_SIZE}"
    certbot_cmd+=(
        -d "$ip_address"
        --email "$email"
        --agree-tos
        --non-interactive
        --staging  # IP certs only work in staging for now
        --profile "$REQUIRED_PROFILE"  # Must use shortlived profile
        --rsa-key-size "$key_size"
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
    local deploy_hook="$RENEWAL_DEPLOY_HOOK"
    [[ -n "${DEPLOY_HOOK_CUSTOM:-}" ]] && deploy_hook="$DEPLOY_HOOK_CUSTOM; $deploy_hook"
    renew_cmd+=(--deploy-hook "$deploy_hook")
    
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

# Function: Setup automatic renewal with cross-platform support
setup_auto_renewal() {
    log "INFO" "Setting up automatic renewal for short-lived IP certificates..."
    log "AUDIT" "Auto-renewal configuration initiated by: ${SUDO_USER:-root}"
    
    local deploy_hook="$RENEWAL_DEPLOY_HOOK"
    [[ -n "${DEPLOY_HOOK_CUSTOM:-}" ]] && deploy_hook="$DEPLOY_HOOK_CUSTOM; $deploy_hook"
    
    # Find certbot path
    local certbot_path=$(command -v certbot)
    [[ -z "$certbot_path" ]] && certbot_path="/usr/bin/certbot"
    
    # Setup based on init system
    case "$INIT_SYSTEM" in
        systemd)
            setup_systemd_renewal "$deploy_hook" "$certbot_path"
            ;;
        openrc)
            setup_openrc_renewal "$deploy_hook" "$certbot_path"
            ;;
        bsd_rc)
            setup_bsd_renewal "$deploy_hook" "$certbot_path"
            ;;
        sysv)
            setup_sysv_renewal "$deploy_hook" "$certbot_path"
            ;;
        launchd)
            setup_launchd_renewal "$deploy_hook" "$certbot_path"
            ;;
        *)
            log "WARN" "Unknown init system, setting up cron-only renewal"
            setup_cron_renewal "$deploy_hook" "$certbot_path"
            ;;
    esac
    
    log "INFO" "Automatic renewal configured successfully"
    
    # Show configuration summary
    echo -e "\n${GREEN}${CHECKMARK} Automatic Renewal Configured:${NC}"
    echo -e "  • Init System: ${WHITE}$INIT_SYSTEM${NC}"
    echo -e "  • Schedule: ${YELLOW}Every 4 hours${NC} (critical for 6-day certs)"
    echo -e "  • Renewal Log: ${WHITE}$RENEWAL_LOG${NC}"
    
    # Create first renewal check
    log "INFO" "Running initial renewal check..."
    renew_ip_certificates
}

# Function: Setup systemd-based renewal
setup_systemd_renewal() {
    local deploy_hook="$1"
    local certbot_path="$2"
    
    log "INFO" "Creating systemd timer for aggressive renewal schedule..."
    
    # Create service unit
    cat > /etc/systemd/system/certbot-ip-renew.service << EOF
[Unit]
Description=Let's Encrypt IP Certificate Renewal
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$certbot_path renew --non-interactive --deploy-hook "$deploy_hook"
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
    
    # Also setup cron as fallback
    setup_cron_renewal "$deploy_hook" "$certbot_path"
}

# Function: Setup OpenRC-based renewal
setup_openrc_renewal() {
    local deploy_hook="$1"
    local certbot_path="$2"
    
    log "INFO" "Creating OpenRC service for renewal..."
    
    # Create OpenRC service script
    cat > /etc/init.d/certbot-ip-renew << 'EOF'
#!/sbin/openrc-run

name="certbot-ip-renew"
description="Let's Encrypt IP Certificate Renewal"

depend() {
    need net
    after networking
}

start() {
    ebegin "Starting Let's Encrypt IP certificate renewal"
    $certbot_path renew --non-interactive --deploy-hook "$deploy_hook" >> $RENEWAL_LOG 2>&1
    eend $?
}
EOF

    # Make executable and add to default runlevel
    chmod +x /etc/init.d/certbot-ip-renew
    rc-update add certbot-ip-renew default
    
    log "INFO" "OpenRC service configured"
    
    # Setup cron for scheduling
    setup_cron_renewal "$deploy_hook" "$certbot_path"
}

# Function: Setup BSD RC-based renewal
setup_bsd_renewal() {
    local deploy_hook="$1"
    local certbot_path="$2"
    
    log "INFO" "Creating BSD RC script for renewal..."
    
    # Add to rc.conf
    echo 'certbot_ip_renew_enable="YES"' >> /etc/rc.conf
    
    # Create RC script
    cat > /etc/rc.d/certbot_ip_renew << EOF
#!/bin/sh

# PROVIDE: certbot_ip_renew
# REQUIRE: NETWORKING
# KEYWORD: shutdown

. /etc/rc.subr

name="certbot_ip_renew"
rcvar="certbot_ip_renew_enable"
command="$certbot_path"
command_args="renew --non-interactive --deploy-hook '$deploy_hook'"

load_rc_config \$name
run_rc_command "\$1"
EOF

    chmod +x /etc/rc.d/certbot_ip_renew
    
    log "INFO" "BSD RC script configured"
    
    # Setup cron for scheduling
    setup_cron_renewal "$deploy_hook" "$certbot_path"
}

# Function: Setup SysV-based renewal
setup_sysv_renewal() {
    local deploy_hook="$1"
    local certbot_path="$2"
    
    log "INFO" "Creating SysV init script for renewal..."
    
    # Create SysV script
    cat > /etc/init.d/certbot-ip-renew << EOF
#!/bin/bash
# certbot-ip-renew    Let's Encrypt IP Certificate Renewal
# chkconfig: 35 80 20
# description: Let's Encrypt IP Certificate Renewal Service

. /etc/rc.d/init.d/functions

USER="root"
DAEMON="certbot-ip-renew"
ROOT_DIR="/var/lib/certbot"

SERVER="\$ROOT_DIR/\$DAEMON"
LOCK_FILE="/var/lock/subsys/\$DAEMON"

do_start() {
    if [ ! -f "\$LOCK_FILE" ] ; then
        echo -n "Starting \$DAEMON: "
        runuser -l "\$USER" -c "\$SERVER" && echo_success || echo_failure
        RETVAL=\$?
        echo
        [ \$RETVAL -eq 0 ] && touch \$LOCK_FILE
    else
        echo "\$DAEMON is locked."
    fi
}
do_stop() {
    echo -n "Shutting down \$DAEMON: "
    pid=\`ps -aefw | grep "\$DAEMON" | grep -v " grep " | awk '{print \$2}'\`
    kill -9 \$pid > /dev/null 2>&1
    [ \$? -eq 0 ] && echo_success || echo_failure
    RETVAL=\$?
    echo
    [ \$RETVAL -eq 0 ] && rm -f \$LOCK_FILE
}

case "\$1" in
    start)
        do_start
        ;;
    stop)
        do_stop
        ;;
    restart)
        do_stop
        do_start
        ;;
    *)
        echo "Usage: \$0 {start|stop|restart}"
        RETVAL=1
esac

exit \$RETVAL
EOF

    chmod +x /etc/init.d/certbot-ip-renew
    chkconfig --add certbot-ip-renew
    chkconfig certbot-ip-renew on
    
    log "INFO" "SysV init script configured"
    
    # Setup cron for scheduling
    setup_cron_renewal "$deploy_hook" "$certbot_path"
}

# Function: Setup macOS launchd-based renewal
setup_launchd_renewal() {
    local deploy_hook="$1"
    local certbot_path="$2"
    
    log "INFO" "Creating macOS launchd plist for renewal..."
    
    # Create launchd plist
    cat > /Library/LaunchDaemons/com.letsencrypt.certbot-ip-renew.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.letsencrypt.certbot-ip-renew</string>
    <key>ProgramArguments</key>
    <array>
        <string>$certbot_path</string>
        <string>renew</string>
        <string>--non-interactive</string>
        <string>--deploy-hook</string>
        <string>$deploy_hook</string>
    </array>
    <key>StartInterval</key>
    <integer>14400</integer>
    <key>StandardOutPath</key>
    <string>$RENEWAL_LOG</string>
    <key>StandardErrorPath</key>
    <string>$RENEWAL_LOG</string>
</dict>
</plist>
EOF

    # Load the plist
    launchctl load /Library/LaunchDaemons/com.letsencrypt.certbot-ip-renew.plist
    
    log "INFO" "macOS launchd service configured"
}

# Function: Setup cron-based renewal (fallback)
setup_cron_renewal() {
    local deploy_hook="$1"
    local certbot_path="$2"
    
    log "INFO" "Creating cron job for renewal..."
    
    # Determine cron location and service name based on OS
    local cron_dir="/etc/cron.d"
    local cron_service="cron"
    
    case "$DISTRO_FAMILY" in
        redhat|suse|arch)
            cron_service="crond"
            ;;
        alpine)
            cron_service="crond"
            ;;
        freebsd|dragonfly)
            cron_dir="/usr/local/etc/cron.d"
            cron_service="cron"
            ;;
        openbsd|netbsd)
            # Use root crontab instead
            (crontab -l 2>/dev/null; echo "$RENEWAL_INTERVAL root sleep \$((RANDOM \% 300)); $certbot_path renew --non-interactive --deploy-hook '$deploy_hook' >> $RENEWAL_LOG 2>&1") | crontab -
            return 0
            ;;
    esac
    
    # Create cron file
    cat > "$cron_dir/certbot-ip-renew" << EOF
# Let's Encrypt IP Certificate Renewal (6-day certificates)
# Runs every 4 hours with random delay
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

$RENEWAL_INTERVAL root sleep \$((RANDOM \% 300)); $certbot_path renew --non-interactive --deploy-hook "$deploy_hook" >> $RENEWAL_LOG 2>&1

# Also check at system startup
@reboot root sleep 60; $certbot_path renew --non-interactive >> $RENEWAL_LOG 2>&1
EOF

    chmod 644 "$cron_dir/certbot-ip-renew"
    
    # Restart cron service based on init system
    case "$INIT_SYSTEM" in
        systemd)
            systemctl restart "$cron_service" 2>/dev/null || true
            ;;
        openrc)
            rc-service "$cron_service" restart 2>/dev/null || true
            ;;
        sysv)
            service "$cron_service" restart 2>/dev/null || true
            ;;
        bsd_rc)
            /etc/rc.d/"$cron_service" restart 2>/dev/null || true
            ;;
    esac
    
    log "INFO" "Cron-based renewal configured"
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

# Function: Show configuration
show_config() {
    echo -e "\n${CYAN}${INFO} Current Configuration${NC}"
    
    if [[ -f "$CONFIG_FILE" ]]; then
        load_config
        echo -e "\n${GREEN}Configuration loaded from: $CONFIG_FILE${NC}"
        echo -e "\n${WHITE}User Preferences:${NC}"
        echo -e "  ${CYAN}Email:${NC} ${USER_EMAIL:-Not configured}"
        echo -e "  ${CYAN}Webroot:${NC} ${USER_WEBROOT:-$DEFAULT_WEBROOT}"
        echo -e "  ${CYAN}Key Size:${NC} ${USER_KEY_SIZE:-$DEFAULT_KEY_SIZE} bits"
        
        echo -e "\n${WHITE}Renewal Settings:${NC}"
        echo -e "  ${CYAN}Auto-Renewal:${NC} ${AUTO_RENEWAL_ENABLED:-true}"
        echo -e "  ${CYAN}Notifications:${NC} ${RENEWAL_NOTIFICATIONS:-true}"
        echo -e "  ${CYAN}Web Server:${NC} ${RENEWAL_WEB_SERVER:-auto}"
        
        echo -e "\n${WHITE}Logging Settings:${NC}"
        echo -e "  ${CYAN}Log Level:${NC} ${LOG_LEVEL:-INFO}"
        echo -e "  ${CYAN}Log Retention:${NC} ${LOG_RETENTION_DAYS:-30} days"
        
        echo -e "\n${WHITE}Advanced Settings:${NC}"
        echo -e "  ${CYAN}Challenge Type:${NC} ${CHALLENGE_TYPE:-http-01}"
        [[ -n "${PREFERRED_CHAIN:-}" ]] && echo -e "  ${CYAN}Preferred Chain:${NC} $PREFERRED_CHAIN"
        [[ -n "${DEPLOY_HOOK_CUSTOM:-}" ]] && echo -e "  ${CYAN}Custom Hook:${NC} $DEPLOY_HOOK_CUSTOM"
        
        echo -e "\n${YELLOW}To reconfigure: $0 --configure${NC}"
    else
        echo -e "\n${YELLOW}No configuration file found.${NC}"
        echo -e "${YELLOW}Run: $0 --configure to create one${NC}"
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
  • Interactive configuration wizard
  • Persistent user preferences
  • Mandatory short-lived certificates (6-day validity)
  • Automatic renewal every 4 hours
  • Public IP validation
  • HTTP-01 challenge support

For help: $0 --help
For setup: $0 --setup
EOF
}

# Function: Generate comprehensive status report
generate_status_report() {
    echo -e "\n${CYAN}${INFO} LetsEncrypt IP SSL Manager - System Status${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Script information
    echo -e "\n${WHITE}Script Information:${NC}"
    echo -e "  Version: ${GREEN}$SCRIPT_VERSION${NC}"
    echo -e "  PID: ${GREEN}$$${NC}"
    echo -e "  User: ${GREEN}${USER:-$(whoami)}${NC}"
    echo -e "  Started: ${GREEN}$(date)${NC}"
    
    # System information
    echo -e "\n${WHITE}System Information:${NC}"
    echo -e "  OS: ${GREEN}${OS_NAME:-Unknown} ${OS_VERSION:-}${NC}"
    echo -e "  Distribution Family: ${GREEN}${DISTRO_FAMILY:-Unknown}${NC}"
    echo -e "  Architecture: ${GREEN}${OS_ARCH:-$(uname -m)}${NC}"
    echo -e "  Package Manager: ${GREEN}${PKG_MANAGER:-Unknown}${NC}"
    echo -e "  Init System: ${GREEN}${INIT_SYSTEM:-Unknown}${NC}"
    
    # Dependencies status
    echo -e "\n${WHITE}Dependencies Status:${NC}"
    local deps=("curl" "openssl" "python3" "certbot")
    for dep in "${deps[@]}"; do
        if command -v "$dep" >/dev/null 2>&1; then
            local version=$($dep --version 2>&1 | head -1 | cut -d' ' -f2-3 || echo "unknown")
            echo -e "  $dep: ${GREEN}✓ ($version)${NC}"
        else
            echo -e "  $dep: ${RED}✗ Not found${NC}"
        fi
    done
    
    # Configuration status
    echo -e "\n${WHITE}Configuration Status:${NC}"
    if [[ -f "$CONFIG_FILE" ]]; then
        echo -e "  Config File: ${GREEN}✓ Present${NC}"
        load_config
        echo -e "  Email: ${GREEN}${USER_EMAIL:-Not configured}${NC}"
        echo -e "  Webroot: ${GREEN}${USER_WEBROOT:-$DEFAULT_WEBROOT}${NC}"
        echo -e "  Auto-Renewal: ${GREEN}${AUTO_RENEWAL_ENABLED:-true}${NC}"
    else
        echo -e "  Config File: ${RED}✗ Missing${NC}"
    fi
    
    # Certificate status
    echo -e "\n${WHITE}Certificate Status:${NC}"
    if command -v certbot >/dev/null 2>&1; then
        local cert_count=$(certbot certificates 2>/dev/null | grep -c "Certificate Name:" || echo "0")
        echo -e "  Total Certificates: ${GREEN}$cert_count${NC}"
        
        if [[ $cert_count -gt 0 ]]; then
            # Check for expiring certificates
            local expiring=$(certbot certificates 2>/dev/null | grep -B5 -A1 "INVALID\|expir" | grep -c "Certificate Name:" || echo "0")
            if [[ $expiring -gt 0 ]]; then
                echo -e "  Expiring Soon: ${RED}$expiring${NC}"
            else
                echo -e "  Expiring Soon: ${GREEN}0${NC}"
            fi
        fi
    else
        echo -e "  Certbot: ${RED}✗ Not available${NC}"
    fi
    
    # Service status
    echo -e "\n${WHITE}Service Status:${NC}"
    case "${INIT_SYSTEM:-unknown}" in
        systemd)
            if systemctl is-active --quiet certbot-ip-renew.timer 2>/dev/null; then
                echo -e "  Renewal Timer: ${GREEN}✓ Active${NC}"
                local next_run=$(systemctl show certbot-ip-renew.timer --property=NextElapseUSecRealtime --value 2>/dev/null)
                [[ -n "$next_run" ]] && echo -e "  Next Renewal: ${GREEN}$next_run${NC}"
            else
                echo -e "  Renewal Timer: ${RED}✗ Inactive${NC}"
            fi
            ;;
        *)
            if [[ -f "/etc/cron.d/certbot-ip-renew" ]]; then
                echo -e "  Cron Job: ${GREEN}✓ Present${NC}"
            else
                echo -e "  Cron Job: ${RED}✗ Missing${NC}"
            fi
            ;;
    esac
    
    # Log status
    echo -e "\n${WHITE}Log Status:${NC}"
    local log_files=("$LOG_FILE" "$ERROR_LOG" "$AUDIT_LOG" "$RENEWAL_LOG")
    for log_file in "${log_files[@]}"; do
        local log_name=$(basename "$log_file")
        if [[ -f "$log_file" ]]; then
            local size=$(du -h "$log_file" 2>/dev/null | cut -f1)
            local lines=$(wc -l < "$log_file" 2>/dev/null || echo "0")
            echo -e "  $log_name: ${GREEN}✓ ($size, $lines lines)${NC}"
        else
            echo -e "  $log_name: ${RED}✗ Missing${NC}"
        fi
    done
    
    # Network status
    echo -e "\n${WHITE}Network Status:${NC}"
    if check_network_connectivity >/dev/null 2>&1; then
        echo -e "  Connectivity: ${GREEN}✓ Online${NC}"
    else
        echo -e "  Connectivity: ${RED}✗ Issues detected${NC}"
    fi
    
    # Recent activity
    echo -e "\n${WHITE}Recent Activity:${NC}"
    if [[ -f "$LOG_FILE" ]]; then
        echo -e "  Last 3 log entries:"
        tail -3 "$LOG_FILE" 2>/dev/null | while IFS= read -r line; do
            echo -e "    ${CYAN}$line${NC}"
        done
    fi
    
    # Error summary
    echo -e "\n${WHITE}Error Summary:${NC}"
    echo -e "  Script Errors: ${GREEN}$SCRIPT_ERRORS${NC}"
    echo -e "  Warnings: ${GREEN}$WARNINGS_COUNT${NC}"
    
    # Backup status
    echo -e "\n${WHITE}Backup Status:${NC}"
    if [[ -d "$BACKUP_DIR" ]]; then
        local backup_count=$(ls -1 "$BACKUP_DIR"/*.backup 2>/dev/null | wc -l)
        echo -e "  Available Backups: ${GREEN}$backup_count${NC}"
        if [[ $backup_count -gt 0 ]]; then
            local latest_backup=$(ls -1t "$BACKUP_DIR"/*.backup 2>/dev/null | head -1)
            local backup_date=$(stat -c %y "$latest_backup" 2>/dev/null | cut -d' ' -f1 || echo "unknown")
            echo -e "  Latest Backup: ${GREEN}$backup_date${NC}"
        fi
    else
        echo -e "  Backup Directory: ${RED}✗ Not found${NC}"
    fi
    
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
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
    
    ${CYAN}Interactive Setup:${NC}
    --setup                   Quick interactive setup for new users
    --configure               Interactive configuration wizard
    --show-config             Display current configuration
    
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
    
    ${CYAN}Maintenance & Recovery:${NC}
    --backup                 Create manual backup
    --restore                Restore from backup
    --emergency              Enter emergency recovery mode
    --status                 Show comprehensive system status
    --integrity-check        Perform system integrity check

${WHITE}EXAMPLES:${NC}
    ${CYAN}# Quick interactive setup (recommended for new users)${NC}
    $0 --setup

    ${CYAN}# Configure preferences interactively${NC}
    $0 --configure

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

${WHITE}SUPPORTED OPERATING SYSTEMS:${NC}
    ${CYAN}Linux Distributions:${NC}
    • Debian family: Debian, Ubuntu, Linux Mint, Kali, Elementary, Pop!_OS
    • RedHat family: RHEL, CentOS, Fedora, Rocky Linux, AlmaLinux, Oracle Linux
    • SUSE family: openSUSE, SLES
    • Arch family: Arch Linux, Manjaro, EndeavourOS
    • Alpine Linux
    • Gentoo
    
    ${CYAN}BSD Systems:${NC}
    • FreeBSD
    • OpenBSD 
    • NetBSD
    • DragonFlyBSD
    
    ${CYAN}Init Systems Supported:${NC}
    • systemd (Linux distributions)
    • OpenRC (Alpine, Gentoo)
    • SysV (legacy systems)
    • BSD RC (FreeBSD, OpenBSD, NetBSD)
    • launchd (macOS - limited support)

EOF
}

# ============================================================================
# MAIN SCRIPT LOGIC
# ============================================================================

main() {
    # Parse arguments first to determine operation
    local operation=""
    local show_help=false
    local show_version=false
    local show_config=false
    
    # Quick parse for info commands
    for arg in "$@"; do
        case "$arg" in
            -h|--help) show_help=true; operation="help" ;;
            -v|--version) show_version=true; operation="version" ;;
            --show-config) show_config=true; operation="show_config" ;;
            --status) operation="status" ;;
            --integrity-check) operation="integrity_check" ;;
        esac
    done
    
    # Initialize logging with operation context
    CURRENT_OPERATION="$operation"
    init_logging "$operation"
    
    # Check root only for operations that require it
    local no_root_operations=("help" "version" "show_config" "status" "integrity_check")
    local needs_root=true
    
    for no_root_op in "${no_root_operations[@]}"; do
        if [[ "$operation" == "$no_root_op" ]]; then
            needs_root=false
            break
        fi
    done
    
    if [[ "$needs_root" == "true" ]]; then
        check_root
    fi
    
    # Load existing configuration
    load_config
    
    # Default values
    local ip_address=""
    local email="${USER_EMAIL:-}"
    local webroot="${USER_WEBROOT:-$DEFAULT_WEBROOT}"
    operation=""  # Reset operation for full parsing
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                trap - ERR  # Disable error trap for help
                usage
                exit 0
                ;;
            -v|--version)
                trap - ERR  # Disable error trap for version
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
            --setup)
                operation="quick_setup"
                shift
                ;;
            --configure)
                operation="configure"
                shift
                ;;
            --show-config)
                operation="show_config"
                shift
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
            --backup)
                operation="backup"
                shift
                ;;
            --restore)
                operation="restore"
                shift
                ;;
            --emergency)
                operation="emergency"
                shift
                ;;
            --status)
                operation="status"
                shift
                ;;
            --integrity-check)
                operation="integrity_check"
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
    
    # Skip lock for info commands and some maintenance operations
    local no_lock_operations=("help" "version" "show_config" "status" "backup" "integrity_check")
    local needs_lock=true
    
    for no_lock_op in "${no_lock_operations[@]}"; do
        if [[ "$operation" == "$no_lock_op" ]]; then
            needs_lock=false
            break
        fi
    done
    
    if [[ "$needs_lock" == "true" ]]; then
        # Acquire lock
        if ! acquire_lock; then
            exit 1
        fi
    fi
    
    # Detect OS (skip for info commands on unsupported systems)
    local skip_os_detect=("help" "version" "show_config" "status")
    local should_detect_os=true
    
    for skip_op in "${skip_os_detect[@]}"; do
        if [[ "$operation" == "$skip_op" ]]; then
            should_detect_os=false
            break
        fi
    done
    
    if [[ "$should_detect_os" == "true" ]]; then
        detect_os
    fi
    
    # Execute requested operation
    case "$operation" in
        quick_setup)
            quick_setup
            ;;
        configure)
            interactive_config
            ;;
        show_config)
            trap - ERR  # Disable error trap for show_config
            show_config
            ;;
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
        backup)
            create_backup "$CONFIG_FILE" "manual"
            [[ -d "$CERT_LIVE_PATH" ]] && create_backup "$CERT_LIVE_PATH" "cert_manual"
            log "INFO" "Manual backup completed"
            ;;
        restore)
            list_backups
            echo ""
            read -p "Enter backup type (config/cert) or 'cancel': " backup_type
            if [[ "$backup_type" != "cancel" ]]; then
                restore_backup "$backup_type"
            fi
            ;;
        emergency)
            emergency_recovery
            ;;
        status)
            trap - ERR  # Disable error trap for status
            generate_status_report
            ;;
        integrity_check)
            trap - ERR  # Disable error trap for integrity check
            perform_system_integrity_check
            local check_result=$?
            if [[ $check_result -eq 0 ]]; then
                log "INFO" "System integrity check completed successfully"
            else
                log "WARN" "System integrity check found $check_result issues"
                exit 1
            fi
            ;;
        *)
            # Default: obtain certificate or show usage
            if [[ -n "$ip_address" ]] && [[ -n "$email" ]]; then
                # Validate inputs before proceeding
                if ! validate_email "$email"; then
                    log "ERROR" "Invalid email address provided"
                    exit 1
                fi
                if ! validate_path "$webroot" "any"; then
                    log "ERROR" "Invalid webroot path provided"
                    exit 1
                fi
                
                check_dependencies
                obtain_ip_certificate "$ip_address" "$email" "$webroot"
            elif [[ -n "$ip_address" ]] && [[ -z "$email" ]] && [[ -n "${USER_EMAIL:-}" ]]; then
                # Use configured email if available
                check_dependencies
                obtain_ip_certificate "$ip_address" "$USER_EMAIL" "$webroot"
            else
                echo -e "${YELLOW}For new users, try: $0 --setup${NC}"
                echo -e "${YELLOW}For existing users: $0 --help${NC}"
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