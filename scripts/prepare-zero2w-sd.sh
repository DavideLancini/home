#!/bin/bash
# Scrive Raspberry Pi OS su microSD e lo preconfigura per fare da
# programmatore seriale delle smart plug BK7231N.
#
# Configura: utente, WiFi (password letta da NetworkManager), SSH con chiave,
# UART hardware libera dal Bluetooth, console seriale disattivata.
#
# Uso:  sudo ./prepare-zero2w-sd.sh /dev/sdX

set -euo pipefail

DEV="${1:-}"
IMG="$HOME/6Local/raspios-lite-arm64.img.xz"
HOSTNAME=zero2w
USERNAME=davidelancini
WIFI_SSID=DiteAmici
PUBKEY="$HOME/.ssh/id_ed25519_dawn.pub"

die() { echo "ERRORE: $*" >&2; exit 1; }

[ -n "$DEV" ] || die "specificare il device: $0 /dev/sdX"
[ -b "$DEV" ] || die "$DEV non è un dispositivo a blocchi"
[ -f "$IMG" ] || die "immagine non trovata: $IMG"
[ -f "$PUBKEY" ] || die "chiave pubblica non trovata: $PUBKEY"

# Rifiuta i dischi non rimovibili: evita di sovrascrivere il disco di sistema
[ "$(lsblk -ndo RM "$DEV")" = "1" ] || die "$DEV non è rimovibile — rifiuto di scriverci"

echo "=== Device: $DEV"
lsblk -o NAME,SIZE,FSTYPE,LABEL "$DEV"
echo
read -rp "Tutti i dati su $DEV saranno cancellati. Continuare? [scrivi SI] " ans
[ "$ans" = "SI" ] || die "annullato"

# --- scrittura immagine
echo "=== Scrittura immagine (circa 8 minuti)..."
umount "${DEV}"* 2>/dev/null || true
xzcat "$IMG" | dd of="$DEV" bs=4M conv=fsync status=progress
sync
partprobe "$DEV" 2>/dev/null || true
sleep 4

# --- montaggio partizione boot
BOOT=$(lsblk -lno NAME,FSTYPE "$DEV" | awk '$2=="vfat"{print "/dev/"$1; exit}')
[ -n "$BOOT" ] || die "partizione boot non trovata"

MNT=$(mktemp -d)
mount "$BOOT" "$MNT"
trap 'sync; umount "$MNT" 2>/dev/null; rmdir "$MNT" 2>/dev/null' EXIT

echo "=== Configurazione in $BOOT"

touch "$MNT/ssh"

# --- password WiFi: NetworkManager la conosce già
WPA=$(nmcli -s -g 802-11-wireless-security.psk connection show "$WIFI_SSID" 2>/dev/null || true)
if [ -z "$WPA" ]; then
    echo "Password WiFi per '$WIFI_SSID' (non trovata in NetworkManager):"
    read -rsp "> " WPA; echo
fi

# Password utente casuale: l'accesso è via chiave, non serve conoscerla
HASH=$(openssl passwd -6 "$(head -c 18 /dev/urandom | base64 | tr -d '/+=')")

cat > "$MNT/custom.toml" <<TOML
config_version = 1

[system]
hostname = "$HOSTNAME"

[user]
name = "$USERNAME"
password = "$HASH"
password_encrypted = true

[ssh]
enabled = true
password_authentication = false
authorized_keys = [ "$(cat "$PUBKEY")" ]

[wlan]
ssid = "$WIFI_SSID"
password = "$WPA"
password_encrypted = false
country = "IT"

[locale]
keymap = "it"
timezone = "Europe/Rome"
TOML

# --- UART hardware libera dal Bluetooth
# Sullo Zero 2 W la UART buona (PL011) è assegnata al Bluetooth: senza
# disable-bt si ottiene la mini-UART, il cui baud rate dipende dalla frequenza
# della CPU ed è inaffidabile per programmare un microcontrollore.
CFG="$MNT/config.txt"
grep -q "^enable_uart=1" "$CFG" || echo "enable_uart=1" >> "$CFG"
grep -q "^dtoverlay=disable-bt" "$CFG" || echo "dtoverlay=disable-bt" >> "$CFG"

# --- console seriale via: altrimenti il kernel scrive sulla porta durante
#     il flash e corrompe la comunicazione col chip
sed -i 's/console=serial0,[0-9]* //' "$MNT/cmdline.txt"

# --- script per installare gli strumenti al primo accesso
cat > "$MNT/setup-flashtools.sh" <<'EOF'
#!/bin/bash
set -e
sudo apt-get update
sudo apt-get install -y python3-pip python3-venv git
python3 -m venv ~/.venv-flash
~/.venv-flash/bin/pip install --upgrade pip
~/.venv-flash/bin/pip install ltchiptool bk7231tools
echo "Fatto. Strumenti in ~/.venv-flash/bin/"
echo "Verifica la UART:  ls -l /dev/ttyAMA0"
EOF
chmod +x "$MNT/setup-flashtools.sh"

echo
echo "=== Fatto."
echo "    Inserisci la SD nello Zero 2 W e accendilo."
echo "    Primo avvio: 2-3 minuti (espande il filesystem e si connette al WiFi)."
echo "    Poi: ssh $USERNAME@${HOSTNAME}.local"
