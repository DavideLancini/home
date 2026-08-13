# Decisioni

## Proxmox + HA OS in VM, non HA OS bare-metal

**Perché:** Home Assistant OS è un sistema chiuso — Buildroot, filesystem immutabile, niente `apt`. Ci si installano solo add-on gestiti dal Supervisor. Installandolo bare-metal, il mini PC farebbe solo quello.

Con Proxmox si mantiene HA OS completo (add-on, aggiornamenti one-click, backup nativi) e restano risorse per altri servizi in VM o LXC. L'overhead su hardware moderno è trascurabile.

**Alternative valutate:**

| Opzione | Perché scartata |
|---|---|
| HA OS bare-metal | Il mini PC farebbe solo Home Assistant |
| HA Container (Docker) | Niente add-on né Supervisor |
| XCP-ng | Xen Orchestra va compilato dai sorgenti, o è a pagamento |
| Incus | Ottimo e leggero, ma solo CLI/UI minimale |
| TrueNAS SCALE | Risolve lo storage, non la virtualizzazione |
| Unraid | Non è FOSS |

Proxmox VE è AGPLv3, su base Debian con KVM/QEMU e LXC. La subscription copre solo i repo enterprise e il supporto: senza, nessun limite funzionale.

## Reverse tunnel SSH, non Tailscale

**Perché:** c'era già un VPS con IP fisso (`elisabetta`) e altri sottodomini `lancini.net` pubblicati con nginx e certbot. Il tunnel si innesta su un'infrastruttura collaudata, senza dipendere da servizi terzi.

**Alternative valutate:**

| Opzione | Perché scartata |
|---|---|
| Tailscale | Comodo (NAT traversal, zero config) ma dipende da un servizio esterno per auth e discovery |
| Nabu Casa | A pagamento, cloud-dependent |
| Port forwarding sul router | La rete di casa non ha IP fisso |

Lo svantaggio è che l'istanza è **esposta pubblicamente**: l'unica difesa è l'autenticazione di HA. Con Tailscale l'accesso sarebbe stato limitato ai dispositivi della rete privata. Da rivalutare se la sicurezza diventa una priorità — vedi le note in [REMOTE-ACCESS.md](REMOTE-ACCESS.md).

## IP statico dentro HA, non reservation DHCP

L'IP `192.168.1.37` è configurato dentro Home Assistant con `ha network update`, non come reservation sul router.

**Motivo pratico:** funziona subito, senza accedere al pannello del modem. Ma una reservation resta consigliata come rete di sicurezza: se la VM venisse ricreata senza riconfigurare l'IP, prenderebbe un indirizzo DHCP qualsiasi.

Proxmox invece ha una reservation vera sul router per `40:b0:34:fe:a2:62` → `.2`.

## VM creata con lo script ufficiale

Le prime VM sono state create a mano con `qm create`, replicando quello che fa lo script della community. Ha funzionato, ma è stato un errore di metodo: lo script è testato, imposta parametri che è facile omettere, ed è ciò che il progetto supporta.

Che sia stato *quello* a risolvere l'incidente dell'11 agosto non è dimostrato — la causa vera era un'altra — ma resta la scelta corretta per manutenibilità.

Procedura in [RUNBOOK.md](RUNBOOK.md).

## Smart plug Tuya: firmware locale

Le smart plug sono **LSC Smart Connect** di Action. L'obiettivo è farle funzionare senza passare dai server Tuya.

Il chip è **Beken BK7231N**, non ESP8266. Questo esclude ESPHome e Tasmota: per usare Tasmota il modulo andrebbe fisicamente sostituito, mentre **OpenBeken** gira sul BK7231N com'è.

### Le due plug

| | Plug A | Plug B |
|---|---|---|
| Firmware | `v1.1.17` (da `v1.0.4`) | `v1.0.0(1.0.2)`, MCU `v1.0.2` |
| Modello | da identificare | **3202087** |
| Cloudcutter OTA | improbabile — Tuya ha patchato a febbraio 2022 | **plausibile** — `v1.0.0` è verosimilmente anteriore |

### Plug B (3202087) — hardware documentato

| | |
|---|---|
| Modulo | CB2S (BK7231N) |
| Misuratore energia | BL0937 |
| PCB | WP02GE-F |
| Case | a clip, non a viti |

**Mappatura GPIO:**

| Pin | Funzione |
|---|---|
| P6 | LED canale 1 |
| P7 | Pulsante |
| P8 | **Relè** |
| P10 | LED WiFi |
| P11 | BL0937 SEL |
| P24 | BL0937 VI |
| P26 | BL0937 ELE |

