# MikroTik CHR Installer

Скрипт автоматической установки MikroTik Cloud Hosted Router (CHR) на Linux VPS/VDS серверы.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![English](https://img.shields.io/badge/lang-English-blue.svg)](README-EN.md)

## 📋 Описание

Этот скрипт полностью автоматизирует установку MikroTik Cloud Hosted Router (CHR) на любой Linux VPS/VDS сервер. Он выполняет всё: от загрузки образа CHR до настройки сети и записи на диск — одной командой.

### Ключевые возможности

- 🚀 **Установка одной командой** — полностью автоматизированный процесс
- 🌐 **Автоопределение сетевых настроек** — IP-адрес, шлюз, интерфейс
- 📦 **Автоустановка зависимостей** — работает на Debian/Ubuntu, CentOS, RHEL, Fedora
- 🔧 **Преднастроенный autorun** — CHR загружается с уже настроенной сетью
- ✅ **Валидация образа** — проверка MBR-сигнатуры и целостности
- 🔄 **Гибкие настройки** — выбор версии, пароля и режима установки

## 🎯 Сценарии использования

### 1. Быстрая миграция VPS на MikroTik

Замените Linux VPS на полноценный MikroTik роутер за несколько минут. Идеально для:
- Создания VPN-сервера (WireGuard, L2TP, PPTP, OpenVPN)
- Организации защищённого шлюза для инфраструктуры
- Построения удалённой точки управления сетью

### 2. Лабораторная среда

Быстрый деплой MikroTik для:
- Тестирования конфигураций RouterOS перед продакшеном
- Изучения администрирования MikroTik
- Подготовки к сертификации (MTCNA, MTCRE и др.)

### 3. Центральный VPN-хаб

Превратите дешёвый VPS в центральный VPN-хаб для связи нескольких площадок:
- Облачный роутер для распределённых сетей
- Резервная точка связи
- Оптимизация маршрутизации по географии

### 4. Управление трафиком и мониторинг

Разверните CHR для:
- Управления полосой пропускания и QoS
- Анализа трафика встроенными инструментами
- Файрвола и защитного шлюза

## 📦 Требования

- Linux VPS/VDS сервер (Debian, Ubuntu, CentOS, RHEL, Fedora)
- Root-доступ
- Минимум 128 MB RAM (рекомендуется 256 MB+)
- Минимум 128 MB дискового пространства
- Активное интернет-соединение
- **Поддерживаются оба режима загрузки**: Legacy BIOS и UEFI

## 🚀 Быстрый старт

### Установка одной командой

```bash
wget -qO- https://raw.githubusercontent.com/DmiRials/mikrotik-chr-installer/main/chr-installer.sh | bash
```

### Ручная установка

```bash
# Скачать скрипт
wget https://raw.githubusercontent.com/DmiRials/mikrotik-chr-installer/main/chr-installer.sh

# Сделать исполняемым
chmod +x chr-installer.sh

# Запустить установщик
sudo ./chr-installer.sh
```

## 📖 Примеры использования

### Базовая установка (интерактивная)

```bash
sudo ./chr-installer.sh
```

Скрипт выполнит:
1. Загрузку образа CHR
2. Определение сетевой конфигурации
3. Запрос подтверждения перед записью на диск
4. Предложение перезагрузки после установки

### Полностью автоматическая установка

```bash
sudo ./chr-installer.sh --yes --reboot
```

Без взаимодействия с пользователем — идеально для автоматизации.

### Выбор версии и пароля

```bash
sudo ./chr-installer.sh --version 7.14.3 --password MySecurePass123
```

### Чистая установка (без автонастройки)

```bash
sudo ./chr-installer.sh --clean
```

CHR загрузится с настройками по умолчанию. Полезно, когда хотите настроить всё вручную.

### Пример скрипта автоматизации

```bash
#!/bin/bash
# Деплой MikroTik CHR на несколько серверов

SERVERS="192.168.1.10 192.168.1.11 192.168.1.12"
PASSWORD="StrongPassword123"

for server in $SERVERS; do
    ssh root@$server "curl -sL https://example.com/chr-installer.sh | bash -s -- --yes --reboot --password $PASSWORD"
done
```

## ⚙️ Параметры командной строки

| Параметр | Описание |
|----------|----------|
| `--clean` | Чистая установка без autorun.scr (требуется ручная настройка) |
| `--force` | Принудительно скачать образ заново |
| `--no-verify` | Пропустить верификацию записи |
| `--yes`, `-y` | Автоматический режим, без подтверждений |
| `--reboot` | Автоперезагрузка после установки (требует `--yes`) |
| `--version VER` | Указать версию CHR (по умолчанию: 7.16.1) |
| `--password PASS` | Установить пароль admin (по умолчанию: PASSWORD) |
| `-h`, `--help` | Показать справку |

## 🔧 Что делает скрипт

1. **Проверяет зависимости** — устанавливает недостающие утилиты
2. **Скачивает образ CHR** — с официальных серверов MikroTik
3. **Валидирует образ** — проверяет MBR-сигнатуру и целостность
4. **Определяет сетевые настройки** — IP-адрес, шлюз, интерфейс
5. **Создаёт autorun.scr** — настраивает CHR для загрузки с вашими сетевыми параметрами
6. **Записывает на диск** — использует `dd` с direct I/O для надёжности
7. **Перезагружает** — в ваш новый MikroTik CHR

## 🌐 Доступ после установки

После установки и перезагрузки подключитесь к CHR через:

- **WinBox**: Подключение к IP-адресу сервера (порт 8291)
- **SSH**: `ssh admin@IP_ВАШЕГО_СЕРВЕРА`

> **Примечание**: Веб-интерфейс (WebFig) отключён по умолчанию из соображений безопасности. При необходимости его можно включить командой: `/ip service set www disabled=no`

Учётные данные по умолчанию:
- **Логин**: `admin`
- **Пароль**: указанный через `--password` (по умолчанию: `PASSWORD`)

## ⚠️ Важно

- **Все данные на целевом диске будут уничтожены!**
- Скрипт требует права root
- Убедитесь, что у вас есть доступ к консоли/KVM на случай проблем
- Сначала протестируйте в непродакшн-среде
- Бесплатная лицензия CHR ограничена скоростью 1 Mbps на upload

## 🔒 Рекомендации по безопасности

1. **Смените пароль по умолчанию** сразу после установки
2. **Отключите неиспользуемые сервисы** после первого входа
3. **Настройте правила файрвола** для защиты управляющего доступа
4. **Регулярно обновляйте RouterOS** до последней версии

## 📝 Конфигурация CHR по умолчанию

Скрипт autorun настраивает:

```routeros
/ip dns set servers=8.8.8.8,8.8.4.4
/ip service set telnet disabled=yes
/ip service set ftp disabled=yes
/ip service set www disabled=yes
/ip service set ssh disabled=no
/ip service set api disabled=yes
/ip service set api-ssl disabled=yes
/ip service set winbox disabled=no
/ip address add address=ВАШ_IP interface=ether1
/ip route add gateway=ВАШ_ШЛЮЗ
```

## 🛠️ Кастомизация autorun.scr

Вы можете отредактировать скрипт и добавить свою конфигурацию в `autorun.scr`. Это позволяет CHR загрузиться с полностью готовыми настройками — файрволом, VPN, пользователями и т.д.

### Где редактировать

Найдите в скрипте установщика блок создания autorun (поиск по `autorun.scr`):

```bash
cat > "$MOUNT_POINT/rw/autorun.scr" <<EOF
# Ваша конфигурация здесь
EOF
```

### Примеры кастомной конфигурации

#### Базовый файрвол для VPS

```routeros
# Защита от брутфорса SSH
/ip firewall filter
add chain=input protocol=tcp dst-port=22 src-address-list=ssh_blacklist action=drop comment="Drop SSH brute force"
add chain=input protocol=tcp dst-port=22 connection-state=new src-address-list=ssh_stage3 action=add-src-to-address-list address-list=ssh_blacklist address-list-timeout=1w
add chain=input protocol=tcp dst-port=22 connection-state=new src-address-list=ssh_stage2 action=add-src-to-address-list address-list=ssh_stage3 address-list-timeout=1m
add chain=input protocol=tcp dst-port=22 connection-state=new src-address-list=ssh_stage1 action=add-src-to-address-list address-list=ssh_stage2 address-list-timeout=1m
add chain=input protocol=tcp dst-port=22 connection-state=new action=add-src-to-address-list address-list=ssh_stage1 address-list-timeout=1m

# Базовые правила
add chain=input connection-state=established,related action=accept comment="Accept established"
add chain=input connection-state=invalid action=drop comment="Drop invalid"
add chain=input protocol=icmp action=accept comment="Accept ICMP"
add chain=input protocol=tcp dst-port=22 action=accept comment="Accept SSH"
add chain=input protocol=tcp dst-port=8291 action=accept comment="Accept WinBox"
add chain=input action=drop comment="Drop all other"
```

#### Ограничение доступа по IP

```routeros
# Разрешить управление только с определённых IP
/ip firewall address-list
add list=management address=YOUR_HOME_IP comment="Home IP"
add list=management address=YOUR_OFFICE_IP comment="Office IP"

/ip firewall filter
add chain=input src-address-list=management action=accept comment="Allow management IPs"
add chain=input protocol=tcp dst-port=22,8291,80,443 action=drop comment="Block management from others"
```

#### Настройка WireGuard VPN

```routeros
/interface wireguard
add name=wg0 listen-port=51820 private-key="YOUR_PRIVATE_KEY"

/interface wireguard peers
add interface=wg0 public-key="PEER_PUBLIC_KEY" allowed-address=10.0.0.2/32

/ip address
add address=10.0.0.1/24 interface=wg0

/ip firewall filter
add chain=input protocol=udp dst-port=51820 action=accept comment="Accept WireGuard"
```

#### Автоматический бэкап конфигурации

```routeros
# Создаём скрипт бэкапа
/system script
add name=backup-script source="/system backup save name=auto-backup"

# Планировщик запускает скрипт ежедневно в 03:00
/system scheduler
add name=daily-backup interval=1d on-event=backup-script start-time=03:00:00
```

#### Настройка NTP и часового пояса

```routeros
/system clock set time-zone-name=Europe/Moscow
/system ntp client set enabled=yes
/system ntp client servers add address=pool.ntp.org
```

### Полный пример кастомного autorun.scr

```bash
cat > "$MOUNT_POINT/rw/autorun.scr" <<EOF
# === Базовая настройка ===
/ip dns set servers=${DNS_SERVERS}
/ip dhcp-client remove [find]
/ip address add address=${ADDRESS} interface=[/interface ethernet find where name=ether1]
/ip route add gateway=${GATEWAY}
/user set 0 name=admin password=${ADMIN_PASSWORD}

# === Сервисы ===
/ip service set telnet disabled=yes
/ip service set ftp disabled=yes
/ip service set www disabled=no
/ip service set ssh disabled=no port=22
/ip service set api disabled=yes
/ip service set api-ssl disabled=yes
/ip service set winbox disabled=no

# === Файрвол ===
/ip firewall filter
add chain=input connection-state=established,related action=accept
add chain=input connection-state=invalid action=drop
add chain=input protocol=icmp action=accept
add chain=input protocol=tcp dst-port=22 action=accept
add chain=input protocol=tcp dst-port=8291 action=accept
add chain=input action=drop

# === Система ===
/system clock set time-zone-name=Europe/Moscow
/system identity set name=MikroTik-CHR
EOF
```

## 🐛 Решение проблем

### CHR не загружается
- Проверьте вывод консоли через VNC/KVM
- Убедитесь, что диск записан корректно
- Попробуйте режим `--clean` и настройте вручную

### Сеть не работает после загрузки
- Проверьте настройки IP и шлюза в CHR
- Убедитесь, что интерфейс называется `ether1`
- Проверьте правила файрвола у хостинг-провайдера

### Не удаётся подключиться через SSH/WinBox
- Подождите 1-2 минуты для полной загрузки CHR
- Проверьте правильность IP-адреса
- Проверьте файрвол/security groups хостинг-провайдера

## 📦 Варианты установки

В проекте доступны несколько скриптов для разных сценариев:

### Минимальная установка

| Скрипт | Язык | Описание |
|--------|------|----------|
| `chr-installer.sh` | RU | Базовый установщик с автонастройкой сети |
| `chr-installer-en.sh` | EN | Basic installer with network auto-config |

### С базовой настройкой безопасности

| Скрипт | Язык | Описание |
|--------|------|----------|
| `chr-installer-base-ru.sh` | RU | + Файрвол, защита от брутфорса, NTP, автобэкап |
| `chr-installer-base-en.sh` | EN | + Firewall, brute-force protection, NTP, auto-backup |

**Включает:**
- Защита от брутфорса SSH/WinBox
- Защита от DNS amplification атак
- Отключение небезопасных сервисов
- Настройка NTP и часового пояса
- Ежедневный автобэкап

### VPN-сервер (все протоколы)

| Скрипт | Язык | Описание |
|--------|------|----------|
| `chr-installer-adv-vpn-ru.sh` | RU | Полноценный VPN-сервер |
| `chr-installer-adv-vpn-en.sh` | EN | Full-featured VPN server |

**Включает все протоколы:**
- PPTP (порт 1723)
- L2TP/IPsec (порт 1701, UDP 500/4500) — автогенерация 12-символьного PSK
- SSTP (порт 443) — автоматический самоподписанный сертификат
- OpenVPN (порт 1194 UDP/TCP, 1195 TCP) — автоматический сертификат
- WireGuard (порт 51820) — автогенерация ключа сервера

**Дополнительные параметры VPN:**
```bash
--vpn-user USER      # VPN пользователь (по умолчанию: vpnuser)
--vpn-pass PASS      # Пароль VPN (генерируется автоматически)
--ipsec-secret KEY   # IPsec PSK (генерируется автоматически)
--wg-port PORT       # WireGuard порт (по умолчанию: 51820)
```

### 🚀 Быстрая установка одной командой

#### Базовая настройка с безопасностью (RU):
```bash
bash <(curl -sL https://raw.githubusercontent.com/DmiRials/mikrotik-chr-installer/main/chr-installer-base-ru.sh) --yes --reboot
```

#### Базовая настройка с безопасностью (EN):
```bash
bash <(curl -sL https://raw.githubusercontent.com/DmiRials/mikrotik-chr-installer/main/chr-installer-base-en.sh) --yes --reboot
```

#### VPN-сервер со всеми протоколами (RU):
```bash
bash <(curl -sL https://raw.githubusercontent.com/DmiRials/mikrotik-chr-installer/main/chr-installer-adv-vpn-ru.sh) --yes --reboot
```

#### VPN-сервер со всеми протоколами (EN):
```bash
bash <(curl -sL https://raw.githubusercontent.com/DmiRials/mikrotik-chr-installer/main/chr-installer-adv-vpn-en.sh) --yes --reboot
```

#### VPN-сервер с кастомными параметрами:
```bash
bash <(curl -sL https://raw.githubusercontent.com/DmiRials/mikrotik-chr-installer/main/chr-installer-adv-vpn-ru.sh) \
  --password MyAdminPass \
  --vpn-user myuser \
  --vpn-pass MyVPNPass123 \
  --ipsec-secret MyIPsecKey \
  --yes --reboot
```

## 📄 Лицензия

Проект распространяется под лицензией MIT — подробности в файле [LICENSE](LICENSE).

## 🤝 Участие в разработке

Приветствуются любые вклады! Смело создавайте Pull Request.

## 📮 Поддержка

Если возникли проблемы или вопросы — создайте Issue на GitHub.

---

**Отказ от ответственности**: Скрипт предоставляется как есть. Всегда делайте бэкапы и убедитесь в наличии консольного доступа перед запуском на продакшн-системах. MikroTik и RouterOS являются торговыми марками MikroTik SIA.
