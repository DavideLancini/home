# home

Domotica di casa: Home Assistant su un mini PC con Proxmox, accessibile da internet tramite un VPS.

## Accessi

| Cosa | Dove |
|---|---|
| Home Assistant (LAN) | <http://192.168.1.37/> — **porta 80** |
| Home Assistant (internet) | <https://ha.lancini.net> |
| Proxmox | <https://192.168.1.2:8006> |
| Shell Proxmox | `ssh proxmox` |

## Documentazione

| File | Contenuto |
|---|---|
| [INFRASTRUCTURE.md](INFRASTRUCTURE.md) | Hardware, rete, configurazione di Proxmox e della VM |
| [CONFIGURATION.md](CONFIGURATION.md) | Aree, dispositivi, automazioni, backup, API |
| [REMOTE-ACCESS.md](REMOTE-ACCESS.md) | Tunnel SSH, nginx, certificato: com'è pubblicato su internet |
| [RUNBOOK.md](RUNBOOK.md) | Operazioni ricorrenti e diagnosi dei guasti |
| [AUTOMATIONS.md](AUTOMATIONS.md) | Dispositivi, automazioni e progetti pianificati |
| [DECISIONS.md](DECISIONS.md) | Scelte architetturali e alternative scartate |
| [POSTMORTEM-2026-08-11.md](POSTMORTEM-2026-08-11.md) | Il debug andato storto durante l'installazione |

## Stato

Base funzionante dall'11 agosto 2026: Proxmox 9.2.2, Home Assistant OS 18.2, accesso remoto attivo.

Configurati: aree, presenza dal telefono, notifiche push, quattro automazioni.
Collegati: robot aspirapolvere Roborock, smart TV (DLNA), Google Home Mini.

**Nessun backup attivo, per scelta** — vedi [CONFIGURATION.md](CONFIGURATION.md).

**Prossimi passi:**

- [ ] Collegare le smart plug LSC — bloccate sull'accesso alle chiavi Tuya, vedi [CONFIGURATION.md](CONFIGURATION.md)
- [ ] Chiavetta Zigbee + passthrough USB alla VM
- [ ] Sensori temperatura nelle stanze principali
- [ ] Integrazione dedicata per la smart TV (ora solo DLNA)
- [ ] Firmware locale sulle plug (OpenBeken) — vedi [DECISIONS.md](DECISIONS.md)