Config equivalente: `{"NAME":"LSC Smart Power Plug with Energy Monitoring","GPIO":[0,2624,1,288,32,544,1,1,2656,224,2720,1,1,1],"FLAG":0,"BASE":18}`

La dicitura "Modulo MCU" nel firmware **non indica un TuyaMCU**: il BL0937 è un chip di misura, non un microcontrollore che pilota il relè. Si usa OpenBeken standard, non la modalità TuyaMCU.

### Metodi

| Metodo | Cosa comporta | Rischio |
|---|---|---|
| **Tuya-Cloudcutter** (OTA) | Nessun cacciavite. Serve un profilo con gli offset della build esatta | Nullo — se fallisce non danneggia |
| **Flash seriale** | Aprire la plug, FTDI 3.3 V su RX/TX/GND, **CEN a massa** per la modalità programmazione | Medio — 230 V, da fare scollegata |
| **LocalTuya** | Nessun flash: si estraggono le chiavi e HA parla in locale | Nullo |

Nota per il flash seriale: il BK7231 assorbe oltre 50 mA di picco e molti adattatori USB-TTL economici non reggono — serve alimentazione 3.3 V esterna. Fare comunque prima un backup del firmware originale, che rivela la mappa GPIO della specifica revisione.

### Tentativo Cloudcutter del 12 agosto 2026 — fallito

**Esito: entrambe le plug sono vulnerabili, ma nessun profilo nel database corrisponde alle loro build.**

L'exploit riesce sempre (`Exploit run, saved device config too!`), è il flash successivo a fallire: gli offset `address_finish` e `address_ssid` sono specifici della singola build del firmware.

Profili provati, tutti falliti:

| Profilo | Su quale plug |
|---|---|
| `oem-bk7231n-safe-dltj-plug-1.0.2` | B — scelto per somiglianza, in realtà è un misuratore EARU con TA |
| `lsc-2578685-970766-smart-plug-cb2s-v1.1.8` | A |
| `lsc-2578685-970766-smart-plug-cb2s-v1.1.7` | A |

Le ultime due sono **le uniche prese LSC BK7231N in tutto il database** (777 dispositivi, 372 profili). L'unica altra entry LSC per prese è la `3202087` v1.3.5, che però è BK7231T — chip incompatibile.

**Identificazione dei dispositivi in rete.** Uno scan `tinytuya` ha trovato due dispositivi Tuya:

| IP | MAC | `productKey` | Identificazione |
|---|---|---|---|
| `192.168.1.15` | `fc:3c:d7:b3:7c:c3` | `keyjup78v54myhan` | **Plug A** — corrisponde ai 5 profili `oem_bk7231n_plug` 1.1.4–1.1.8 |
| `192.168.1.10` | `d8:fc:92:42:0e:08` | `keykmm3rjyqy5r8p` | Sconosciuto — nessun profilo nel database. Probabilmente una lampadina |

La `productKey` della plug A coincide esattamente con quella della famiglia `oem_bk7231n_plug`, quindi la famiglia firmware è certa: manca solo il profilo per la build `1.1.17`.

