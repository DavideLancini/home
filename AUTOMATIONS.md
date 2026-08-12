# Dispositivi e automazioni

**Nulla di quanto segue è ancora implementato.** Home Assistant è installato e raggiungibile, ma non ha ancora dispositivi collegati. Questo file raccoglie il piano e gli esempi di configurazione da usare quando l'hardware arriverà.

## Dispositivi da integrare

| Dispositivo | Integrazione prevista | Note |
|---|---|---|
| Smart plug (condizionatori) | Tuya / SmartLife | Con monitoraggio consumi |
| Smart plug (lavatrice, lavastoviglie) | Tuya / SmartLife | Notifica fine ciclo dal calo di potenza |
| Videocamera animali | RTSP/HTTP | |
| Smart TV | HDMI-CEC / Tuya | |
| Luci smart | Zigbee2MQTT | Preferito a WiFi, vedi [DECISIONS.md](DECISIONS.md) |
| Alexa | Emulated Hue | HA espone i device ad Alexa, non il contrario |
| Google Assistant | Google Home | Richiede OAuth, passa dal cloud |
| Assistente vocale | ESPHome + mic/speaker | Oppure Ollama locale sul mini PC |

## Hardware da procurare

- **Chiavetta Zigbee** — SkyConnect (ufficiale) o Sonoff ZBDongle-E (~15 €, equivalente)
- **Prolunga USB 3 m** — indispensabile: il mini PC interferisce a 2.4 GHz
- **Sensori temperatura Zigbee** — 2-3, per le stanze con condizionatore
- **Microfono e cassa USB** — per l'assistente vocale

## Progetti pianificati

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

## Idee non ancora valutate

- Sensori di perdita d'acqua sotto lavatrice e caldaia — costano poco e prevengono danni seri
- Rilevatori di fumo Zigbee
- Contatore elettrico smart, per la dashboard energetica
- Videocamere in salotto e alla porta, con Frigate per il riconoscimento persone (richiede passthrough iGPU, già possibile su questo hardware)
- Sensori di apertura su porte e finestre
