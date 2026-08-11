# HOME — Home Assistant su mini PC

## Stato installazione

Installato l'11 agosto 2026.

**Hardware:** HP EliteDesk 800 G2 DM 65W — i5-6400T (4 core), 7.6 GB RAM, NVMe 238 GB.

| Componente | Valore |
|---|---|
| Proxmox VE | 9.2.2, kernel 7.0.14-11-pve |
| IP Proxmox | `192.168.1.2/25` — WebUI `https://192.168.1.2:8006` |
| SSH | `ssh proxmox` (chiave `id_ed25519_dawn`, no password) |
| VM Home Assistant | VMID 100 `haos-18.2`, creata con lo script ufficiale |
| IP Home Assistant | `192.168.1.37` (statico) — WebUI `http://192.168.1.37:8123` |
| Accesso pubblico | `https://ha.lancini.net` |
| MAC Proxmox | `40:b0:34:fe:a2:62` |
| MAC VM HA | `02:9D:16:D9:80:13` |

Rete `192.168.1.0/25` (arriva a `.126`, non `.254`), gateway `192.168.1.1`.

**Piano di indirizzamento:**

| Range | Uso |
|---|---|
| `.1` | Gateway/router |
| `.2` | Proxmox (reservation) |
| `.3` | Occupato (MAC `a8:fa:d8:3b:e5:0b`, dispositivo non identificato) |
| `.4`–`.36` | Riservati nel modem |
| `.37`+ | Liberi per assegnazione statica — **`.37` = Home Assistant** |
| `.50`–`.126` | Pool DHCP |

**Configurazione applicata:**

- Repo `pve-no-subscription` (formato deb822), nag di subscription rimosso
- `apt` forzato su IPv4 (`/etc/apt/apt.conf.d/99force-ipv4`) — l'IPv6 sull'host non riceve Router Advertisement
- IPv4 preferito nella risoluzione dei nomi (`/etc/gai.conf`)
- Timezone `Europe/Rome`
- Wake-on-LAN persistente via `wol@nic0.service` (`Wake-on: g`)
- VM HA con `onboot=1`, QEMU guest agent attivo
- `tmux`, `ethtool`, `htop`, `iotop`, `lm-sensors` installati sull'host

**Note sull'installazione:**

- L'ISO Proxmox non fa boot UEFI su questo hardware: errore `relocation 0x41615252 is not implemented yet` (bug del boot ibrido HFS+). Risolto con **Ventoy**.
- L'interfaccia di rete si chiama **`nic0`**, non `enp1s0` — nuovo schema di naming di Proxmox 9.
- VT-x e VT-d/IOMMU già attivi nel BIOS (verificato via `dmesg | grep DMAR`), pronti per il passthrough iGPU di Frigate.

## Accesso remoto — implementazione

Home Assistant è pubblicato su `https://ha.lancini.net` tramite reverse tunnel SSH verso il VPS `elisabetta` (`87.106.233.97`), che fa da reverse proxy.

```
browser → https://ha.lancini.net (nginx su elisabetta)
        → 127.0.0.1:8123 (capo del tunnel)
        → tunnel SSH
        → 192.168.1.37:8123 (HA in LAN)
```

**Su Proxmox** — `/etc/systemd/system/ha-tunnel.service`, `Restart=always`, keepalive ogni 30s. Usa la chiave dedicata `/root/.ssh/id_ed25519_tunnel` (separata dalle altre, così è revocabile da sola).

**Su elisabetta:**

- `/etc/nginx/sites-available/ha.lancini.net` — proxy verso `127.0.0.1:8123` con header WebSocket (`Upgrade`/`Connection`), senza i quali la UI di HA resta congelata
- `/etc/nginx/sites-available/ha-acme` — serve `/.well-known/acme-challenge/` in HTTP senza redirect. Necessario perché `00-redirect-80-to-443` manderebbe la challenge su HTTPS, e il rinnovo fallirebbe
- Chiave del tunnel in `~/.ssh/authorized_keys` con `restrict,port-forwarding` — può solo inoltrare porte, niente shell
- Certificato Let's Encrypt, rinnovo automatico verificato con `--dry-run`

**In Home Assistant** — `configuration.yaml` con `use_x_forwarded_for: true` e `trusted_proxies`. Senza, HA risponde `400` a ogni richiesta proxata.

**Da fare:**

- [x] DHCP reservation sul router per `40:b0:34:fe:a2:62` → `192.168.1.2`
- [x] IP statico Home Assistant → `192.168.1.37`
- [x] BIOS: `After Power Loss` → *Power On*
- [x] Accesso remoto pubblico via `ha.lancini.net`
- [ ] Onboarding Home Assistant (creazione utente admin)
- [ ] Chiavetta Zigbee + passthrough USB alla VM

## Incidente 11 agosto 2026 — diagnosi

Dopo l'onboarding, HA smetteva di rispondere su `192.168.1.37:8123`. Il problema si è ripresentato tre volte, e sono state necessarie tre ricreazioni della VM prima di risolverlo.

**Due cause distinte si sono sovrapposte, e questo ha reso la diagnosi molto più lunga del dovuto.**

*Causa 1 — depistaggio.* Dopo ogni ricreazione la VM prendeva un indirizzo DHCP nuovo (`.87`, poi `.73`), mentre l'entry ARP di `192.168.1.37` sopravviveva come residuo della VM precedente. Il `ping` su `.37` rispondeva, quindi sembrava la macchina giusta. Questo ha fatto cercare il problema dentro HA anziché nell'indirizzamento, e ha portato a dichiarare "risolto" quando non lo era.

