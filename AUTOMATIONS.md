# Dispositivi e automazioni

Alcuni dispositivi sono collegati (vedi [CONFIGURATION.md](CONFIGURATION.md)), ma **nessuna delle automazioni descritte qui è ancora implementata**. Questo file raccoglie il piano e gli esempi di configurazione da usare man mano che l'hardware arriva.

## Dispositivi da integrare

| Dispositivo | Integrazione prevista | Stato |
|---|---|---|
| Robot aspirapolvere | `roborock` | ✅ collegato |
| Smart TV | DLNA | ✅ collegato (solo invio contenuti) |
| Google Home Mini | Google Cast | ✅ collegato |
| Smart plug (condizionatori) | Tuya / LocalTuya | ⏳ bloccato sulle chiavi |
| Smart plug (lavatrice, lavastoviglie) | Tuya / LocalTuya | ⏳ bloccato sulle chiavi |
| Videocamera animali | RTSP/HTTP | — |
| Luci smart | Zigbee2MQTT | Preferito a WiFi, vedi [DECISIONS.md](DECISIONS.md) |
| Alexa | Emulated Hue | HA espone i device ad Alexa, non il contrario |
| Google Assistant | Google Home | Richiede OAuth, passa dal cloud |
| Assistente vocale | ESPHome + mic/speaker | LLM su server esterno, non sul mini PC |

## Hardware da procurare

- **Chiavetta Zigbee** — SkyConnect (ufficiale) o Sonoff ZBDongle-E (~15 €, equivalente)
- **Prolunga USB 3 m** — indispensabile: il mini PC interferisce a 2.4 GHz
- **Sensori temperatura Zigbee** — 2-3, per le stanze con condizionatore
- **Microfono e cassa USB** — per l'assistente vocale

## Progetti pianificati

### Robot aspirapolvere — automazioni possibili subito

Silvio è già collegato e non richiede altro hardware. Alcune idee realizzabili con le entità disponibili:

```yaml
# Pulisce quando esci di casa, ma solo nei giorni feriali
- alias: "Silvio - pulizia quando esco"
  triggers:
    - trigger: state
      entity_id: person.davide
      from: home
      to: not_home
      for: "00:10:00"
  conditions:
    - condition: time
      weekday: [mon, tue, wed, thu, fri]
      after: "09:00:00"
      before: "17:00:00"
    - condition: state
      entity_id: vacuum.silvio
      state: docked
  actions:
    - action: vacuum.start
      target:
        entity_id: vacuum.silvio

# Avvisa quando ha finito
- alias: "Silvio - pulizia completata"
  triggers:
    - trigger: state
      entity_id: vacuum.silvio
      to: docked
      from: returning
  actions:
    - action: notify.mobile_app_razr
      data:
        title: Pulizia completata
        message: >-
          Puliti {{ states('sensor.silvio_area_di_pulizia') }} m².

# Manutenzione: avvisa quando un consumabile è esaurito
- alias: "Silvio - manutenzione necessaria"
  triggers:
    - trigger: numeric_state
      entity_id:
        - sensor.silvio_dock_strainer_time_left
        - sensor.silvio_dock_maintenance_brush_time_left
      below: 0
  actions:
    - action: notify.mobile_app_razr
      data:
        title: Silvio - manutenzione
        message: "{{ trigger.to_state.name }} da sostituire."
```

Nota: le stanze note al robot vengono dalla sua mappa e non coincidono con le aree di HA. Per pulire una stanza specifica serve `vacuum.send_command` con `app_segment_clean` e l'ID del segmento.

### Controllo condizionatori portatili

I condizionatori sono portatili e si accendono/spengono da smart plug. Con sensori di temperatura in stanza si automatizza il ciclo.

```yaml
- alias: "AC salotto ON"
  trigger:
    platform: numeric_state
    entity_id: sensor.salotto_temperature
    above: 28
  action:
    service: switch.turn_on
    target:
      entity_id: switch.ac_salotto

- alias: "AC salotto OFF"
  trigger:
    platform: numeric_state
    entity_id: sensor.salotto_temperature
    below: 24
  action:
    service: switch.turn_off
    target:
      entity_id: switch.ac_salotto
```

L'isteresi (28 °C per accendere, 24 °C per spegnere) evita che il condizionatore si accenda e spenga di continuo attorno alla soglia. Da aggiungere: fascia oraria, e un `input_boolean` per l'override manuale.

### Lavatrice e lavastoviglie

Il calo di potenza sotto i 5 W indica la fine del ciclo:

```yaml
- alias: "Lavatrice - fine ciclo"
  trigger:
    platform: numeric_state
    entity_id: sensor.lavatrice_power
    below: 5
    for: "00:01:00"
  action:
    service: notify.telegram
    data:
      message: "✅ Lavatrice: ciclo finito"
```

Utile anche un allarme se il consumo resta alto per più di tre ore, che segnala un blocco.

### Serratura smart

