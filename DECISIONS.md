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

## Zigbee preferito a WiFi per i sensori

Per sensori e attuatori, Zigbee via Zigbee2MQTT è preferibile a dispositivi WiFi/Tuya:

- Funziona in locale, senza dipendere dal cloud del produttore
- Le batterie durano 1-2 anni contro settimane
- Non satura il WiFi con decine di dispositivi
- La rete mesh migliora con l'aumentare dei nodi alimentati

Richiede una chiavetta coordinatore (SkyConnect o Sonoff ZBDongle-E) con passthrough USB alla VM.