*Causa 2 — il guasto vero.* Con l'IP corretto verificato, HA si bloccava comunque: caricava fino a 19 thread, consumava ~1600 tick di CPU, poi si fermava in `do_epoll_wait` senza mai aprire la porta 8123. Nessun crash, nessun log, nessun errore. Riproducibile sistematicamente dopo l'onboarding.

**Ipotesi seguite e scartate lungo la strada:**

| Ipotesi | Perché scartata |
|---|---|
| Spegnimento col pulsante (`Power key pressed short`) | Il problema si è ripresentato senza spegnimenti |
| Blocco `http:`/`trusted_proxies` errato | Rimosso, nessun cambiamento |
| Database SQLite corrotto (WAL 659 KB, `.db` 4 KB) | WAL spostato, nessun cambiamento |
| Integrazione Bluetooth su VM senza hardware | Non presente in `core.config_entries` |
| Configurazione o integrazioni | La recovery mode le bypassa e il sintomo restava |
| `--cpu host` incompatibile | Cambiato in `x86-64-v2-AES`, ma non era quello |

Un errore mio ha peggiorato la diagnosi: un `cat >> configuration.yaml` ha **sovrascritto** il file invece di accodare, cancellando `default_config:` e gli include. Ripristinato, con i file `automations.yaml`/`scripts.yaml`/`scenes.yaml` ricreati.

**Lezioni operative:**

- Dopo aver ricreato una VM, chiedere l'IP al guest agent — mai fidarsi della cache ARP, che sopravvive con lo stesso MAC. I log del container dicevano `Announcing http://192.168.1.73:8123` fin dall'inizio
- `ping` che risponde non implica che sia la macchina giusta
- Per accodare a un file usare `tee -a` o verificare il contenuto dopo la scrittura
- Su una piattaforma con installer ufficiale, usarlo — anche quando è interattivo e sembra più rapido replicarne i comandi a mano

**Epilogo.** Dopo che anche una VM creata a mano con `--cpu x86-64-v2-AES` si è bloccata allo stesso modo (HA caricava 19 thread, consumava ~1600 tick di CPU, poi si fermava in `do_epoll_wait` senza mai aprire la 8123), la VM è stata ricreata con lo **script ufficiale della community** — che funziona al primo colpo.

La configurazione prodotta dallo script è quasi identica a quella manuale (`q35`, `ovmf`, `virtio`, `discard`, `ssd`), con una differenza: **non specifica `--cpu`**, quindi eredita il default `kvm64`. È l'unica variabile rimasta a distinguere le due installazioni.

**Come lanciare lo script in modo non interattivo** (è basato su whiptail):

```bash
curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/vm/haos-vm.sh -o /tmp/haos-vm.sh
sed -i '1s/^\xEF\xBB\xBF//' /tmp/haos-vm.sh   # rimuove il BOM UTF-8, che rompe lo shebang
tmux new-session -d -s haos -x 200 -y 50 "bash /tmp/haos-vm.sh"
tmux capture-pane -t haos -p    # legge la schermata
tmux send-keys -t haos Enter    # risponde
```

Attenzione ai default dei dialoghi: alla schermata `SSH DETECTED` il pulsante preselezionato è `<No>`, che fa uscire lo script — serve un `Left` prima dell'`Enter`.

## Decisione

Proxmox VE bare-metal sul mini PC, Home Assistant OS come VM.

**Perché:** HA OS bare-metal è un sistema chiuso (Buildroot, filesystem immutabile, no `apt`) — ci giri solo add-on Supervisor. Proxmox mantiene HA OS completo (add-on, aggiornamenti one-click, backup nativi) e lascia il mini PC libero per altri servizi in VM/LXC.

**Alternative scartate:**

| Opzione | Perché no |
|---|---|
| HA OS bare-metal | Il mini PC farebbe solo HA |
| HA Container (Docker) | Niente add-on né Supervisor |
| XCP-ng | Xen Orchestra da compilare o a pagamento |
| Incus | Ottimo ma solo CLI/UI minimale |
| TrueNAS SCALE | Risolve lo storage, non la virtualizzazione |
| Unraid | Non FOSS |

Proxmox VE: AGPLv3, base Debian + KVM/QEMU + LXC. La subscription copre solo repo enterprise e supporto — nessun limite funzionale senza.

## Installazione

### 1. Proxmox VE

1. ISO da <https://www.proxmox.com/en/downloads>
2. Flash su USB (`dd` o Balena Etcher)
3. BIOS: Secure Boot **off**, virtualizzazione (VT-x/AMD-V + VT-d/IOMMU) **on**, boot da USB
4. Installer: filesystem ext4 (ZFS solo con RAM abbondante e più dischi), IP statico, hostname, password root, email
5. Rimuovi USB, riavvia → `https://<ip>:8006` (utente `root`, realm PAM)

### 2. Post-install Proxmox

```bash
# Repo no-subscription + rimozione nag
bash -c "$(curl -fsSL https://github.com/community-scripts/ProxmoxVE/raw/main/tools/pve/post-pve-install.sh)"
```

Poi:

```bash
apt update && apt full-upgrade -y
reboot
```

### 3. VM Home Assistant OS

```bash
bash -c "$(curl -fsSL https://github.com/community-scripts/ProxmoxVE/raw/main/vm/haos-vm.sh)"
```

