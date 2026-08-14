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
| **Silvio** (robot aspirapolvere) | `roborock` — cloud | Salotto |
| Silvio Dock | `roborock` | Salotto |
| Tv del soggiorno | DLNA (`dlna_dmr`) | Salotto |
| Google Home Mini | Google Cast | Cucina |
| Razr (telefono) | `mobile_app` | — |
| ASKEY RTV1907VW (modem) | UPnP | — |
| Fastweb_DLNA_Server | `dlna_dms` | — |

La TV è collegata solo via DLNA, che permette di inviarle contenuti ma non di accenderla o cambiare sorgente. Se è Samsung o LG esiste un'integrazione dedicata più completa.

### Silvio — robot aspirapolvere

Roborock `roborock.vacuum.a101`, collegato tramite l'integrazione ufficiale (passa dal cloud Roborock). Espone **44 entità**, fra cui:

| Entità | Cosa fa |
|---|---|
| `vacuum.silvio` | Controllo principale — avvio, stop, rientro alla base |
| `sensor.silvio_batteria` | Livello batteria |
| `sensor.silvio_current_room` | Stanza in cui si trova |
| `sensor.silvio_area_di_pulizia_totale` | m² puliti da sempre |
| `image.silvio_map_0` | Mappa della casa |
| `select.silvio_cleaning_mode` | Aspirazione, lavaggio, o entrambi |
| `binary_sensor.silvio_dock_*` | Stato serbatoi, panno, fluido di pulizia |
| `sensor.silvio_dock_strainer_time_left` | Vita residua del filtro |

Le entità del dock riportano anche la manutenzione: `strainer_time_left` in negativo significa filtro da sostituire.

Le stanze note al robot (`Soggiorno`, ecc.) sono definite nella sua mappa e **non coincidono** con le aree di Home Assistant — sono due registri separati.

### Smart plug — non ancora collegate

Le due plug LSC funzionano regolarmente con l'app LSC Smart Connect, ma **non sono in Home Assistant**. Servirebbero le `local_key`, che genera il cloud Tuya.

| Plug | IP | `device_id` | Protocollo |
|---|---|---|---|
| A | `192.168.1.15` | `bfaf68f4a8c2054efbpvy8` | 3.4 |
| B | non in rete al momento | — | — |

Le chiavi estratte da Cloudcutter **non sono utilizzabili**: sono temporanee, generate dall'exploit, e il loro `device_id` non corrisponde a quello reale.

**Tre strade, tutte con un ostacolo:**

1. **Tuya IoT Platform** (`iot.tuya.com`) — dà le `local_key` per LocalTuya. Tentato senza successo: il QR code per collegare l'account scade immediatamente (`QR code has expired`). Da riprovare tenendo l'app già aperta sulla schermata di scansione, e verificando che il data center sia `Central Europe`
2. **Integrazione Tuya ufficiale in HA** — non richiede la piattaforma sviluppatori, bastano le credenziali dell'app. Passa dal cloud
3. **Firmware locale** (OpenBeken) — la soluzione definitiva, ma richiede il flash seriale. Vedi [DECISIONS.md](DECISIONS.md)

Le app LSC Smart Connect sono costruite sulla piattaforma Tuya (white label), quindi al passaggio di collegamento va usata **quella app**, non SmartLife.

**Lo storico dei consumi dei due mesi passati non è recuperabile dalle plug**: conservano solo il totale cumulativo, la serie temporale sta sui server Tuya. Potrebbe essere estraibile via API una volta risolto l'accesso alla piattaforma.

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

Definite in `automations.yaml`. Il sorgente delle automazioni del robot è versionato in [`automations/silvio.yaml`](automations/silvio.yaml).

| Automazione | Quando scatta |
|---|---|
| Notifica all'avvio di HA | HA si avvia — utile per accorgersi di riavvii non voluti |
| Batteria telefono scarica | Sotto il 15% mentre non è in carica |
| Notifica arrivo a casa | `person.davide` passa a `home` |
| Notifica uscita da casa | `person.davide` passa a `not_home` da 5 minuti |
| Silvio - inizio pulizia | Il robot passa a `cleaning`, da qualunque comando |
| Silvio - pulizia completata | Rientro alla base da `returning`, con m² e minuti |
| Silvio - errore | `sensor.silvio_errore_aspirapolvere` diverso da `none` |
| Silvio - acqua esaurita | Serbatoio dell'acqua pulita vuoto |
| Silvio - acqua sporca piena | Serbatoio di recupero da svuotare |
| Silvio - manutenzione | Sabato mattina, se un consumabile ha superato la vita utile |

