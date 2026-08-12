#!/bin/bash
# Estrae i backup di Home Assistant dalla VM e li conserva sull'host Proxmox.
#
# La VM li tiene in /mnt/data/supervisor/backup, che vive sullo stesso disco
# virtuale della VM: se quello si corrompe, spariscono anche i backup.
# Questo script li copia fuori, sul filesystem dell'host.
#
# Installato in /usr/local/bin/ha-backup-pull.sh su proxmox, lanciato da
# systemd timer (ha-backup-pull.timer) ogni notte.

set -euo pipefail

VMID=100
DEST=/var/lib/vz/dump/ha-backups
KEEP=14          # quanti backup conservare sull'host
LOG_TAG=ha-backup-pull

log() { logger -t "$LOG_TAG" "$*"; echo "$*"; }

mkdir -p "$DEST"

if ! qm status "$VMID" 2>/dev/null | grep -q running; then
    log "VM $VMID non in esecuzione, esco"
    exit 0
fi

# Chiede a HA di creare un backup fresco. Il nome include la data.
NAME="auto-$(date +%Y-%m-%d)"
log "creo backup '$NAME' nella VM"

SLUG=$(qm guest exec "$VMID" --timeout 600 -- \
        /usr/bin/ha backups new --name "$NAME" 2>/dev/null \
      | grep -oE 'slug: [a-f0-9]+' | cut -d' ' -f2 || true)

if [ -z "$SLUG" ]; then
    log "ERRORE: creazione backup fallita"
    exit 1
fi

log "backup creato: slug=$SLUG"

# Estrae il .tar dalla VM. base64 perché guest exec non gestisce binario.
SRC="/mnt/data/supervisor/backup/${SLUG}.tar"
OUT="$DEST/${NAME}-${SLUG}.tar"

qm guest exec "$VMID" --timeout 600 -- \
    /bin/sh -c "base64 < $SRC" 2>/dev/null \
  | python3 -c "
import sys, json, base64
d = json.load(sys.stdin).get('out-data', '')
sys.stdout.buffer.write(base64.b64decode(d))
" > "$OUT"

if [ ! -s "$OUT" ]; then
    log "ERRORE: estrazione fallita, file vuoto"
    rm -f "$OUT"
    exit 1
fi

log "estratto in $OUT ($(du -h "$OUT" | cut -f1))"

# Rimuove i backup vecchi sull'host, tenendo i più recenti.
cd "$DEST"
ls -1t *.tar 2>/dev/null | tail -n +$((KEEP + 1)) | while read -r old; do
    log "rimuovo backup vecchio: $old"
    rm -f "$old"
done

# Nella VM ne tiene solo 3: lì lo spazio è poco.
qm guest exec "$VMID" --timeout 120 -- /bin/sh -c \
    "ls -1t /mnt/data/supervisor/backup/*.tar 2>/dev/null | tail -n +4 | xargs -r rm -f" \
    >/dev/null 2>&1 || true

log "completato"