Lo script scarica l'immagine ufficiale `haos_ova-*.qcow2` e crea la VM. Impostazioni consigliate: 2 vCPU, 4 GB RAM, 32 GB disco, avvio automatico all'accensione.

Alternativa manuale: scarica `haos_ova-*.qcow2` dalle [release ufficiali](https://github.com/home-assistant/operating-system/releases), crea la VM (BIOS **OVMF/UEFI**, macchina `q35`) e importa il disco con `qm importdisk`.

### 4. Configurazione HA

1. `http://homeassistant.local:8123` → onboarding
2. IP statico via reservation DHCP sul router (l'MDNS non è affidabile per le integrazioni)
3. Backup automatici verso storage esterno

## Passthrough USB (Zigbee/Z-Wave)

Se arriva una chiavetta (SkyConnect, Sonoff ZBDongle, Aeotec):

1. `ls -l /dev/serial/by-id/` sull'host Proxmox
2. VM → Hardware → Add → USB Device → **Use USB Vendor/Device ID** (non la porta fisica, cambia se sposti la chiavetta)
3. Prolunga USB per allontanarla dal mini PC — l'interferenza a 2.4 GHz degrada la rete Zigbee

## Backup

- **HA**: backup nativi Settings → System → Backups, con add-on Samba/Google Drive per copia esterna
- **Proxmox**: Datacenter → Backup, job schedulato su storage esterno
- Regola 3-2-1: la copia della VM non sostituisce quella dei dati HA

## Dispositivi & Integrazioni

### Attuali

| Device | Integrazione | Note |
|---|---|---|
| Smart plug (1×) | Tuya / SmartLife | Energy monitoring |
| Videocamera animali | RTSP/HTTP | Frigate fuori scope per ora |
| Smart TV | HDMI-CEC / Tuya | Controllo accensione/input/volume |
| Luci smart | Zigbee / Tuya / Philips Hue | Preferire Zigbee2MQTT |
| Alexa | Emulated Hue / IFTTT | Controlla HA device, not vice versa |
| Google Assistant | Google Home integration | OAuth, tutto cloud |
| HA Voice assistant | ESPHome + mic/speaker | Local only (o mini PC host Ollama) |

### Roadmap (2026 Q3+)

- [ ] Contatore smart (monitoraggio gas/elettricità)
- [ ] Videocamera salotto (Frigate: Coral TPU o iGPU passthrough)
- [ ] Videocamera porta (person detection)
- [x] Citofono video smart (intercomunicazione HA)
- [ ] Sensori perdita acqua (2-3 pezzi)
- [ ] Rilevatore fumo/gas Zigbee

## Automazioni climatiche & tende

### Monitoraggio temperatura (sensori wireless)

Misurare temperatura per pilotare i condizionatori portatili via smart plug.

**Opzioni sensori:**
- **Zigbee** (consigliato): TINT, TuYa Zigbee, Aqara — batteria 1-2 anni, local-only
- **WiFi**: TuYa WiFi — sempre cloud, consumi alti
- **Bluetooth**: LYWSD03MMC — local con gateway Bluetooth, batteria lunga

Setup:
1. Sensori Zigbee nelle stanze chiave (salotto, camera, studio)
2. Zigbee2MQTT legge temperature → `sensor.<room>_temperature`
3. HA automazioni trigger su soglie

### Automazioni condizionatori

```yaml
# automation.yaml

- alias: "AC salotto ON - temperatura > 28°C"
  trigger:
    platform: numeric_state
    entity_id: sensor.salotto_temperature
    above: 28
  action:
    service: switch.turn_on
    target:
      entity_id: switch.ac_salotto_smart_plug

- alias: "AC salotto OFF - temperatura < 24°C"
  trigger:
    platform: numeric_state
    entity_id: sensor.salotto_temperature
    below: 24
  action:
    service: switch.turn_off
    target:
      entity_id: switch.ac_salotto_smart_plug
```

**Opzioni avanzate:**
- Isteresys (range: ON a 28°C, OFF a 24°C) → evita on/off continui
- Orari (non accendere AC di notte anche se caldo)
- Override manuale (pulsante HA per override temporaneo)
- Notifiche (alert se AC acceso > 4 ore)

### Serratura smart

Cambio serratura già in programma — integra una smart lock per accesso remoto, log, automazioni.

**Opzioni Zigbee:**

| Modello | Protocollo | Prezzo | Note |
|---|---|---|---|
| **Aqara Smart Lock U100** | Zigbee 3.0 | ~120€ | Ottima, batteria 1 anno, log storico, temporanea accessi |
| **Tuya Zigbee Smart Lock** | Zigbee 3.0 | ~60€ | Budget, funziona, batteria ~8 mesi |
| **Yale Assure SL2** | Zigbee 3.0 | ~200€ | Premium, affidabilità altissima, bell'estetica |
| **Nuki Smart Lock Pro** | WiFi/Bluetooth | ~250€ | Top, ma WiFi → sempre cloud, no Zigbee |

**Raccomandazione: Aqara U100** — miglior rapporto qualità/prezzo, Zigbee locale, batteria buona, HA integration perfetta.

**Setup HA:**

```yaml
# Automazioni accesso

automation:
  - alias: "Porta aperta - notifica"
    trigger:
      platform: state
      entity_id: lock.porta_principale
      to: "unlocked"
    action:
      - service: notify.telegram
        data:
          message: "🔓 Porta sbloccata alle {{ now().strftime('%H:%M') }}"

  - alias: "Sblocca porta da remoto (via HA)"
    trigger:
      platform: homeassistant
      event: automation_triggered
    action:
      - service: lock.unlock
        target:
          entity_id: lock.porta_principale

  - alias: "Auto-lock dopo 30 sec se dimenticato"
    trigger:
      platform: state
      entity_id: lock.porta_principale
      to: "unlocked"
      for: "00:00:30"
    action:
      - service: lock.lock
        target:
          entity_id: lock.porta_principale
      - service: notify.telegram
        data:
          message: "🔒 Porta richiusa automaticamente (dimenticata aperta)"

  - alias: "Accesso temporaneo per ospiti"
    description: "Crea accessi monouso per ospiti via HA"
    # Aqara supporta PIN temporanei tramite integrazioni
```

**Funzionalità:**
- ✓ Sblocca/blocca da remoto (Tailscale + HA webui)
- ✓ Log storico completo (chi ha aperto, quando)
- ✓ PIN monouso per ospiti/corrieri (gestito via HA)
- ✓ Notifiche istantanee aperture/chiusure
- ✓ Automazioni scenari (esempio: torna a casa → sblocca porta + accendi luce ingresso)
- ✓ Batteria: ~12 mesi (Aqara), avviso automatico

**Installazione:**
- Compatibile con cilindri europei standard (99% serrature italiane)
- Richiede batterie AA/AAA (non 12V)
- Zigbee2MQTT lo rileva automaticamente
- Zero modifche alla porta, rimovibile in 5 minuti

**Alternativa DIY (ESPHome):**
Se vuoi massima libertà → motoriduttore + relay su ESP32, ma serve ingegneria meccanica (costi di machining).

### Citofono video smart

Integrazione intercomunicazione con HA, notifiche persona detected, registrazione, sblocco porta remoto.

**Opzioni:**

| Modello | Protocollo | Prezzo | Note |
|---|---|---|---|
| **Dahua VTO2211G** | IP (SIP/RTSP) | ~150€ | Affidabile, integrazione HA facile, supporta SIP |
| **Tuya Video Doorbell** | WiFi/Cloud | ~80€ | Budget, ma cloud-dependent |
| **Tapo D230** | WiFi/Cloud | ~100€ | Decente, ma cloud TP-Link |
| **DIY: Tapo C100** | WiFi/RTSP | ~40€ | Semplice camera, non citofono vero |

**Raccomandazione: Dahua VTO2211G** — IP puro, SIP nativo, RTSP locale, integrazione HA ottimale, niente cloud obbligatorio.

**Setup HA:**

```yaml
# configuration.yaml

# Integrazione citofono SIP (richiede asterisk/freeswitch oppure MQTT relay)
camera:
  - platform: ffmpeg
    name: "Citofono video"
    input: "rtsp://citofono_ip:554/stream1"

# Oppure via ONVIF (se il citofono lo supporta)
onvif:
  host: citofono_ip
  port: 8080

# Automazione: notifica quando qualcuno suona
automation:
  - alias: "Citofono - Suoneria + notifica"
    trigger:
      platform: webhook
      webhook_id: doorbell_ring  # il citofono invia POST a questo webhook
    action:
      - service: notify.telegram
        data:
          message: "🔔 Qualcuno al citofono"
          data:
            photo:
              url: "http://citofono_ip:80/cgi-bin/snapshot.cgi"
      - service: media_player.play_media
        target:
          entity_id: media_player.salotto_speaker  # riproduci suoneria
        data:
          media_content_id: "http://ha:8123/local/suoneria.mp3"
          media_content_type: "audio/mpeg"

  - alias: "Citofono - Sblocca porta da remoto"
    trigger:
      platform: webhook
      webhook_id: unlock_door_via_doorbell
    action:
      - service: lock.unlock
        target:
          entity_id: lock.porta_principale
      - service: notify.telegram
        data:
          message: "🔓 Porta sbloccata dal citofono"
```

**Integrazione intercomunicazione vocale:**

Se il citofono supporta SIP (Dahua lo fa), puoi integrarti con Asterisk/PJSUA per risposte vocali live:

```bash
# Su mini PC / LXC Asterisk
pjsua --local-port=5060 --registrar=sip:citofono_ip --id=sip:mini_pc@citofono_ip
```

Poi da HA puoi inviare audio bidiezionale (microfono + speaker del mini PC = vivavoce).

**Cablaggio:**

- PoE (Power over Ethernet) — un solo cavo, no alimentatore separato
- Cavo CAT6 nella scatola citofono verso switch PoE nel mini PC area
- RTSP stream locale (zero latency, no cloud)
- Opzionale: relay 12V per sblocco porta (connesso direttamente al citofono o via relay HA)

### Mini serra — automazioni clima & luci

Controllo completo: temperature, umidità, irrigazione, fotoperiodon.

**Sensori necessari:**

| Sensore | Protocollo | Prezzo | Funzione |
|---|---|---|---|
| Temperatura/Umidità | Zigbee | ~15€ | Monitoraggio clima |
| Sensore luce | Zigbee | ~20€ | Misurazione illuminazione, PAR (opzionale) |
| Sensore umidità suolo | WiFi/Zigbee custom | ~10€ | Trigger irrigazione |
| CO₂ (opzionale) | Zigbee | ~30€ | Ventilazione smart |

**Attuatori:**

| Dispositivo | Tipo | Prezzo | Funzione |
|---|---|---|---|
| Strisce LED grow | WiFi smart/relay | ~30€ | Illuminazione fotoperiodon (12h on/off) |
| Ventilatore estrattore | Smart plug relay | ~20€ | Ventilazione (trigger umidità > 70%) |
| Valvola irrigazione | Solenoid WiFi/Zigbee | ~25€ | Irrigazione automatica |
| Umidificatore | Smart plug | ~25€ | Aumenta umidità se < 40% |

**Setup HA automazioni:**

```yaml
# automation.yaml

# Fotoperiodon: luci accese 14h/giorno (crescita vegetativa)
- alias: "Serra - Luci ON (mattino)"
  trigger:
    platform: time
    at: "06:00:00"
  action:
    service: light.turn_on
    target:
      entity_id: light.serra_grow_led

- alias: "Serra - Luci OFF (sera)"
  trigger:
    platform: time
    at: "20:00:00"
  action:
    service: light.turn_off
    target:
      entity_id: light.serra_grow_led

# Ventilazione: accendi se umidità > 70%
- alias: "Serra - Ventilatore ON (umidità alta)"
  trigger:
    platform: numeric_state
    entity_id: sensor.serra_humidity
    above: 70
  action:
    service: switch.turn_on
    target:
      entity_id: switch.serra_ventilatore

- alias: "Serra - Ventilatore OFF (umidità < 60%)"
  trigger:
    platform: numeric_state
    entity_id: sensor.serra_humidity
    below: 60
  action:
    service: switch.turn_off
    target:
      entity_id: switch.serra_ventilatore

# Irrigazione: ogni 2 giorni se umidità suolo < 40%
- alias: "Serra - Irrigazione (umidità suolo bassa)"
  trigger:
    platform: time
    at: "10:00:00"
  condition:
    - condition: numeric_state
      entity_id: sensor.serra_soil_moisture
      below: 40
  action:
    - service: switch.turn_on
      target:
        entity_id: switch.serra_valvola_irrigazione
    - delay: "00:00:30"  # 30 sec irrigazione
    - service: switch.turn_off
      target:
        entity_id: switch.serra_valvola_irrigazione

# Riscaldamento: se temperatura < 18°C (piante delicate)
- alias: "Serra - Riscaldatore ON"
  trigger:
    platform: numeric_state
    entity_id: sensor.serra_temperature
    below: 18
  action:
    service: switch.turn_on
    target:
      entity_id: switch.serra_riscaldatore

- alias: "Serra - Riscaldatore OFF"
  trigger:
    platform: numeric_state
    entity_id: sensor.serra_temperature
    above: 25
  action:
    service: switch.turn_off
    target:
      entity_id: switch.serra_riscaldatore

# Notifiche anomalie
- alias: "Serra - Alert temperatura bassa"
  trigger:
    platform: numeric_state
    entity_id: sensor.serra_temperature
    below: 15
    for: "00:05:00"
  action:
    - service: notify.telegram
      data:
        message: "⚠️ Serra: temperatura bassa ({{ states('sensor.serra_temperature') }}°C)"
```

**Dashboard HA (Serra):**

```yaml
# ui-lovelace.yaml section
cards:
  - type: entities
    title: "🌱 Mini Serra"
    entities:
      - sensor.serra_temperature
      - sensor.serra_humidity
      - sensor.serra_soil_moisture
      - sensor.serra_light_level
      - light.serra_grow_led
      - switch.serra_ventilatore
      - switch.serra_valvola_irrigazione
      - switch.serra_riscaldatore

  - type: thermostat
    entity: climate.serra_temperature  # solo se hai clima/termostato
    
  - type: history-stats
    title: "Ore luci/giorno"
    entity: light.serra_grow_led
    stat_period: day
```

**Setup fisico:**

1. **Sensori Zigbee** in giro per la serra (temperatura, umidità, suolo)
2. **LED grow** 120-200W (full spectrum, 12-14h/giorno)
3. **Ventilatore estrattore** (estrae aria umida)
4. **Valvola irrigazione solenoid 12V** con tubo gocciolante
5. **Umidificatore** (nebulizzatore, se piante richiedono >70% umidità)
6. **Riscaldatore** (se serra in esterno o non isolata)
7. **Piccolo PLC/relay** per coordinare 12V, oppure tutto WiFi smart plug

**Budget totale:**
- Sensori: ~50€
- Luci LED grow: ~30€
- Ventilazione + irrigazione: ~50€
- Smart plug/relay: ~30€
- **Totale: ~160€** (minimo, no riscaldatore/umidificatore)

**Varianti:**
- **Serra outdoor**: aggiungi sensori pioggia, copertura automatica, drenaggio
- **Idroponica**: sostituisci irrigazione gocciolante con pompa + serbatoio, sensore pH/EC
- **Propagazione**: temperatura 22-25°C costante, umidità 80%+, light 18h
- **Coltivazione frutta**: fotoperiodon variabile (8h inverno, 16h estate)

### Automazioni lavatrice & lavastoviglie

Monitoraggio cicli, notifiche fine, storico consumi.

```yaml
# automation.yaml

# Notifica quando lavatrice finisce
- alias: "Lavatrice - Fine ciclo"
  trigger:
    platform: numeric_state
    entity_id: sensor.lavatrice_power
    below: 5  # quando consumi < 5W = ciclo finito
    for: "00:01:00"
  condition:
    - condition: state
      entity_id: sensor.lavatrice_power
      state: "off"
  action:
    - service: notify.telegram
      data:
        message: "✅ Lavatrice: ciclo finito"
    - service: media_player.play_media
      target:
        entity_id: media_player.salotto_speaker
      data:
        media_content_id: "http://ha:8123/local/alert.mp3"
        media_content_type: "audio/mpeg"

# Stessa cosa per lavastoviglie
- alias: "Lavastoviglie - Fine ciclo"
  trigger:
    platform: numeric_state
    entity_id: sensor.lavastoviglie_power
    below: 5
    for: "00:01:00"
  action:
    - service: notify.telegram
      data:
        message: "✅ Lavastoviglie: ciclo finito"

# Alert: se lavatrice accesa > 3 ore (anomalia)
- alias: "Lavatrice - Alert durata anomala"
  trigger:
    platform: numeric_state
    entity_id: sensor.lavatrice_power
    above: 500  # > 500W = ciclo attivo
    for: "03:00:00"  # da 3 ore
  action:
    - service: notify.telegram
      data:
        message: "⚠️ Lavatrice accesa da 3 ore, controllare"
```

**Energy dashboard:**
- Traccia kWh/ciclo di lavatrice/lavastoviglie
- Confronta con storico (se ciclo consuma 50% meno = efficienza migliorata)
- Budget mensile: lavatrice ~3€/mese, lavastoviglie ~2€/mese (valori medi)

### Scenari (Automazioni multi-device)

Script che coordinano più device contemporaneamente per situazioni specifiche.

```yaml
# automations.yaml

# SCENARIO: CINEMA
- alias: "Scenario Cinema"
  trigger:
    platform: state
    entity_id: input_boolean.cinema_mode  # toggle da HA UI
    to: "on"
  sequence:
    - service: light.turn_off
      target:
        entity_id:
          - light.salotto
          - light.camera
    - service: cover.close_cover
      target:
        entity_id: cover.tenda_salotto
    - service: switch.turn_off
      target:
        entity_id: switch.ac_salotto_smart_plug  # spegni AC (rumore)
    - service: notify.telegram
      data:
        message: "🎬 Scenario Cinema attivato"

- alias: "Scenario Cinema - OFF"
  trigger:
    platform: state
    entity_id: input_boolean.cinema_mode
    to: "off"
  sequence:
    - service: light.turn_on
      target:
        entity_id: light.salotto
      data:
        brightness: 150
    - service: cover.open_cover
      target:
        entity_id: cover.tenda_salotto

# SCENARIO: LAVORO (concentrazione)
- alias: "Scenario Lavoro"
  trigger:
    platform: state
    entity_id: input_boolean.work_mode
    to: "on"
  sequence:
    - service: light.turn_on
      target:
        entity_id: light.studio
      data:
        brightness: 254
        color_temp: 4000  # luce fredda, concentrazione
    - service: switch.turn_on
      target:
        entity_id: switch.ac_studio_smart_plug  # clima fresco
    - service: automation.turn_off
      target:
        entity_id: automation.notification_telegram_work_hours  # silenzia notifiche
    - service: notify.telegram
      data:
        message: "💼 Scenario Lavoro attivato"

# SCENARIO: NOTTE (sicurezza + confort)
- alias: "Scenario Notte"
  trigger:
    - platform: time
      at: "23:00:00"
    - platform: state
      entity_id: input_boolean.sleep_mode
      to: "on"
  sequence:
    - service: light.turn_off
      target:
        entity_id:
          - light.salotto
          - light.camera
          - light.studio
          - light.cucina
    - service: cover.close_cover
      target:
        entity_id:
          - cover.tenda_salotto
          - cover.tenda_camera
    - service: lock.lock
      target:
        entity_id: lock.porta_principale
    - service: switch.turn_off
      target:
        entity_id:
          - switch.ac_salotto_smart_plug
          - switch.ac_camera_smart_plug
    - service: light.turn_on
      target:
        entity_id: light.scale  # piccola luce scale (navigazione notturna)
      data:
        brightness: 30
    - service: alarm_control_panel.arm_night
      target:
        entity_id: alarm_control_panel.ha  # se hai integration rilevatori
    - service: notify.telegram
      data:
        message: "🌙 Notte: casa securizzata"

# SCENARIO: BUONGIORNO (mattina)
- alias: "Scenario Buongiorno"
  trigger:
    - platform: time
      at: "07:00:00"
    - platform: state
      entity_id: input_boolean.wake_up
      to: "on"
  sequence:
    - service: light.turn_on
      target:
        entity_id:
          - light.camera
          - light.cucina
      data:
        brightness: 200
        color_temp: 5500  # luce calda-fredda, svegliarsi
    - service: cover.open_cover
      target:
        entity_id:
          - cover.tenda_salotto
          - cover.tenda_camera
    - service: climate.turn_on
      target:
        entity_id: climate.serra  # avvia luci serra (fotoperiodon)
    - service: media_player.play_media
      target:
        entity_id: media_player.salotto_speaker
      data:
        media_content_id: "http://ha:8123/local/buongiorno.mp3"  # playlist/podcast
        media_content_type: "audio/mpeg"
    - service: notify.telegram
      data:
        message: "☀️ Buongiorno! Casa pronta"

# SCENARIO: TORNO A CASA (arrivo)
- alias: "Scenario Torno a Casa"
  trigger:
    - platform: state
      entity_id: person.davide  # richiede integration presence tracking
      from: "not_home"
      to: "home"
  sequence:
    - service: lock.unlock
      target:
        entity_id: lock.porta_principale
    - service: light.turn_on
      target:
        entity_id:
          - light.ingresso
          - light.salotto
      data:
        brightness: 150
    - service: switch.turn_on
      target:
        entity_id: switch.ac_salotto_smart_plug
    - service: notify.telegram
      data:
        message: "👋 Benvenuto a casa!"

# SCENARIO: ESCI DA CASA (partenza)
- alias: "Scenario Esci"
  trigger:
    - platform: state
      entity_id: person.davide
      from: "home"
      to: "not_home"
  sequence:
    - service: light.turn_off
      target:
        entity_id:
          - light.salotto
          - light.camera
          - light.studio
          - light.cucina
    - service: switch.turn_off
      target:
        entity_id:
          - switch.ac_salotto_smart_plug
          - switch.ac_camera_smart_plug
          - switch.serra_ventilatore
    - service: lock.lock
      target:
        entity_id: lock.porta_principale
    - service: alarm_control_panel.arm_away  # attiva allarme
      target:
        entity_id: alarm_control_panel.ha
    - service: notify.telegram
      data:
        message: "🏠 Casa securizzata, arrivederci!"
```

**UI Dashboard - Scenari:**

```yaml
# ui-lovelace.yaml
cards:
  - type: button
    name: "🎬 Cinema"
    tap_action:
      action: toggle
      entity: input_boolean.cinema_mode

  - type: button
    name: "💼 Lavoro"
    tap_action:
      action: toggle
      entity: input_boolean.work_mode

  - type: button
    name: "🌙 Notte"
    tap_action:
      action: call-service
      service: automation.trigger
      service_data:
        entity_id: automation.scenario_notte

  - type: button
    name: "☀️ Buongiorno"
    tap_action:
      action: call-service
      service: automation.trigger
      service_data:
        entity_id: automation.scenario_buongiorno
```

**Note scenari:**
- Usa `input_boolean` per toggle manuali (Cinema, Lavoro)
- Usa `person.davide` per presence tracking (integrazione Google Home / Owntracks)
- Combina time trigger + manual toggle per flessibilità
- Ogni scenario disattiva gli altri conflittuali (es: Cinema spegne luci, Lavoro le riaccende)

### Tenda motorizzata (DIY)

Adapter tenda manuale con motore smart.

**Opzioni:**
1. **Motore Zigbee TuYa** (~30€) + track meccanico — Zigbee2MQTT lo vede come `cover.tenda`
2. **Motore WiFi** — solito problema cloud
3. **ESPHome custom** — microcontroller (ESP32) + motore DC relay + sensore fine corsa

Setup ESPHome (più flessibile):
```yaml
# tenda-salotto.yaml (ESPHome)

cover:
  - platform: template
    name: "Tenda Salotto"
    open_action:
      - output.turn_on: motor_forward
      - delay: 15s  # adatta al tempo di apertura totale
      - output.turn_off: motor_forward
    close_action:
      - output.turn_on: motor_backward
      - delay: 15s
      - output.turn_off: motor_backward

output:
  - platform: gpio
    pin: GPIO12
    id: motor_forward
  - platform: gpio
    pin: GPIO13
    id: motor_backward
```

Automazioni HA:
```yaml
- alias: "Tenda Salotto - Apri al mattino"
  trigger:
    platform: time
    at: "08:00:00"
  action:
    service: cover.open_cover
    target:
      entity_id: cover.tenda_salotto

- alias: "Tenda Salotto - Chiudi al tramonto"
  trigger:
    platform: sun
    event: sunset
  action:
    service: cover.close_cover
    target:
      entity_id: cover.tenda_salotto

- alias: "Tenda + AC - Scenari"
  trigger:
    platform: time
    at: "22:00:00"
  sequence:
    - service: cover.close_cover
      target:
        entity_id: cover.tenda_salotto
    - service: switch.turn_off  # spegni AC per la notte
      target:
        entity_id: switch.ac_salotto_smart_plug
```

**Componenti fisici:**
- Motoriduttore 12V DC (ebay/aliexpress)
- Relay doppio (comandare motore avanti/indietro)
- Sensori fine corsa (microswitch) — optional, senza è manuale
- Alimentatore 12V 2A
- Catena/cinghia per trasmissione movimento

**Costo totale DIY:** ~50€ vs ~200€ motore preassemblato Zigbee.

### Energy dashboard (optional)

HA ha una dashboard energetica built-in che traccia le prese smart:
1. Settings → Devices & Services → Energy
2. Associa le prese ai "device" (AC salotto, ecc.)
3. Dashboard → Energy mostra trend, costi, confronti

Utile per capire quanta corrente mangiano i condizionatori.

### Hardware necessario

- Chiavetta Zigbee (SkyConnect o ZBDongle-E)
- Prolunga USB 3m (allontana interferenza 2.4 GHz)
- Microfono USB
- Cassa USB/3.5mm
- Serratura smart (vedi sezione sotto)
- Sensori temperatura Zigbee (2-3 pezzi)
- Motore tenda (Zigbee o ESPHome)

## Roadmap servizi Proxmox

Da valutare dopo che HA è stabile — LXC su Proxmox, non add-on, se devono sopravvivere a un riavvio di HA:

- [ ] AdGuard Home / Pi-hole (DNS)
- [ ] Mosquitto (MQTT broker)
- [ ] Zigbee2MQTT o ZHA
- [ ] ESPHome
- [ ] Frigate (NVR, richiede Coral o iGPU passthrough)
- [ ] Reverse proxy + accesso remoto (Tailscale o Nginx Proxy Manager + DDNS)

## Accesso remoto

Mini PC con ethernet stabile (WiFi riservato per altro), accesso remoto verso VPS.

### Opzione A: SSH Reverse Tunnel (DIY)

```bash
# Su mini PC, systemd service /etc/systemd/system/ha-reverse-tunnel.service

[Unit]
Description=HA Reverse SSH Tunnel
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/ssh -N -R 9122:localhost:22 user@vps.example.com
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Poi:
```bash
systemctl enable ha-reverse-tunnel.service
systemctl start ha-reverse-tunnel.service
```

Accedi dal client: `ssh -p 9122 user@vps.example.com` → connette al mini PC.

**Pro:** Niente dipendenze cloud, totale controllo, semplice.  
**Contro:** Se la connessione cade, il tunnel muore (Restart=always riavvia, ma c'è un gap).

### Opzione B: Tailscale (Consigliato)

```bash
# Su mini PC (Proxmox host)
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --authkey=<key-from-tailscale-admin>
```

Poi HA VM:
```bash
# Dentro la VM HA OS (via SSH)
tailscale up --authkey=<key>
```

Accedi da qualsiasi device nella rete Tailscale:
```bash
ssh root@homeassistant  # oppure ssh admin@<tailscale-ip>
```

WebUI HA: `http://homeassistant.local:8123` oppure `http://<tailscale-ip>:8123`

**Pro:** NAT traversal automático, mesh network, niente port forwarding, reconnect automatico, funziona anche mobile, webui HA raggiungibile facilmente.  
**Contro:** Account Tailscale (free per homelab), leggera dipendenza dal servizio Tailscale per coordinate/auth.

### Hybrid (Best Practice)

1. Tailscale: accesso webui + SSH comodo, dappertutto
2. SSH key-only (no password) su mini PC
3. Firewall mini PC: ssh solo da Tailscale interface (`ufw allow in on tailscale0 from any to any port 22`)

Così Tailscale è il gate, SSH non è esposto a internet.

### HA Cloud Access (alternativa)

HA ufficiale offre "Nabu Casa" (a pagamento) — accesso webui remoto + notifiche push. Salta il reverse tunnel ma è cloud-dependent.

## Wake-on-LAN & Power Management

### Wake-on-LAN (WoL)

Accendi il mini PC da remoto via pacchetto magic packet.

**Setup BIOS:**
1. Entra Setup → Advanced / Power Management
2. Abilita **Wake on LAN** (label varia: `Resume on LAN`, `PXE Resume`, `Network Wake-up`)
3. Salva e riavvia

**Setup Proxmox:**
```bash
# Controlla NIC
ip link show

# Abilita WoL (es. eth0)
ethtool -s eth0 wol g

# Verifica
ethtool eth0 | grep -i wake

# Persisti su reboot: /etc/network/interfaces oppure netplan
# Se netplan (/etc/netplan/01-netcfg.yaml):
network:
  ethernets:
    eth0:
      dhcp4: true
      wakeonlan: true
  version: 2
```

Poi da remoto:
```bash
wakeonlan <MAC-address-mini-pc>
```

Su HA puoi aggiungere un `shell_command` e un button per accenderlo:

```yaml
# configuration.yaml
shell_command:
  wol_mini_pc: wakeonlan <MAC>

script:
  power_on_home_server:
    sequence:
      - service: shell_command.wol_mini_pc
```

### Wake-on-Power (Automatic Boot After Power Loss)

Mini PC si riaccende automaticamente dopo blackout.

**Setup BIOS:**
1. Power Management → AC Recovery / **Restore on AC Loss** / **Power After Power Loss**
2. Imposta su **Always On** oppure **Last State** (riaccende solo se era acceso prima della caduta)
3. Salva

**Proxmox VM startup:**
```bash
# HA OS VM si avvia automaticamente al boot Proxmox
qm set <vmid> -autostart 1
```

Verifica:
```bash
qm config <vmid> | grep autostart
```

### Shutdown remoto (Hibernate)

Spegni il mini PC da remoto (utile se consumi importano):

```bash
# Via HA:
shell_command:
  shutdown_mini_pc: ssh root@<ip-mini-pc> 'systemctl poweroff'

script:
  power_off_home_server:
    sequence:
      - service: shell_command.shutdown_mini_pc
```

O da Tailscale:
```bash
ssh root@homeassistant 'shutdown -h now'
```

### Consumo energetico

Mini PC in idle:
- C-states **disabilitati** (performance mode): 15-25W
- C-states **abilitati**: 3-8W
- Standby (S5): <1W

Se il mini PC resterà sempre acceso, abilita C-states nel BIOS (Power Management → CPU C-states → Auto/Enabled). Risparmi ~15W continui.

## Note

- **Aggiornamenti**: HA Core mensile (rilascio il primo mercoledì), HA OS meno frequente. Snapshot Proxmox prima di un major update.
- **Watchdog**: abilita `QEMU Guest Agent` nella VM e l'avvio automatico, così HA torna su dopo un blackout.
- **Rumore/consumi**: verifica i profili C-state nel BIOS, i mini PC restano spesso bloccati in performance mode.
- **Ethernet**: setup stabile per reverse tunnel. WiFi per device IoT separato (guest network se possibile, VLAN IoT ottimale).
- **WoL**: verifica che la NIC supporti WoL (quasi tutte le ethernet moderne sì). USB wake non funziona via WoL magic packet.

## Riferimenti

- [Installazione HA](https://www.home-assistant.io/installation/)
- [HA OS releases](https://github.com/home-assistant/operating-system/releases)
- [Proxmox VE docs](https://pve.proxmox.com/pve-docs/)
- [Community Scripts ProxmoxVE](https://community-scripts.github.io/ProxmoxVE/)