**Chiavi estratte** (temporanee, generate da Cloudcutter — **non** utilizzabili per LocalTuya, che richiede le `local_key` reali dall'account Tuya):

```
Plug A: uuid=ryhF64ItQqYT  local_key=HzJwr9btGj5M3hCM
Plug B: uuid=t6ccXvSNh5Te  local_key=2rfiUwDwvTmv0cGo
```

**Le plug non sono state modificate.** La fase `Exploit run, saved device config too!` estrae solo la configurazione: lo scollegamento dal cloud avviene nell'opzione 1 dello script ("Detach from the cloud"), che non è mai stata usata — abbiamo sempre scelto l'opzione 2 (flash), fallita prima di scrivere alcunché. Entrambe le plug continuano a funzionare normalmente con l'app SmartLife.

### Cosa resta da fare

| Opzione | Costo | Note |
|---|---|---|
| **USB-TTL** | ~5 € | Flash diretto, deterministico. Salta Cloudcutter. Mappatura GPIO già nota |
| **Raspberry Pi Zero 2 W** | già posseduto | Fa da programmatore seriale via GPIO 14/15. Vedi sotto |
| **ESP32 + Lightleak** | ~5 € | Dump wireless della flash → costruzione profilo → flash. Tre fasi, la seconda difficile. L'ESP32 resta utile per ESPHome |
| **Issue sul repository** | gratis | Serve comunque un dump per costruire il profilo |

Il Raspberry Pico 2 **non è utilizzabile** per Lightleak: serve un chip supportato da LibreTiny (ESP32/ESP8266/BK7231/RTL8710B), e l'RP2350 non lo è — nemmeno nella variante Pico 2 W.

### Zero 2 W come programmatore seriale — preparato, non ancora operativo

Lo Zero 2 W può sostituire l'adattatore USB-TTL: ha una UART hardware sui GPIO. La microSD è stata preparata con [`scripts/prepare-zero2w-sd.sh`](scripts/prepare-zero2w-sd.sh), ma **al 13 agosto 2026 non è ancora stato raggiunto in rete**.

Collegamenti previsti (plug **scollegata dalla 230 V**):

| Zero 2 W | Pin fisico | Modulo CB2S |
|---|---|---|
| GPIO14 TXD | 8 | RX (pin P11 del modulo) |
| GPIO15 RXD | 10 | TX (pin P10 del modulo) |
| GND | 6 | GND |
| 3.3V | 1 | 3.3V / VBAT |

TX e RX vanno **incrociati**. Serve inoltre portare **CEN a GND** per un istante, per far entrare il chip in modalità programmazione.

Sulla plug B i pad `3.3V`, `GND` e `CEN` sono serigrafati; `RX` e `TX` no, ma corrispondono ai pin **P10** e **P11** del modulo.

**Attenzione all'alimentazione:** il BK7231 assorbe oltre 50 mA di picco e il pin 3.3V dello Zero eroga poco. Un flash che si interrompe a metà è quasi sempre questo — serve alimentazione 3.3 V esterna con masse in comune.

Il primo comando dev'essere un **backup**, non il flash: permette di tornare indietro e rivela la mappa GPIO reale della revisione.

**Problemi incontrati nella preparazione:**

- `custom.toml` **non funziona** con un'immagine scritta via `dd`: quel meccanismo richiede il `firstrun.sh` generato da Raspberry Pi Imager. La configurazione va scritta direttamente sul filesystem (connessione in `/etc/NetworkManager/system-connections/` con permessi `600`, chiave in `/home/pi/.ssh/authorized_keys`, shell dell'utente `pi` da `nologin` a `/bin/bash`)
- L'utente risultante è **`pi`**, non quello previsto da `custom.toml`
- Una microSD si è rivelata guasta: si scollegava a ogni scrittura mentre la lettura funzionava — NAND a fine vita
- LED verde **fisso** = boot non partito, quasi sempre contatto della microSD. Lampeggio irregolare = sta leggendo, tutto bene

### Ambiente Cloudcutter — note operative

- Repository clonato in `~/6Local/tuya-cloudcutter`
- Richiede **Docker** e un **adattatore WiFi dedicato** con modalità AP. Il Sitecom WL-608 (`rt2800usb`) funziona ma è 802.11g e si è scollegato spontaneamente una volta
- Occupa la **porta 53**: va fermato `systemd-resolved` insieme ai suoi socket (`systemd-resolved-monitor.socket`, `systemd-resolved-varlink.socket`, altrimenti riparte), sostituendo `/etc/resolv.conf` con un DNS diretto
- Il flag `-p` vuole il **device slug**, non il profile slug
- Se un run si interrompe resta un container orfano: `sudo docker rm -f cloudcutter`
- Non è pilotabile via `tmux send-keys`: Docker rifiuta il TTY e si blocca su *"Loading options"*. Va lanciato da un terminale interattivo vero
- Per il flash serve la **modalità AP** (lampeggio lento, crea la rete `SmartLife-XXXX`), non la EZ (lampeggio veloce, non crea nulla)

Riferimenti: [Teardown 3202087](https://www.elektroda.com/news/news4087228.html) · [Template 3202087](https://templates.blakadder.com/lsc_smart_connect_3202087.html) · [Tuya-CloudCutter](https://github.com/tuya-cloudcutter/tuya-cloudcutter) · [OpenBK LSC Action](https://github.com/hkiam/OpenBK_LSC_Action1681PG)

## Zigbee preferito a WiFi per i sensori

Per sensori e attuatori, Zigbee via Zigbee2MQTT è preferibile a dispositivi WiFi/Tuya:

- Funziona in locale, senza dipendere dal cloud del produttore
- Le batterie durano 1-2 anni contro settimane
- Non satura il WiFi con decine di dispositivi
- La rete mesh migliora con l'aumentare dei nodi alimentati

Richiede una chiavetta coordinatore (SkyConnect o Sonoff ZBDongle-E) con passthrough USB alla VM.
