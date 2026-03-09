#!/bin/bash
set -e

# Output colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_debug() { echo -e "${CYAN}[DEBUG]${NC} $1"; }

# ============================================
# PASSWORD GENERATION AND SANITIZATION
# ============================================
generate_password() {
    local length=$1
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$length"
}

sanitize_input() {
    local input="$1"
    # Remove dangerous characters: ; " ' ` $ \ / and newlines
    echo "$input" | tr -d ';"'\''`$\\/\n\r' | head -c 64
}

# ============================================
# CONFIGURATION
# ============================================
CHR_VERSION="7.16.1"
CHR_URL="https://download.mikrotik.com/routeros/${CHR_VERSION}/chr-${CHR_VERSION}.img.zip"
CHR_ZIP="chr-${CHR_VERSION}.img.zip"
CHR_IMG="chr-${CHR_VERSION}.img"
WORK_DIR="/tmp/chr-install"
MOUNT_POINT="/mnt/chr"

# CHR Settings (password auto-generated if not specified)
ADMIN_PASSWORD=""
DNS_SERVERS="8.8.8.8,8.8.4.4"
ROUTER_NAME="MikroTik-CHR"
TIMEZONE="Europe/Moscow"

# Flags
FORCE_DOWNLOAD=false
AUTO_YES=false
AUTO_REBOOT=false

# ============================================
# ARGUMENT PARSING
# ============================================
usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "CHR installation script with basic security configuration:"
    echo "  - Firewall with SSH/WinBox brute-force protection"
    echo "  - DNS amplification attack protection"
    echo "  - Disable insecure services"
    echo "  - NTP and timezone configuration"
    echo "  - Daily automatic backup"
    echo ""
    echo "Options:"
    echo "  --force          Force re-download the image"
    echo "  --yes, -y        No confirmations (automatic mode)"
    echo "  --reboot         Automatic reboot (requires --yes)"
    echo "  --version VER    CHR version (default: $CHR_VERSION)"
    echo "  --password PASS  Admin password (auto-generated)"
    echo "  --name NAME      Router name (default: $ROUTER_NAME)"
    echo "  --timezone TZ    Timezone (default: $TIMEZONE)"
    echo "  --dns SERVERS    DNS servers (default: $DNS_SERVERS)"
    echo "  -h, --help       Show help"
    echo ""
    echo "Examples:"
    echo "  $0 --yes --reboot                           # Auto-install with basic config"
    echo "  $0 --password MyPass123 --name VPN-Server   # Custom password and name"
    echo "  $0 --timezone America/New_York              # Different timezone"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_DOWNLOAD=true
            shift
            ;;
        --yes|-y)
            AUTO_YES=true
            shift
            ;;
        --reboot)
            AUTO_REBOOT=true
            shift
            ;;
        --version)
            CHR_VERSION="$2"
            CHR_URL="https://download.mikrotik.com/routeros/${CHR_VERSION}/chr-${CHR_VERSION}.img.zip"
            CHR_ZIP="chr-${CHR_VERSION}.img.zip"
            CHR_IMG="chr-${CHR_VERSION}.img"
            shift 2
            ;;
        --password)
            ADMIN_PASSWORD=$(sanitize_input "$2")
            shift 2
            ;;
        --name)
            ROUTER_NAME=$(sanitize_input "$2")
            shift 2
            ;;
        --timezone)
            TIMEZONE=$(sanitize_input "$2")
            shift 2
            ;;
        --dns)
            DNS_SERVERS=$(sanitize_input "$2")
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# ============================================
# PASSWORD GENERATION (if not specified)
# ============================================
if [[ -z "$ADMIN_PASSWORD" ]]; then
    ADMIN_PASSWORD=$(generate_password 16)
    log_info "Generated admin password: $ADMIN_PASSWORD"
fi

# ============================================
# ROOT CHECK
# ============================================
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    exit 1
fi

# ============================================
# BOOT MODE DETECTION (UEFI/LEGACY)
# ============================================
if [[ -d /sys/firmware/efi ]]; then
    BOOT_MODE="UEFI"
    log_info "Boot mode: UEFI"
else
    BOOT_MODE="LEGACY"
    log_info "Boot mode: Legacy BIOS"
fi

# ============================================
# DEPENDENCY CHECK
# ============================================
log_info "Checking dependencies..."

REQUIRED_TOOLS="wget unzip fdisk dd mount umount file md5sum xxd"

if [[ "$BOOT_MODE" == "UEFI" ]]; then
    REQUIRED_TOOLS="$REQUIRED_TOOLS parted mkfs.vfat"
fi

MISSING_TOOLS=""

for tool in $REQUIRED_TOOLS; do
    if ! command -v $tool &> /dev/null; then
        MISSING_TOOLS="$MISSING_TOOLS $tool"
    fi
done

if [[ -n "$MISSING_TOOLS" ]]; then
    log_warn "Missing tools:$MISSING_TOOLS"
    log_info "Attempting to install..."

    if command -v apt-get &> /dev/null; then
        apt-get update && apt-get install -y wget unzip fdisk coreutils mount xxd file parted dosfstools
    elif command -v yum &> /dev/null; then
        yum install -y wget unzip util-linux coreutils vim-common file parted dosfstools
    elif command -v dnf &> /dev/null; then
        dnf install -y wget unzip util-linux coreutils vim-common file parted dosfstools
    else
        log_error "Please install manually:$MISSING_TOOLS"
        exit 1
    fi
fi

log_info "All dependencies are satisfied"

# ============================================
# WORKING DIRECTORY PREPARATION
# ============================================
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

log_info "Working directory: $WORK_DIR"
log_debug "Free space: $(df -h "$WORK_DIR" | tail -1 | awk '{print $4}')"

# ============================================
# IMAGE DOWNLOAD
# ============================================
if [[ "$FORCE_DOWNLOAD" == true ]] || [[ ! -f "$CHR_IMG" ]]; then
    rm -f "$CHR_ZIP" "$CHR_IMG" "${CHR_IMG}.modified"
    
    log_info "Downloading CHR ${CHR_VERSION}..."
    wget --progress=bar:force -O "$CHR_ZIP" "$CHR_URL"
    
    # Check downloaded file size
    ACTUAL_SIZE=$(stat -c%s "$CHR_ZIP")
    log_debug "Downloaded file size: $ACTUAL_SIZE bytes"
    
    if [[ $ACTUAL_SIZE -lt 30000000 ]]; then
        log_error "File too small, download incomplete"
        exit 1
    fi
    
    # Check file type
    FILE_TYPE=$(file "$CHR_ZIP")
    log_debug "File type: $FILE_TYPE"
    
    if echo "$FILE_TYPE" | grep -q "Zip archive"; then
        log_info "Extracting ZIP..."
        unzip -o "$CHR_ZIP"
    elif echo "$FILE_TYPE" | grep -q "gzip"; then
        log_info "Extracting GZIP..."
        gunzip -c "$CHR_ZIP" > "$CHR_IMG"
    else
        log_error "Unknown format: $FILE_TYPE"
        exit 1
    fi
    
    rm -f "$CHR_ZIP"
else
    log_info "Using existing image: $CHR_IMG"
fi

# ============================================
# IMAGE VALIDATION
# ============================================
log_info "Validating image..."

if [[ ! -f "$CHR_IMG" ]]; then
    log_error "Image not found!"
    ls -la "$WORK_DIR"
    exit 1
fi

IMG_SIZE=$(stat -c%s "$CHR_IMG")
log_debug "Image size: $IMG_SIZE bytes ($(( IMG_SIZE / 1024 / 1024 )) MB)"

# Check MBR signature
MBR_SIG=$(xxd -s 510 -l 2 -p "$CHR_IMG")
if [[ "$MBR_SIG" != "55aa" ]]; then
    log_error "Invalid MBR signature: $MBR_SIG (expected 55aa)"
    exit 1
fi
log_debug "MBR signature: OK (55aa)"

ORIGINAL_MD5=$(md5sum "$CHR_IMG" | awk '{print $1}')
log_info "Original image MD5: $ORIGINAL_MD5"

log_info "Image validation passed ✓"

# ============================================
# UEFI CONVERSION (if needed)
# ============================================
if [[ "$BOOT_MODE" == "UEFI" ]]; then
    log_info "Converting image for UEFI..."
    
    CHR_IMG_UEFI="${CHR_IMG%.img}-uefi.img"
    
    # Remove boot flag (*) so columns don't shift
    PART1_START=$(fdisk -l "$CHR_IMG" 2>/dev/null | grep "${CHR_IMG}1" | sed 's/\*//' | awk '{print $2}')
    PART1_END=$(fdisk -l "$CHR_IMG" 2>/dev/null | grep "${CHR_IMG}1" | sed 's/\*//' | awk '{print $3}')
    PART1_SECTORS=$((PART1_END - PART1_START + 1))
    
    PART2_START=$(fdisk -l "$CHR_IMG" 2>/dev/null | grep "${CHR_IMG}2" | sed 's/\*//' | awk '{print $2}')
    PART2_END=$(fdisk -l "$CHR_IMG" 2>/dev/null | grep "${CHR_IMG}2" | sed 's/\*//' | awk '{print $3}')
    PART2_SECTORS=$((PART2_END - PART2_START + 1))
    
    # Check that values were obtained
    if [[ -z "$PART1_START" || -z "$PART2_START" ]]; then
        log_error "Failed to determine image partitions"
        exit 1
    fi
    
    ESP_SECTORS=69632
    TOTAL_SECTORS=$((2048 + ESP_SECTORS + PART1_SECTORS + PART2_SECTORS + 34))
    NEW_IMG_SIZE=$((TOTAL_SECTORS * 512))
    
    log_debug "Creating UEFI image of $((NEW_IMG_SIZE / 1024 / 1024)) MB"
    
    dd if=/dev/zero of="$CHR_IMG_UEFI" bs=1M count=$((NEW_IMG_SIZE / 1024 / 1024 + 1)) status=none
    
    parted -s "$CHR_IMG_UEFI" mklabel gpt
    
    ESP_START=2048
    ESP_END=$((ESP_START + ESP_SECTORS - 1))
    parted -s "$CHR_IMG_UEFI" mkpart primary fat32 ${ESP_START}s ${ESP_END}s
    parted -s "$CHR_IMG_UEFI" set 1 esp on
    parted -s "$CHR_IMG_UEFI" set 1 boot on
    
    BOOT_START=$((ESP_END + 1))
    BOOT_END=$((BOOT_START + PART1_SECTORS - 1))
    parted -s "$CHR_IMG_UEFI" mkpart primary ext4 ${BOOT_START}s ${BOOT_END}s
    
    ROOT_START=$((BOOT_END + 1))
    ROOT_END=$((ROOT_START + PART2_SECTORS - 1))
    parted -s "$CHR_IMG_UEFI" mkpart primary ext4 ${ROOT_START}s ${ROOT_END}s
    
    log_debug "Copying partitions from original image..."
    
    dd if="$CHR_IMG" of="$CHR_IMG_UEFI" bs=512 skip=$PART1_START seek=$BOOT_START count=$PART1_SECTORS conv=notrunc status=none
    dd if="$CHR_IMG" of="$CHR_IMG_UEFI" bs=512 skip=$PART2_START seek=$ROOT_START count=$PART2_SECTORS conv=notrunc status=none
    
    log_debug "Creating EFI partition..."
    
    LOOP_DEV=$(losetup -f --show -o $((ESP_START * 512)) --sizelimit $((ESP_SECTORS * 512)) "$CHR_IMG_UEFI")
    mkfs.vfat -F 32 -n "EFI" "$LOOP_DEV" >/dev/null 2>&1
    
    ESP_MOUNT="/mnt/chr-esp"
    mkdir -p "$ESP_MOUNT"
    mount "$LOOP_DEV" "$ESP_MOUNT"
    
    BOOT_LOOP=$(losetup -f --show -o $((PART1_START * 512)) --sizelimit $((PART1_SECTORS * 512)) "$CHR_IMG")
    BOOT_MOUNT="/mnt/chr-boot"
    mkdir -p "$BOOT_MOUNT"
    mount -o ro "$BOOT_LOOP" "$BOOT_MOUNT"
    
    if [[ -d "$BOOT_MOUNT/EFI" ]]; then
        cp -r "$BOOT_MOUNT/EFI" "$ESP_MOUNT/"
        log_debug "EFI files copied from image"
    else
        mkdir -p "$ESP_MOUNT/EFI/BOOT"
        if [[ -f "$BOOT_MOUNT/vmlinuz" ]]; then
            cp "$BOOT_MOUNT/vmlinuz" "$ESP_MOUNT/EFI/BOOT/BOOTX64.EFI"
            log_debug "Created EFI bootloader from vmlinuz"
        fi
    fi
    
    umount "$BOOT_MOUNT" 2>/dev/null || true
    losetup -d "$BOOT_LOOP" 2>/dev/null || true
    umount "$ESP_MOUNT" 2>/dev/null || true
    losetup -d "$LOOP_DEV" 2>/dev/null || true
    rmdir "$ESP_MOUNT" 2>/dev/null || true
    rmdir "$BOOT_MOUNT" 2>/dev/null || true
    
    CHR_IMG="$CHR_IMG_UEFI"
    
    log_info "UEFI image created ✓"
    log_debug "New partition table:"
    parted -s "$CHR_IMG" print 2>/dev/null || fdisk -l "$CHR_IMG" 2>/dev/null | head -20
fi

# ============================================
# NETWORK PARAMETERS DETECTION
# ============================================
log_info "Detecting network parameters..."

INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
ADDRESS=$(ip addr show "$INTERFACE" 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | head -n1)
GATEWAY=$(ip route | grep default | awk '{print $3}' | head -n1)
SERVER_IP="${ADDRESS%/*}"
NETMASK="${ADDRESS#*/}"

if [[ -z "$INTERFACE" || -z "$ADDRESS" || -z "$GATEWAY" ]]; then
    log_error "Failed to detect network parameters"
    log_error "INTERFACE=$INTERFACE ADDRESS=$ADDRESS GATEWAY=$GATEWAY"
    exit 1
fi

check_same_subnet() {
    local ip="$1"
    local gw="$2"
    local mask="$3"
    
    IFS='.' read -r i1 i2 i3 i4 <<< "$ip"
    IFS='.' read -r g1 g2 g3 g4 <<< "$gw"
    
    local full_mask=$(( 0xFFFFFFFF << (32 - mask) & 0xFFFFFFFF ))
    local m1=$(( (full_mask >> 24) & 255 ))
    local m2=$(( (full_mask >> 16) & 255 ))
    local m3=$(( (full_mask >> 8) & 255 ))
    local m4=$(( full_mask & 255 ))
    
    if [[ $((i1 & m1)) -eq $((g1 & m1)) ]] && \
       [[ $((i2 & m2)) -eq $((g2 & m2)) ]] && \
       [[ $((i3 & m3)) -eq $((g3 & m3)) ]] && \
       [[ $((i4 & m4)) -eq $((g4 & m4)) ]]; then
        return 0
    else
        return 1
    fi
}

if check_same_subnet "$SERVER_IP" "$GATEWAY" "$NETMASK"; then
    GATEWAY_IN_SUBNET=true
    log_info "Gateway in same subnet - using simple route"
else
    GATEWAY_IN_SUBNET=false
    log_info "Gateway in different subnet - using recursive routing (scope)"
fi

log_info "Interface: $INTERFACE | Address: $ADDRESS | Gateway: $GATEWAY"

# ============================================
# DISK DETECTION
# ============================================
log_info "Detecting target disk..."

echo ""
lsblk -d -o NAME,SIZE,MODEL,TYPE | grep -E "(NAME|disk)"
echo ""

# Detect disk by root partition (excludes fd0, sr0, etc.)
DISK_DEVICE=""
ROOT_PART=$(findmnt -n -o SOURCE / 2>/dev/null)
if [[ -n "$ROOT_PART" ]]; then
    DISK_DEVICE=$(lsblk -ndo PKNAME "$ROOT_PART" 2>/dev/null)
    [[ -n "$DISK_DEVICE" ]] && DISK_DEVICE="/dev/$DISK_DEVICE"
fi
# Fallback: first real disk (exclude floppy, cdrom, loop)
if [[ -z "$DISK_DEVICE" ]]; then
    DISK_DEVICE=$(lsblk -ndo NAME,TYPE | awk '$2=="disk" && $1!~/^(fd|sr|loop)/ {print "/dev/"$1; exit}')
fi

if [[ -z "$DISK_DEVICE" ]]; then
    log_error "Disk not found"
    exit 1
fi

DISK_SIZE=$(lsblk -ndo SIZE "$DISK_DEVICE")
log_warn "Target disk: $DISK_DEVICE ($DISK_SIZE)"

# ============================================
# CREATE AUTORUN WITH BASIC CONFIGURATION
# ============================================
log_info "Creating autorun.scr with basic security configuration..."

CHR_IMG_MOD="${CHR_IMG}.modified"
cp "$CHR_IMG" "$CHR_IMG_MOD"

mkdir -p "$MOUNT_POINT"

if [[ "$BOOT_MODE" == "UEFI" ]]; then
    ROOT_PART_NUM=3
else
    ROOT_PART_NUM=2
fi

OFFSET_SECTORS=$(fdisk -l "$CHR_IMG_MOD" 2>/dev/null | grep "${CHR_IMG_MOD}${ROOT_PART_NUM}" | awk '{print $2}')
if [[ -z "$OFFSET_SECTORS" ]]; then
    if [[ "$BOOT_MODE" == "UEFI" ]]; then
        log_error "Failed to determine offset for UEFI image"
        exit 1
    fi
    OFFSET_BYTES=33571840
else
    OFFSET_BYTES=$((OFFSET_SECTORS * 512))
fi

log_debug "Mounting partition $ROOT_PART_NUM with offset: $OFFSET_BYTES"

mount -o loop,offset="$OFFSET_BYTES" "$CHR_IMG_MOD" "$MOUNT_POINT"

if [[ ! -d "$MOUNT_POINT/rw" ]]; then
    log_warn "Directory /rw does not exist, creating..."
    mkdir -p "$MOUNT_POINT/rw"
fi

# Create autorun (no comments for RouterOS compatibility)
if [[ "$GATEWAY_IN_SUBNET" == "true" ]]; then
    ROUTE_COMMANDS="/ip route add dst-address=0.0.0.0/0 gateway=${GATEWAY}"
else
    ROUTE_COMMANDS="/ip route add dst-address=${GATEWAY}/32 gateway=ether1 scope=10
/ip route add dst-address=0.0.0.0/0 gateway=${GATEWAY} target-scope=11"
fi

cat > "$MOUNT_POINT/rw/autorun.scr" <<EOF
/ip dhcp-client remove [find]
/ip address add address=${ADDRESS} interface=ether1
${ROUTE_COMMANDS}
/ip dns set servers=${DNS_SERVERS}
/user set 0 name=admin password=${ADMIN_PASSWORD}
/system identity set name=${ROUTER_NAME}
/system clock set time-zone-name=${TIMEZONE}
/system ntp client set enabled=yes
/system ntp client servers add address=pool.ntp.org
/ip service set telnet disabled=yes
/ip service set ftp disabled=yes
/ip service set www disabled=yes
/ip service set api disabled=yes
/ip service set api-ssl disabled=yes
/ip service set ssh disabled=no port=22
/ip service set winbox disabled=no
/ip firewall filter add chain=input connection-state=established,related action=accept
/ip firewall filter add chain=input connection-state=invalid action=drop
/ip firewall filter add chain=input protocol=tcp dst-port=22 src-address-list=ssh_blacklist action=drop
/ip firewall filter add chain=input protocol=tcp dst-port=22 connection-state=new src-address-list=ssh_stage3 action=add-src-to-address-list address-list=ssh_blacklist address-list-timeout=1w
/ip firewall filter add chain=input protocol=tcp dst-port=22 connection-state=new src-address-list=ssh_stage2 action=add-src-to-address-list address-list=ssh_stage3 address-list-timeout=1m
/ip firewall filter add chain=input protocol=tcp dst-port=22 connection-state=new src-address-list=ssh_stage1 action=add-src-to-address-list address-list=ssh_stage2 address-list-timeout=1m
/ip firewall filter add chain=input protocol=tcp dst-port=22 connection-state=new action=add-src-to-address-list address-list=ssh_stage1 address-list-timeout=1m
/ip firewall filter add chain=input protocol=tcp dst-port=8291 src-address-list=winbox_blacklist action=drop
/ip firewall filter add chain=input protocol=tcp dst-port=8291 connection-state=new src-address-list=winbox_stage3 action=add-src-to-address-list address-list=winbox_blacklist address-list-timeout=1w
/ip firewall filter add chain=input protocol=tcp dst-port=8291 connection-state=new src-address-list=winbox_stage2 action=add-src-to-address-list address-list=winbox_stage3 address-list-timeout=1m
/ip firewall filter add chain=input protocol=tcp dst-port=8291 connection-state=new src-address-list=winbox_stage1 action=add-src-to-address-list address-list=winbox_stage2 address-list-timeout=1m
/ip firewall filter add chain=input protocol=tcp dst-port=8291 connection-state=new action=add-src-to-address-list address-list=winbox_stage1 address-list-timeout=1m
/ip dns set allow-remote-requests=no
/ip firewall filter add chain=input protocol=udp dst-port=53 action=drop
/ip firewall filter add chain=input protocol=tcp dst-port=53 action=drop
/ip firewall filter add chain=input protocol=icmp action=accept
/ip firewall filter add chain=input protocol=tcp dst-port=22 action=accept
/ip firewall filter add chain=input protocol=tcp dst-port=8291 action=accept
/ip firewall filter add chain=input action=drop
/system script add name=backup-script source="/system backup save name=auto-backup"
/system scheduler add name=daily-backup interval=1d on-event=backup-script start-time=03:00:00
/system logging add topics=firewall action=memory
/system logging add topics=error action=memory
/system logging add topics=warning action=memory
/ip firewall nat add chain=srcnat out-interface=ether1 action=masquerade
/file remove [find name~"autorun"]
EOF

sync

log_debug "autorun.scr created:"
cat "$MOUNT_POINT/rw/autorun.scr"

if [[ ! -s "$MOUNT_POINT/rw/autorun.scr" ]]; then
    log_error "autorun.scr is empty or not created!"
    umount "$MOUNT_POINT"
    exit 1
fi

sync
umount "$MOUNT_POINT"
sync

# Check MD5 after modification
MODIFIED_MD5=$(md5sum "$CHR_IMG_MOD" | awk '{print $1}')
log_debug "MD5 after modification: $MODIFIED_MD5"

# Check MBR after modification
MBR_SIG_MOD=$(xxd -s 510 -l 2 -p "$CHR_IMG_MOD")
if [[ "$MBR_SIG_MOD" != "55aa" ]]; then
    log_error "MBR corrupted after modification! Signature: $MBR_SIG_MOD"
    exit 1
fi

log_debug "MBR after modification: OK"
FINAL_IMG="$CHR_IMG_MOD"
log_info "Basic configuration prepared ✓"

# ============================================
# FINAL CONFIRMATION
# ============================================
echo ""
echo "============================================"
echo -e "${YELLOW}        POINT OF NO RETURN!${NC}"
echo "============================================"
echo ""
echo "Image:    $FINAL_IMG"
echo "Disk:     $DISK_DEVICE ($DISK_SIZE)"
echo "Mode:     $BOOT_MODE"
echo "IP:       $ADDRESS"
echo "Gateway:  $GATEWAY"
echo "Name:     $ROUTER_NAME"
echo "Timezone: $TIMEZONE"
echo ""
echo -e "${GREEN}Basic configuration includes:${NC}"
echo "  ✓ Firewall with brute-force protection (SSH, WinBox)"
echo "  ✓ DNS amplification attack protection"
echo "  ✓ Disable insecure services"
echo "  ✓ NTP configuration (pool.ntp.org)"
echo "  ✓ Daily auto-backup (03:00)"
echo "  ✓ Logging firewall/error/warning"
echo ""
echo -e "${RED}ALL DATA ON $DISK_DEVICE WILL BE DESTROYED!${NC}"
echo ""

if [[ "$AUTO_YES" == true ]]; then
    log_warn "Automatic mode (--yes), continuing without confirmation..."
else
    read -p "Type 'YES' to continue: " confirm
    if [[ "$confirm" != "YES" ]]; then
        log_info "Cancelled"
        exit 0
    fi
fi

# ============================================
# WRITE TO DISK
# ============================================
log_info "Writing image to $DISK_DEVICE..."

log_info "Switching filesystem to read-only..."
sync
echo 1 > /proc/sys/kernel/sysrq
echo u > /proc/sysrq-trigger
sleep 2

dd if="$FINAL_IMG" of="$DISK_DEVICE" bs=4M oflag=direct status=progress

log_info "Write completed"

# ============================================
# COMPLETION
# ============================================
echo ""
log_info "=========================================="
log_info "CHR installation with basic config completed!"
log_info "=========================================="
echo ""
echo "CHR will be available at: ${ADDRESS%/*}"
echo "Admin password: ${ADMIN_PASSWORD}"
echo ""
echo -e "${GREEN}Configured:${NC}"
echo "  • Router name: $ROUTER_NAME"
echo "  • Timezone: $TIMEZONE"
echo "  • Firewall with brute-force protection"
echo "  • DNS amplification protection"
echo "  • Auto-backup daily at 03:00"
echo ""

if [[ "$AUTO_YES" == true && "$AUTO_REBOOT" == true ]]; then
    log_info "Automatic reboot in 3 seconds..."
    sleep 3
    echo 1 > /proc/sys/kernel/sysrq
    echo s > /proc/sysrq-trigger
    sleep 1
    echo u > /proc/sysrq-trigger
    sleep 1
    echo b > /proc/sysrq-trigger
elif [[ "$AUTO_YES" == true ]]; then
    log_info "Reboot manually: reboot"
else
    read -p "Reboot now? (y/n): " do_reboot
    if [[ "$do_reboot" == "y" ]]; then
        log_info "Rebooting..."
        sleep 2
        echo 1 > /proc/sys/kernel/sysrq
        echo s > /proc/sysrq-trigger
        sleep 1
        echo u > /proc/sysrq-trigger
        sleep 1
        echo b > /proc/sysrq-trigger
    else
        log_info "Reboot manually: reboot"
    fi
fi
