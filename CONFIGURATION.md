# Configurazione Home Assistant

Stato al 12 agosto 2026.

## Impostazioni generali

Definite in `configuration.yaml`:

```yaml
homeassistant:
  external_url: https://ha.lancini.net
  internal_url: http://192.168.1.37
```

Senza questi URL, i link nelle notifiche puntano a indirizzi sbagliati quando sei fuori casa.

Impostate durante l'onboarding: posizione (45.63, 8.83), timezone `Europe/Rome`, valuta EUR, lingua italiana, unità metriche.

## Aree

| Area | ID interno |
|---|---|
| Salotto | `living_room` |
| Cucina | `kitchen` |
| Camera | `bedroom` |
| Cameretta | `cameretta` |
| Corridoio | `corridoio` |
| Bagno | `bagno` |
| Sgabuzzino | `sgabuzzino` |

I tre ID in inglese sono le aree create dall'onboarding, rinominate. I balconi non hanno un'area propria: contano come la stanza da cui si accede.

## Dispositivi collegati

| Dispositivo | Integrazione | Area |
|---|---|---|
| Tv del soggiorno | DLNA (`dlna_dmr`) | Salotto |
| Google Home Mini | Google Cast | Cucina |
| Razr (telefono) | `mobile_app` | — |
| ASKEY RTV1907VW (modem) | UPnP | — |

Non confermato, in attesa nella lista dei dispositivi scoperti: `Fastweb_DLNA_Server`.

La TV è collegata solo via DLNA, che permette di inviarle contenuti ma non di accenderla o cambiare sorgente. Se è Samsung o LG esiste un'integrazione dedicata più completa.

## Presenza

`person.davide` è collegato a `device_tracker.razr`, alimentato dall'app Home Assistant sul telefono. Funziona senza hardware aggiuntivo.

Dal telefono arrivano anche `sensor.razr_battery_level`, `sensor.razr_battery_state`, `sensor.razr_charger_type`.

## Notifiche

Il servizio è **`notify.mobile_app_razr`** — non `notify.razr`, che non esiste e restituisce `400`.

```yaml
- action: notify.mobile_app_razr
  data:
    title: Titolo
    message: Testo
```

Non serve Telegram: le notifiche push dell'app funzionano già.

## Automazioni attive

Definite in `automations.yaml`:

| Automazione | Quando scatta |
|---|---|
| Notifica all'avvio di HA | HA si avvia — utile per accorgersi di riavvii non voluti |
| Batteria telefono scarica | Sotto il 15% mentre non è in carica |
| Notifica arrivo a casa | `person.davide` passa a `home` |
| Notifica uscita da casa | `person.davide` passa a `not_home` da 5 minuti |

Le ultime due sono segnaposto: per ora mandano solo una notifica, diventeranno scenari veri quando ci saranno luci, serratura e prese da comandare.

Per ricaricarle dopo una modifica, senza riavviare tutto HA:

```bash
curl -X POST -H "Authorization: Bearer $TOKEN" \
  http://192.168.1.37/api/services/automation/reload
```

## Backup

Due livelli.

**Nella VM** — Home Assistant tiene i suoi backup in `/mnt/data/supervisor/backup`, sullo stesso disco virtuale della VM. Se quello si corrompe, spariscono anche i backup.

**Sull'host** — `/usr/local/bin/ha-backup-pull.sh` (sorgente in [scripts/](scripts/)) crea un backup nella VM, lo estrae e lo salva in `/var/lib/vz/dump/ha-backups` sull'host Proxmox. Tiene 14 copie sull'host e 3 nella VM.

Lanciato da `ha-backup-pull.timer` ogni notte alle 3:30, con `Persistent=true` così recupera l'esecuzione se il mini PC era spento.

```bash
ssh proxmox 'systemctl list-timers ha-backup-pull.timer'   # prossima esecuzione
ssh proxmox '/usr/local/bin/ha-backup-pull.sh'             # esecuzione manuale
ssh proxmox 'ls -lh /var/lib/vz/dump/ha-backups/'          # cosa c'è
```

**Nota sull'estrazione:** avviene via `qm guest exec` con codifica base64, perché il canale del guest agent non gestisce dati binari. Funziona, ma è lento su file grandi: quando i backup cresceranno, converrà passare a un `rsync` verso l'host.

### Un backup davvero esterno manca ancora

Entrambe le copie vivono sullo stesso disco NVMe. Un guasto hardware le porterebbe via tutte.

`elisabetta` non è adatta come destinazione: è al **92% di occupazione**, con soli 10 GB liberi. Riempirla farebbe cadere i servizi che ci girano.

Opzioni da valutare: un disco USB collegato al mini PC, uno spazio su un altro server, o un servizio cloud con `rclone`.

## API

Per operare da fuori serve un token di accesso a lungo termine: profilo utente → Sicurezza → Token di accesso a lungo termine.

Le aree e il registro dispositivi si gestiscono via **WebSocket**, non REST:

```python
# tipi di messaggio utili
{"type": "config/area_registry/list"}
{"type": "config/area_registry/create", "name": "..."}
{"type": "config/area_registry/update", "area_id": "...", "name": "..."}
{"type": "config/device_registry/list"}
{"type": "config/device_registry/update", "device_id": "...", "area_id": "..."}
```

Stati e servizi invece stanno su REST:

```bash
curl -H "Authorization: Bearer $TOKEN" http://192.168.1.37/api/states
curl -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"message":"test"}' http://192.168.1.37/api/services/notify/mobile_app_razr
```