Le automazioni del robot sono **solo informative**: nessun avvio automatico, per non interferire con la programmazione impostata nell'app Roborock.

Note sulle scelte:

- *Pulizia completata* scatta sulla transizione `returning → docked`, non su `docked` da qualunque stato: altrimenti notificherebbe a ogni ricarica
- *Manutenzione* è un promemoria settimanale invece di una notifica per ogni consumabile, per non moltiplicare gli avvisi. I sensori riportano le **ore residue**: un valore negativo significa vita utile già superata
- Le notifiche usano `tag`, così quelle della stessa categoria si sostituiscono invece di accumularsi

Per ricaricarle dopo una modifica, senza riavviare tutto HA:

```bash
curl -X POST -H "Authorization: Bearer $TOKEN" \
  http://192.168.1.37/api/services/automation/reload
```

## Liste

| Entità | Uso |
|---|---|
| `todo.shopping_list` | Lista della spesa estemporanea |
| `todo.home` | Cose da fare in casa — 36 task |
| `todo.dispensa` | Inventario dispensa — 111 prodotti |
| `todo.dispensa_stagionale` | Prodotti stagionali o occasionali — 14 |

### Dispensa: la logica è invertita

Le liste `dispensa` non sono liste della spesa: sono un **inventario permanente**. Le voci non si aggiungono né si eliminano — sono sempre tutte lì, e cambia solo il loro stato:

- **Spuntato** = ce l'ho
- **Non spuntato** = da comprare

Prima della spesa si passa la lista segnando cosa c'è; quel che resta non spuntato è la lista della spesa.

I prodotti sono ordinati **per categoria** come nel file sorgente, e alfabeticamente all'interno di ciascuna. La categoria è nella descrizione di ogni voce.

Sorgente: `~/0Projects/lista-spesa/lista-spesa.md`. Per ripopolarle da capo esiste lo script che le ha generate — le liste vanno però svuotate prima, perché `todo.add_item` non deduplica.

**Nota:** le etichette degli stati (*Attivo* / *Completato*) non sono personalizzabili. Sono valori fissi del core di Home Assistant (`needs_action` / `completed`), tradotti dal frontend: non esiste un'opzione per rinominarli, né globalmente né per singola lista.

## Dashboard

L'overview predefinita è stata sostituita con una configurazione esplicita, versionata in [`dashboard/overview.yaml`](dashboard/overview.yaml). Tre viste:

| Vista | Contenuto |
|---|---|
| **Casa** | Meteo, presenza, batteria telefono; robot con comandi e manutenzione; media; lista della spesa |
| **Mappa** | Planimetria con icone di stato sovrapposte (`picture-elements`) |
| **Sistema** | Aggiornamenti, stato WAN, automazioni, alba/tramonto |

La planimetria è in `/config/www/planimetria.png`, servita come `/local/planimetria.png`. **HA registra la cartella `www` solo al riavvio**: dopo averci messo un file serve `ha core restart`, altrimenti risponde `404`.

Le dashboard in Home Assistant sono **globali, non per-utente**: non esistono configurazioni separate per account.

Per reinstallarla dopo una modifica al file si usa il servizio WebSocket `lovelace/config/save` con `url_path: null` (la dashboard predefinita).

Per ricaricarle dopo una modifica, senza riavviare tutto HA:

```bash
curl -X POST -H "Authorization: Bearer $TOKEN" \
  http://192.168.1.37/api/services/automation/reload
```

## Backup — nessuno, per scelta

**Non è attivo alcun backup**, né in Home Assistant né su Proxmox. Decisione presa il 12 agosto 2026.

Era stato configurato un job notturno che estraeva i backup dalla VM verso l'host, ma è stato rimosso: entrambe le copie finivano sullo stesso disco NVMe, quindi proteggevano da una VM corrotta ma non da un guasto hardware. Poco valore per lo spazio occupato.

`elisabetta` non è utilizzabile come destinazione: è al **92% di occupazione**, con circa 10 GB liberi. Riempirla farebbe cadere i servizi che ci girano.

**Conseguenza da tenere presente:** un errore di configurazione, un aggiornamento andato male o un guasto al disco comportano rifare tutto da capo — onboarding, aree, dispositivi, automazioni.

Quando servirà, le opzioni sono un disco USB collegato al mini PC, spazio su un altro server, o un servizio cloud via `rclone`.

Per un backup manuale occasionale:

```bash
ssh proxmox 'qm guest exec 100 --timeout 600 -- /usr/bin/ha backups new --name "prima-di-<cosa>"'
```

Utile prima di modifiche rischiose. Resta comunque dentro la VM.

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