Da abbinare al cambio serratura già previsto. **Aqara U100** (~120 €) è il miglior compromesso: Zigbee locale, batteria ~12 mesi, compatibile con cilindri europei, PIN temporanei per ospiti.

Alternative: Yale Assure SL2 (~200 €, premium), Nuki Smart Lock Pro (~250 €, ma WiFi e cloud).

Automazioni utili: notifica a ogni apertura, chiusura automatica se resta aperta, sblocco all'arrivo.

### Tenda motorizzata

La tenda esistente va adattata. Due strade:

- **Motore Zigbee TuYa** (~30 €) — plug-and-play, appare come `cover.*`
- **ESPHome su ESP32** (~50 €) — motoriduttore 12 V, relay doppio, opzionali i finecorsa. Più lavoro, più controllo

Automazioni: apertura al mattino, chiusura al tramonto, integrazione negli scenari.

### Citofono video

**Dahua VTO2211G** (~150 €) è la scelta consigliata: IP puro, RTSP locale, SIP nativo, nessuna dipendenza dal cloud. Alimentazione PoE, quindi un solo cavo.

Permette notifica con snapshot alla chiamata, apertura porta da remoto e — con Asterisk — intercomunicazione vocale.

### Mini serra

Sensori (temperatura, umidità, umidità del suolo) e attuatori (LED grow, ventilatore, valvola di irrigazione) per un ciclo automatico completo:

- Fotoperiodo: luci accese 14 h al giorno
- Ventilazione se l'umidità supera il 70%
- Irrigazione se l'umidità del suolo scende sotto il 40%
- Riscaldamento sotto i 18 °C

Budget indicativo: ~160 € senza riscaldatore né umidificatore.

### Scenari

Automazioni che coordinano più dispositivi. I casi utili:

| Scenario | Effetto |
|---|---|
| **Cinema** | Luci spente, tende chiuse, AC in standby |
| **Lavoro** | Luce fredda nello studio, AC acceso, notifiche silenziate |
| **Notte** | Tutto spento, porta chiusa, luce scale al minimo |
| **Buongiorno** | Tende aperte, luci calde, musica |
| **Arrivo** | Porta sbloccata, luci ingresso, AC acceso |
| **Uscita** | Tutto spento, porta chiusa, allarme attivo |

Si attivano da `input_boolean` (per quelli manuali), da orario, o da presenza rilevata.

```yaml
- alias: "Scenario Notte"
  trigger:
    - platform: time
      at: "23:00:00"
  action:
    - service: light.turn_off
      target:
        entity_id: [light.salotto, light.cucina, light.studio]
    - service: cover.close_cover
      target:
        entity_id: cover.tenda_salotto
    - service: lock.lock
      target:
        entity_id: lock.porta_principale
```

### Assistente vocale con AI

L'obiettivo è un dispositivo tipo Google Home o Alexa, ma con un LLM al posto dell'assistente commerciale, e soprattutto **capace di interagire con le liste**: chiedere cosa manca in dispensa, segnare un prodotto come finito, aggiungere un task — a voce.

È il motivo per cui le liste vivono in Home Assistant e non più in un file: le entità `todo` espongono già `get_items`, `add_item` e `update_item`, che un LLM può usare come strumenti.

**I pezzi della catena** (HA li supporta tutti nativamente via *Assist*):

| Fase | Dove gira | Opzioni |
|---|---|---|
| Wake word | mini PC | openWakeWord, microWakeWord |
| Riconoscimento vocale | mini PC | Whisper (add-on) |
| **Ragionamento (LLM)** | **altrove** | vedi sotto |
| Sintesi vocale | mini PC | Piper (add-on) |

**Il LLM non gira sul mini PC.** L'i5-6400T senza GPU reggerebbe solo modelli da 3B con latenza di secondi. Due strade, entrambe accettabili:

- **Altro server locale con GPU** — mantiene tutto in casa, nessuna dipendenza esterna
- **API esterna** (OpenAI, Anthropic, altri) — modelli molto più capaci, dipendenza dalla rete **accettata consapevolmente**

Il resto della catena resta comunque locale sul mini PC: wake word, riconoscimento e sintesi vocale non richiedono potenza di calcolo rilevante. Quindi anche con LLM remoto solo il ragionamento passa dalla rete, non l'audio grezzo in continuazione.

**Hardware del dispositivo**, due strade:

- **ESP32-S3 dedicato** — ESPHome Voice PE (~60 €) o assemblato: sta in una stanza, sempre in ascolto
- **Microfono e cassa USB sul mini PC** — costa meno ma il dispositivo è dove sta il server

## Idee non ancora valutate

- Sensori di perdita d'acqua sotto lavatrice e caldaia — costano poco e prevengono danni seri
- Rilevatori di fumo Zigbee
- Contatore elettrico smart, per la dashboard energetica
- Videocamere in salotto e alla porta, con Frigate per il riconoscimento persone (richiede passthrough iGPU, già possibile su questo hardware)
- Sensori di apertura su porte e finestre
