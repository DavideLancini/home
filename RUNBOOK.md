# Runbook

Operazioni ricorrenti e diagnosi dei guasti.

## Verifiche rapide

```bash
# Home Assistant risponde? (porta 80, non 8123)
curl -sI http://192.168.1.37/

# Accesso pubblico
curl -s -o /dev/null -w "%{http_code}\n" https://ha.lancini.net/

# Stato di Proxmox e del tunnel
ssh proxmox 'uptime -p; systemctl is-active ha-tunnel.service; qm status 100'

# IP reale della VM — mai fidarsi della cache ARP
ssh proxmox 'qm guest cmd 100 network-get-interfaces' | grep -o '192\.168\.1\.[0-9]*'

# Porte in ascolto dentro la VM
ssh proxmox 'qm guest exec 100 --timeout 30 -- /bin/sh -c "netstat -tln"'
```

## Diagnosi: `ha.lancini.net` dà 502

Il `502` significa che nginx non trova nulla dietro al tunnel. Si risale la catena dal fondo:

1. **HA risponde in LAN?** `curl -sI http://192.168.1.37/`
   Se no → il problema è HA o la VM, salta al paragrafo successivo.
2. **Proxmox è raggiungibile?** `ssh proxmox 'uptime -p'`
   Se no ma il ping passa, l'host è in difficoltà: attendi, di solito rientra.
3. **Il tunnel è attivo?** `ssh proxmox 'systemctl is-active ha-tunnel.service'`
4. **Il capo del tunnel è in ascolto?** `ssh elisabetta 'sudo ss -tlnp | grep 8123'`
5. **nginx è su?** `ssh elisabetta 'systemctl is-active nginx'`

Il tunnel si riavvia da solo (`Restart=always`, keepalive 30s). Se un blocco è transitorio, rientra senza intervento.

## Diagnosi: Home Assistant non risponde

**Prima di tutto: verifica su quale porta ascolta.** Non dare per scontata la 8123.

```bash
ssh proxmox 'qm guest exec 100 --timeout 30 -- /bin/sh -c "netstat -tln"'
```

Poi, in ordine:

```bash
# La VM gira?
ssh proxmox 'qm status 100'

# Che IP ha davvero?
ssh proxmox 'qm guest cmd 100 network-get-interfaces' | grep -o '192\.168\.1\.[0-9]*'

# I container del Supervisor sono su?
ssh proxmox 'qm guest exec 100 --timeout 30 -- /usr/bin/docker ps --format "{{.Names}}"'

# Cosa dicono i log di HA
ssh proxmox 'qm guest exec 100 --timeout 30 -- /usr/bin/docker logs --tail 20 homeassistant'
```

I log del container sono in **UTC**, l'ora locale è CEST (+2). Confrontando i timestamp, tenerne conto per capire se un evento è recente.

## Riavviare Home Assistant

```bash
# Solo il Core (applica le modifiche a configuration.yaml)
ssh proxmox 'qm guest exec 100 --timeout 60 -- /usr/bin/ha core restart'

# Verifica della configurazione prima di riavviare
ssh proxmox 'qm guest exec 100 --timeout 120 -- /usr/bin/ha core check'
```

`ha core restart` è il modo corretto: `docker restart homeassistant` riavvia il container ma **non ricarica `configuration.yaml`**.

Se il Supervisor risponde `"Home Assistant is already running!"` a un `ha core start` mentre HA è chiaramente fermo, usare `restart`, che forza stop+start.

## Spegnere il mini PC

**Non usare il pulsante di accensione.** Genera uno spegnimento che HA gestisce male.

```bash
ssh proxmox 'qm shutdown 100 --timeout 90 && shutdown -h now'
```

Riaccensione da remoto via Wake-on-LAN:

```bash
wakeonlan 40:b0:34:fe:a2:62
```

## Ricreare la VM Home Assistant

Usare lo **script ufficiale**, non `qm create` a mano. Lo script è interattivo (whiptail), quindi va pilotato via `tmux`:

```bash
ssh proxmox

curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/vm/haos-vm.sh -o /tmp/haos-vm.sh
sed -i '1s/^\xEF\xBB\xBF//' /tmp/haos-vm.sh    # il BOM UTF-8 rompe lo shebang
tmux new-session -d -s haos -x 200 -y 50 "bash /tmp/haos-vm.sh"

# Poi, per ogni schermata:
tmux capture-pane -t haos -p     # legge
tmux send-keys -t haos Enter     # conferma
```

Attenzione ai default: alla schermata **`SSH DETECTED` il pulsante preselezionato è `<No>`**, che fa uscire lo script. Serve `tmux send-keys -t haos Left` prima dell'`Enter`.

Dopo la creazione, impostare l'IP statico:

```bash
ssh proxmox 'qm guest exec 100 --timeout 45 -- /usr/bin/ha network update enp6s18 \
  --ipv4-method static --ipv4-address 192.168.1.37/25 \
  --ipv4-gateway 192.168.1.1 --ipv4-nameserver 192.168.1.1'
```

L'interfaccia dentro la VM si chiama `enp6s18` (diversa da `nic0` dell'host).

## Passthrough USB (chiavetta Zigbee)

```bash
# Identifica il device sull'host
ssh proxmox 'ls -l /dev/serial/by-id/'

# Aggiungilo alla VM per Vendor/Device ID, non per porta fisica
ssh proxmox 'qm set 100 -usb0 host=VVVV:PPPP'
```

Usare l'ID e non la porta: la porta cambia se sposti la chiavetta.

Metti la chiavetta su una prolunga USB di qualche metro — il mini PC genera interferenza a 2.4 GHz che degrada la rete Zigbee.

## Certificato TLS

Il rinnovo è automatico. Per verificarlo dopo modifiche a nginx:

```bash
ssh elisabetta 'sudo certbot renew --cert-name ha.lancini.net --dry-run'
```

Se fallisce, controlla che `/etc/nginx/sites-enabled/ha-acme` esista: serve a far passare le challenge in HTTP.

Il `--dry-run` può restare appeso e tenere un lock; in quel caso il tentativo successivo dice `Another instance of Certbot is already running`. Attendere che si liberi.

## Backup

Ancora da configurare. Due livelli, complementari:

- **Home Assistant** — Impostazioni → Sistema → Backup, con copia su storage esterno
- **Proxmox** — Datacenter → Backup, job schedulato

Il backup della VM non sostituisce quello di HA: il primo ripristina la macchina, il secondo la configurazione domotica.
