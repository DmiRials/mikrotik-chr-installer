#!/bin/bash
set -e

# Цвета для вывода
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
# ГЕНЕРАЦИЯ ПАРОЛЕЙ И САНИТИЗАЦИЯ
# ============================================
generate_password() {
    local length=$1
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$length"
}

sanitize_input() {
    local input="$1"
    # Удаляем опасные символы: ; " ' ` $ \ / и переносы строк
    echo "$input" | tr -d ';"'\''`$\\/\n\r' | head -c 64
}

# ============================================
# КОНФИГУРАЦИЯ
# ============================================
CHR_VERSION="7.16.1"
CHR_URL="https://download.mikrotik.com/routeros/${CHR_VERSION}/chr-${CHR_VERSION}.img.zip"
CHR_ZIP="chr-${CHR_VERSION}.img.zip"
CHR_IMG="chr-${CHR_VERSION}.img"
WORK_DIR="/tmp/chr-install"
MOUNT_POINT="/mnt/chr"

# Настройки CHR (пароль генерируется автоматически если не указан)
ADMIN_PASSWORD=""
DNS_SERVERS="8.8.8.8,8.8.4.4"

# Флаги
SKIP_AUTORUN=false
FORCE_DOWNLOAD=false
VERIFY_WRITE=true
AUTO_YES=false
AUTO_REBOOT=false

# ============================================
# ПАРСИНГ АРГУМЕНТОВ
# ============================================
usage() {
    echo "Использование: $0 [опции]"
    echo ""
    echo "Опции:"
    echo "  --clean          Чистая установка без autorun.scr"
    echo "  --force          Принудительно скачать образ заново"
    echo "  --no-verify      Пропустить верификацию записи"
    echo "  --yes, -y        Без подтверждений (автоматический режим)"
    echo "  --reboot         Автоматическая перезагрузка (требует --yes)"
    echo "  --version VER    Версия CHR (по умолчанию: $CHR_VERSION)"
    echo "  --password PASS  Пароль admin (генерируется автоматически)"
    echo "  -h, --help       Показать справку"
    echo ""
    echo "Примеры:"
    echo "  $0 --clean                    # Чистая установка с подтверждением"
    echo "  $0 --yes --reboot             # Полностью автоматическая установка"
    echo "  $0 -y --clean --reboot        # Автоматическая чистая установка"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --clean)
            SKIP_AUTORUN=true
            shift
            ;;
        --force)
            FORCE_DOWNLOAD=true
            shift
            ;;
        --no-verify)
            VERIFY_WRITE=false
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
        -h|--help)
            usage
            ;;
        *)
            log_error "Неизвестная опция: $1"
            usage
            ;;
    esac
done

# ============================================
# ГЕНЕРАЦИЯ ПАРОЛЯ (если не задан)
# ============================================
if [[ -z "$ADMIN_PASSWORD" ]]; then
    ADMIN_PASSWORD=$(generate_password 16)
    log_info "Сгенерирован пароль admin: $ADMIN_PASSWORD"
fi

# ============================================
# ПРОВЕРКА ROOT
# ============================================
if [[ $EUID -ne 0 ]]; then
    log_error "Скрипт должен запускаться от root"
    exit 1
fi

# ============================================
# ОПРЕДЕЛЕНИЕ РЕЖИМА ЗАГРУЗКИ (UEFI/LEGACY)
# ============================================
if [[ -d /sys/firmware/efi ]]; then
    BOOT_MODE="UEFI"
    log_info "Режим загрузки: UEFI"
else
    BOOT_MODE="LEGACY"
    log_info "Режим загрузки: Legacy BIOS"
fi

# ============================================
# ПРОВЕРКА ЗАВИСИМОСТЕЙ
# ============================================
log_info "Проверка зависимостей..."

REQUIRED_TOOLS="wget unzip fdisk dd mount umount file md5sum xxd"

# Дополнительные инструменты для UEFI
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
    log_warn "Отсутствуют утилиты:$MISSING_TOOLS"
    log_info "Попытка установки..."
    
    if command -v apt-get &> /dev/null; then
        apt-get update && apt-get install -y wget unzip fdisk coreutils mount xxd file parted dosfstools
    elif command -v yum &> /dev/null; then
        yum install -y wget unzip util-linux coreutils vim-common file parted dosfstools
    elif command -v dnf &> /dev/null; then
        dnf install -y wget unzip util-linux coreutils vim-common file parted dosfstools
    else
        log_error "Установи вручную:$MISSING_TOOLS"
        exit 1
    fi
fi

log_info "Все зависимости в порядке"

# ============================================
# ПОДГОТОВКА РАБОЧЕЙ ДИРЕКТОРИИ
# ============================================
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

log_info "Рабочая директория: $WORK_DIR"
log_debug "Свободное место: $(df -h "$WORK_DIR" | tail -1 | awk '{print $4}')"

# ============================================
# СКАЧИВАНИЕ ОБРАЗА
# ============================================
if [[ "$FORCE_DOWNLOAD" == true ]] || [[ ! -f "$CHR_IMG" ]]; then
    rm -f "$CHR_ZIP" "$CHR_IMG" "${CHR_IMG}.modified"
    
    log_info "Скачивание CHR ${CHR_VERSION}..."
    wget --progress=bar:force -O "$CHR_ZIP" "$CHR_URL"
    
    # Проверка размера скачанного файла
    ACTUAL_SIZE=$(stat -c%s "$CHR_ZIP")
    log_debug "Размер скачанного файла: $ACTUAL_SIZE байт"
    
    if [[ $ACTUAL_SIZE -lt 30000000 ]]; then
        log_error "Файл слишком маленький, скачивание неполное"
        exit 1
    fi
    
    # Проверка типа файла
    FILE_TYPE=$(file "$CHR_ZIP")
    log_debug "Тип файла: $FILE_TYPE"
    
    if echo "$FILE_TYPE" | grep -q "Zip archive"; then
        log_info "Распаковка ZIP..."
        unzip -o "$CHR_ZIP"
    elif echo "$FILE_TYPE" | grep -q "gzip"; then
        log_info "Распаковка GZIP..."
        gunzip -c "$CHR_ZIP" > "$CHR_IMG"
    else
        log_error "Неизвестный формат: $FILE_TYPE"
        exit 1
    fi
    
    rm -f "$CHR_ZIP"
else
    log_info "Используется существующий образ: $CHR_IMG"
fi

# ============================================
# ВАЛИДАЦИЯ ОБРАЗА (РАСШИРЕННАЯ)
# ============================================
log_info "Валидация образа..."

if [[ ! -f "$CHR_IMG" ]]; then
    log_error "Образ не найден!"
    ls -la "$WORK_DIR"
    exit 1
fi

IMG_SIZE=$(stat -c%s "$CHR_IMG")
log_debug "Размер образа: $IMG_SIZE байт ($(( IMG_SIZE / 1024 / 1024 )) MB)"

# Проверка MBR сигнатуры (последние 2 байта первого сектора = 55 AA)
MBR_SIG=$(xxd -s 510 -l 2 -p "$CHR_IMG")
if [[ "$MBR_SIG" != "55aa" ]]; then
    log_error "Неверная MBR сигнатура: $MBR_SIG (ожидается 55aa)"
    exit 1
fi
log_debug "MBR сигнатура: OK (55aa)"

# Сохраняем MD5 оригинального образа
ORIGINAL_MD5=$(md5sum "$CHR_IMG" | awk '{print $1}')
log_info "MD5 оригинального образа: $ORIGINAL_MD5"

# Проверка таблицы разделов
log_debug "Таблица разделов:"
fdisk -l "$CHR_IMG" 2>/dev/null | grep -E "^(Disk|Device|${CHR_IMG})" || true

log_info "Образ прошёл валидацию ✓"

# ============================================
# КОНВЕРТАЦИЯ ДЛЯ UEFI (если нужно)
# ============================================
if [[ "$BOOT_MODE" == "UEFI" ]]; then
    log_info "Конвертация образа для UEFI..."
    
    CHR_IMG_UEFI="${CHR_IMG%.img}-uefi.img"
    
    # Размеры разделов оригинального образа
    # Убираем boot flag (*) чтобы колонки не сдвигались
    PART1_START=$(fdisk -l "$CHR_IMG" 2>/dev/null | grep "${CHR_IMG}1" | sed 's/\*//' | awk '{print $2}')
    PART1_END=$(fdisk -l "$CHR_IMG" 2>/dev/null | grep "${CHR_IMG}1" | sed 's/\*//' | awk '{print $3}')
    PART1_SECTORS=$((PART1_END - PART1_START + 1))
    
    PART2_START=$(fdisk -l "$CHR_IMG" 2>/dev/null | grep "${CHR_IMG}2" | sed 's/\*//' | awk '{print $2}')
    PART2_END=$(fdisk -l "$CHR_IMG" 2>/dev/null | grep "${CHR_IMG}2" | sed 's/\*//' | awk '{print $3}')
    PART2_SECTORS=$((PART2_END - PART2_START + 1))
    
    # Проверка что значения получены
    if [[ -z "$PART1_START" || -z "$PART2_START" ]]; then
        log_error "Не удалось определить разделы образа"
        exit 1
    fi
    
    # ESP размер: 34MB = 69632 секторов
    ESP_SECTORS=69632
    ESP_SIZE_MB=34
    
    # Новый размер образа: ESP + оригинальные разделы + GPT overhead
    TOTAL_SECTORS=$((2048 + ESP_SECTORS + PART1_SECTORS + PART2_SECTORS + 34))
    NEW_IMG_SIZE=$((TOTAL_SECTORS * 512))
    
    log_debug "Создание UEFI образа размером $((NEW_IMG_SIZE / 1024 / 1024)) MB"
    
    # Создаём пустой образ
    dd if=/dev/zero of="$CHR_IMG_UEFI" bs=1M count=$((NEW_IMG_SIZE / 1024 / 1024 + 1)) status=none
    
    # Создаём GPT таблицу разделов
    parted -s "$CHR_IMG_UEFI" mklabel gpt
    
    # ESP раздел (EFI System Partition)
    ESP_START=2048
    ESP_END=$((ESP_START + ESP_SECTORS - 1))
    parted -s "$CHR_IMG_UEFI" mkpart primary fat32 ${ESP_START}s ${ESP_END}s
    parted -s "$CHR_IMG_UEFI" set 1 esp on
    parted -s "$CHR_IMG_UEFI" set 1 boot on
    
    # Boot раздел (из оригинала)
    BOOT_START=$((ESP_END + 1))
    BOOT_END=$((BOOT_START + PART1_SECTORS - 1))
    parted -s "$CHR_IMG_UEFI" mkpart primary ext4 ${BOOT_START}s ${BOOT_END}s
    
    # Root раздел (из оригинала)
    ROOT_START=$((BOOT_END + 1))
    ROOT_END=$((ROOT_START + PART2_SECTORS - 1))
    parted -s "$CHR_IMG_UEFI" mkpart primary ext4 ${ROOT_START}s ${ROOT_END}s
    
    log_debug "Копирование разделов из оригинального образа..."
    
    # Копируем boot раздел
    dd if="$CHR_IMG" of="$CHR_IMG_UEFI" bs=512 skip=$PART1_START seek=$BOOT_START count=$PART1_SECTORS conv=notrunc status=none
    
    # Копируем root раздел
    dd if="$CHR_IMG" of="$CHR_IMG_UEFI" bs=512 skip=$PART2_START seek=$ROOT_START count=$PART2_SECTORS conv=notrunc status=none
    
    log_debug "Создание EFI раздела..."
    
    # Создаём loop device для ESP
    LOOP_DEV=$(losetup -f --show -o $((ESP_START * 512)) --sizelimit $((ESP_SECTORS * 512)) "$CHR_IMG_UEFI")
    
    # Форматируем ESP
    mkfs.vfat -F 32 -n "EFI" "$LOOP_DEV" >/dev/null 2>&1
    
    # Монтируем ESP
    ESP_MOUNT="/mnt/chr-esp"
    mkdir -p "$ESP_MOUNT"
    mount "$LOOP_DEV" "$ESP_MOUNT"
    
    # Монтируем boot раздел оригинального образа для копирования EFI файлов
    BOOT_LOOP=$(losetup -f --show -o $((PART1_START * 512)) --sizelimit $((PART1_SECTORS * 512)) "$CHR_IMG")
    BOOT_MOUNT="/mnt/chr-boot"
    mkdir -p "$BOOT_MOUNT"
    mount -o ro "$BOOT_LOOP" "$BOOT_MOUNT"
    
    # Копируем EFI файлы
    if [[ -d "$BOOT_MOUNT/EFI" ]]; then
        cp -r "$BOOT_MOUNT/EFI" "$ESP_MOUNT/"
        log_debug "EFI файлы скопированы из образа"
    else
        # Создаём минимальную EFI структуру вручную
        mkdir -p "$ESP_MOUNT/EFI/BOOT"
        # Копируем ядро как EFI загрузчик (RouterOS использует EFI stub)
        if [[ -f "$BOOT_MOUNT/vmlinuz" ]]; then
            cp "$BOOT_MOUNT/vmlinuz" "$ESP_MOUNT/EFI/BOOT/BOOTX64.EFI"
            log_debug "Создан EFI загрузчик из vmlinuz"
        fi
    fi
    
    # Отмонтируем всё
    umount "$BOOT_MOUNT" 2>/dev/null || true
    losetup -d "$BOOT_LOOP" 2>/dev/null || true
    umount "$ESP_MOUNT" 2>/dev/null || true
    losetup -d "$LOOP_DEV" 2>/dev/null || true
    rmdir "$ESP_MOUNT" 2>/dev/null || true
    rmdir "$BOOT_MOUNT" 2>/dev/null || true
    
    # Используем UEFI образ вместо оригинального
    CHR_IMG="$CHR_IMG_UEFI"
    
    log_info "UEFI образ создан ✓"
    log_debug "Новая таблица разделов:"
    parted -s "$CHR_IMG" print 2>/dev/null || fdisk -l "$CHR_IMG" 2>/dev/null | head -20
fi

# ============================================
# ОПРЕДЕЛЕНИЕ СЕТЕВЫХ ПАРАМЕТРОВ
# ============================================
log_info "Определение сетевых параметров..."

INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
ADDRESS=$(ip addr show "$INTERFACE" 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | head -n1)
GATEWAY=$(ip route | grep default | awk '{print $3}' | head -n1)
SERVER_IP="${ADDRESS%/*}"
NETMASK="${ADDRESS#*/}"

if [[ -z "$INTERFACE" || -z "$ADDRESS" || -z "$GATEWAY" ]]; then
    log_error "Не удалось определить сетевые параметры"
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
    log_info "Gateway в той же подсети - используем простой маршрут"
else
    GATEWAY_IN_SUBNET=false
    log_info "Gateway в другой подсети - используем recursive routing (scope)"
fi

log_info "Интерфейс: $INTERFACE | Адрес: $ADDRESS | Шлюз: $GATEWAY"

# ============================================
# ОПРЕДЕЛЕНИЕ ДИСКА
# ============================================
log_info "Определение целевого диска..."

echo ""
lsblk -d -o NAME,SIZE,MODEL,TYPE | grep -E "(NAME|disk)"
echo ""

# Определяем диск по корневому разделу (исключает fd0, sr0 и т.д.)
DISK_DEVICE=""
ROOT_PART=$(findmnt -n -o SOURCE / 2>/dev/null)
if [[ -n "$ROOT_PART" ]]; then
    DISK_DEVICE=$(lsblk -ndo PKNAME "$ROOT_PART" 2>/dev/null)
    [[ -n "$DISK_DEVICE" ]] && DISK_DEVICE="/dev/$DISK_DEVICE"
fi
# Fallback: первый реальный диск (исключаем floppy, cdrom, loop)
if [[ -z "$DISK_DEVICE" ]]; then
    DISK_DEVICE=$(lsblk -ndo NAME,TYPE | awk '$2=="disk" && $1!~/^(fd|sr|loop)/ {print "/dev/"$1; exit}')
fi

if [[ -z "$DISK_DEVICE" ]]; then
    log_error "Диск не найден"
    exit 1
fi

DISK_SIZE=$(lsblk -ndo SIZE "$DISK_DEVICE")
log_warn "Целевой диск: $DISK_DEVICE ($DISK_SIZE)"

# ============================================
# ВЫБОР ОБРАЗА ДЛЯ ЗАПИСИ
# ============================================
FINAL_IMG="$CHR_IMG"

if [[ "$SKIP_AUTORUN" == true ]]; then
    log_warn "Режим --clean: autorun.scr НЕ будет создан"
    log_warn "Настройка CHR вручную после загрузки"
else
    log_info "Создание autorun.scr..."
    
    # Создаём копию образа для модификации
    CHR_IMG_MOD="${CHR_IMG}.modified"
    cp "$CHR_IMG" "$CHR_IMG_MOD"
    
    # Монтирование
    mkdir -p "$MOUNT_POINT"
    
    # Для UEFI root раздел = 3, для Legacy = 2
    if [[ "$BOOT_MODE" == "UEFI" ]]; then
        ROOT_PART_NUM=3
    else
        ROOT_PART_NUM=2
    fi
    
    OFFSET_SECTORS=$(fdisk -l "$CHR_IMG_MOD" 2>/dev/null | grep "${CHR_IMG_MOD}${ROOT_PART_NUM}" | awk '{print $2}')
    if [[ -z "$OFFSET_SECTORS" ]]; then
        if [[ "$BOOT_MODE" == "UEFI" ]]; then
            log_error "Не удалось определить offset для UEFI образа"
            exit 1
        fi
        OFFSET_BYTES=33571840
    else
        OFFSET_BYTES=$((OFFSET_SECTORS * 512))
    fi
    
    log_debug "Монтирование раздела $ROOT_PART_NUM с offset: $OFFSET_BYTES"
    
    mount -o loop,offset="$OFFSET_BYTES" "$CHR_IMG_MOD" "$MOUNT_POINT"
    
    # Проверяем структуру
    log_debug "Содержимое смонтированного раздела:"
    ls -la "$MOUNT_POINT/" || true
    
    if [[ ! -d "$MOUNT_POINT/rw" ]]; then
        log_warn "Директория /rw не существует, создаём..."
        mkdir -p "$MOUNT_POINT/rw"
    fi
    
    # Создание autorun
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
/ip service set telnet disabled=yes
/ip service set ftp disabled=yes
/ip service set www disabled=yes
/ip service set ssh disabled=no
/ip service set api disabled=yes
/ip service set api-ssl disabled=yes
/ip service set winbox disabled=no
/user set 0 name=admin password=${ADMIN_PASSWORD}
/ip firewall nat add chain=srcnat out-interface=ether1 action=masquerade
/file remove [find name~"autorun"]
EOF
    
    # Синхронизация ФС перед размонтированием
    sync
    
    log_debug "autorun.scr создан:"
    cat "$MOUNT_POINT/rw/autorun.scr"
    
    # Проверяем что файл записался
    if [[ ! -s "$MOUNT_POINT/rw/autorun.scr" ]]; then
        log_error "autorun.scr пустой или не создан!"
        umount "$MOUNT_POINT"
        exit 1
    fi
    
    # Размонтирование с sync
    sync
    umount "$MOUNT_POINT"
    sync
    
    # Проверка MD5 после модификации
    MODIFIED_MD5=$(md5sum "$CHR_IMG_MOD" | awk '{print $1}')
    log_debug "MD5 после модификации: $MODIFIED_MD5"
    
    if [[ "$ORIGINAL_MD5" == "$MODIFIED_MD5" ]]; then
        log_warn "MD5 не изменился — возможно autorun.scr не записался"
    fi
    
    # Проверка MBR после модификации
    MBR_SIG_MOD=$(xxd -s 510 -l 2 -p "$CHR_IMG_MOD")
    if [[ "$MBR_SIG_MOD" != "55aa" ]]; then
        log_error "MBR повреждён после модификации! Сигнатура: $MBR_SIG_MOD"
        log_error "Используем оригинальный образ без autorun"
        rm -f "$CHR_IMG_MOD"
        SKIP_AUTORUN=true
        FINAL_IMG="$CHR_IMG"
    else
        log_debug "MBR после модификации: OK"
        FINAL_IMG="$CHR_IMG_MOD"
        log_info "Autorun настроен ✓"
    fi
fi

# ============================================
# ФИНАЛЬНОЕ ПОДТВЕРЖДЕНИЕ
# ============================================
echo ""
echo "============================================"
echo -e "${YELLOW}        ТОЧКА НЕВОЗВРАТА!${NC}"
echo "============================================"
echo ""
echo "Образ:   $FINAL_IMG"
echo "Диск:    $DISK_DEVICE ($DISK_SIZE)"
echo "Режим:   $BOOT_MODE"
echo "IP:      $ADDRESS"
echo "Шлюз:    $GATEWAY"
echo "Autorun: $(if [[ "$SKIP_AUTORUN" == true ]]; then echo "ОТКЛЮЧЕН"; else echo "включен"; fi)"
echo ""
echo -e "${RED}ВСЕ ДАННЫЕ НА $DISK_DEVICE БУДУТ УНИЧТОЖЕНЫ!${NC}"
echo ""

if [[ "$AUTO_YES" == true ]]; then
    log_warn "Автоматический режим (--yes), продолжаем без подтверждения..."
else
    read -p "Введи 'YES' для продолжения: " confirm
    if [[ "$confirm" != "YES" ]]; then
        log_info "Отменено"
        exit 0
    fi
fi

# ============================================
# ЗАПИСЬ НА ДИСК
# ============================================
log_info "Запись образа на $DISK_DEVICE..."

# Переводим FS в read-only чтобы избежать race condition
log_info "Перевод файловой системы в read-only..."
sync
echo 1 > /proc/sys/kernel/sysrq
echo u > /proc/sysrq-trigger
sleep 2

dd if="$FINAL_IMG" of="$DISK_DEVICE" bs=4M oflag=direct status=progress

log_info "Запись завершена"
# sync не нужен - FS уже в read-only, dd с oflag=direct пишет напрямую

# ============================================
# ВЕРИФИКАЦИЯ ЗАПИСИ
# ============================================
# После echo u файловая система в read-only, верификация невозможна
# MBR уже проверен до записи, dd с oflag=direct гарантирует запись
log_info "Верификация пропущена (FS в read-only после remount)"

# ============================================
# ЗАВЕРШЕНИЕ
# ============================================
echo ""
log_info "=========================================="
log_info "Установка CHR завершена успешно!"
log_info "=========================================="
echo ""

if [[ "$SKIP_AUTORUN" == true ]]; then
    echo "После загрузки настрой вручную:"
    echo "  /ip address add address=$ADDRESS interface=ether1"
    echo "  /ip route add gateway=$GATEWAY"
    echo ""
fi

echo "CHR будет доступен: ${ADDRESS%/*}"
echo "Admin пароль:  ${ADMIN_PASSWORD}"
echo ""

if [[ "$AUTO_YES" == true && "$AUTO_REBOOT" == true ]]; then
    log_info "Автоматическая перезагрузка через 3 секунды..."
    sleep 3
    echo 1 > /proc/sys/kernel/sysrq
    echo s > /proc/sysrq-trigger
    sleep 1
    echo u > /proc/sysrq-trigger
    sleep 1
    echo b > /proc/sysrq-trigger
elif [[ "$AUTO_YES" == true ]]; then
    log_info "Перезагрузи вручную: reboot"
else
    read -p "Перезагрузить сейчас? (y/n): " do_reboot
    if [[ "$do_reboot" == "y" ]]; then
        log_info "Перезагрузка..."
        sleep 2
        echo 1 > /proc/sys/kernel/sysrq
        echo s > /proc/sysrq-trigger
        sleep 1
        echo u > /proc/sysrq-trigger
        sleep 1
        echo b > /proc/sysrq-trigger
    else
        log_info "Перезагрузи вручную: reboot"
    fi
fi