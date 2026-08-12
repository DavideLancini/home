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

## Smart plug Tuya: firmware locale — da decidere

Le smart plug sono **LSC Smart Connect** di Action, con firmware aggiornato a `v1.1.17`. L'obiettivo è farle funzionare senza passare dai server Tuya.

Il chip è **Beken BK7231N/T** (moduli CB2S/CB3S/WB2S), non ESP8266: quindi né ESPHome né Tasmota, il firmware alternativo è **OpenBeken**.

Tre strade:

| Metodo | Cosa comporta | Rischio |
|---|---|---|
| **Tuya-Cloudcutter** (OTA) | Nessun cacciavite, ma Tuya ha patchato l'exploit a febbraio 2022 e `v1.1.17` è quasi certamente successiva | Nullo — se fallisce, non danneggia |
| **Flash seriale** | Aprire la plug, saldare GND/3.3V/RX/TX, adattatore USB-TTL | Medio — 230 V, da fare scollegata |
| **LocalTuya** | Nessun flash: si estraggono le chiavi e HA parla in locale | Nullo |

**Da provare per primo: LocalTuya.** Dà il funzionamento locale senza aprire nulla né rischiare di rendere inservibili le plug. Il flash resta possibile in seguito.

Nota per il flash seriale: il BK7231 assorbe oltre 50 mA di picco e molti adattatori USB-TTL economici non reggono — serve alimentazione 3.3 V esterna. Conviene fare prima un backup del firmware originale, che rivela la mappa GPIO della specifica revisione hardware.

Riferimenti: [OpenBK LSC Action](https://github.com/hkiam/OpenBK_LSC_Action1681PG) · [Tuya-CloudCutter](https://github.com/tuya-cloudcutter/tuya-cloudcutter) · [Teardown LSC 3202087](https://www.elektroda.com/news/news4087228.html)

## Zigbee preferito a WiFi per i sensori

Per sensori e attuatori, Zigbee via Zigbee2MQTT è preferibile a dispositivi WiFi/Tuya:

- Funziona in locale, senza dipendere dal cloud del produttore
- Le batterie durano 1-2 anni contro settimane
- Non satura il WiFi con decine di dispositivi
- La rete mesh migliora con l'aumentare dei nodi alimentati

Richiede una chiavetta coordinatore (SkyConnect o Sonoff ZBDongle-E) con passthrough USB alla VM.
