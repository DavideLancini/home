# Infrastruttura

Stato dell'installazione al 12 agosto 2026.

## Hardware

**HP EliteDesk 800 G2 DM 65W** — Intel i5-6400T (4 core, Skylake), 7.6 GB RAM, NVMe WDC SN520 238 GB.

VT-x e VT-d/IOMMU sono attivi nel BIOS (verificato con `dmesg | grep DMAR`), quindi il passthrough della iGPU per Frigate è già possibile senza rimettere mano al firmware.

Voci BIOS rilevanti su questo modello:

| Impostazione | Percorso | Valore |
|---|---|---|
| Wake on LAN | Advanced → Built-In Device Options | *Boot to Network* |
| After Power Loss | Advanced → Power Management Options | *Power On* |
| VT-d | Advanced → System Options | attivo |

## Rete

Sottorete `192.168.1.0/25` — arriva a `.126`, non a `.254`. Gateway `192.168.1.1`.

Scrivere `/24` al posto di `/25` rende il gateway irraggiungibile: è un errore facile e con sintomi confusi.

| Range | Uso |
|---|---|
| `.1` | Gateway |
| `.2` | Proxmox (reservation DHCP) |
| `.3` | Occupato — MAC `a8:fa:d8:3b:e5:0b`, dispositivo non identificato |
| `.4`–`.36` | Riservati nel modem |
| `.37`+ | Assegnazione statica — **`.37` = Home Assistant** |
| `.50`–`.126` | Pool DHCP |

**IPv6 non funziona sull'host.** `vmbr0` riceve solo un indirizzo link-local, nessun Router Advertisement. Curiosamente la VM HA ottiene invece un IPv6 globale via SLAAC, quindi è una questione di configurazione del bridge, non della rete. Per ora l'host è IPv4-only e non è un problema.

## Proxmox

Proxmox VE 9.2.2, kernel `7.0.14-11-pve`, su `192.168.1.2/25` (MAC `40:b0:34:fe:a2:62`).

Accesso: `ssh proxmox` (definito in `~/.ssh/config`, chiave `id_ed25519_dawn`, senza password).

**Configurazione applicata:**

- Repo `pve-no-subscription` in formato deb822 (`/etc/apt/sources.list.d/`), popup di subscription rimosso
- `apt` forzato su IPv4 in `/etc/apt/apt.conf.d/99force-ipv4` — senza, tenta l'IPv6 e fallisce con `Network is unreachable`
- IPv4 preferito nella risoluzione dei nomi (`/etc/gai.conf`)
- Timezone `Europe/Rome`
- Wake-on-LAN persistente via `wol@nic0.service` (`Wake-on: g`)
- Pacchetti aggiuntivi: `tmux`, `ethtool`, `htop`, `iotop`, `lm-sensors`

**L'interfaccia di rete si chiama `nic0`**, non `enp1s0`: è il nuovo schema di naming di Proxmox 9. Va usato quel nome in `/etc/network/interfaces` e nei comandi `ethtool`.

Layout dei dischi: `pve-root` 69 GB, `pve-data` (LVM-thin per le VM) 141 GB, swap 7.6 GB.

## VM Home Assistant

VMID 100, `haos-18.2`, creata con lo **script ufficiale della community** (vedi [RUNBOOK.md](RUNBOOK.md) per la procedura).

| Parametro | Valore |
|---|---|
| CPU | `kvm64` (default dello script) |
| RAM | 4096 MB |
| Core | 2 |
| Disco | 32 GB su `local-lvm`, `discard=on`, `ssd=1` |
| Firmware | OVMF (UEFI), macchina `q35` |
| Rete | `virtio`, bridge `vmbr0`, MAC `02:9D:16:D9:80:13` |
| Avvio automatico | `onboot=1` |
| Guest agent | attivo |

IP statico `192.168.1.37/25`, configurato dentro HA con `ha network update` (non via DHCP).

**Home Assistant serve l'interfaccia sulla porta 80**, non sulla 8123 canonica. È il dettaglio che ha causato l'incidente dell'11 agosto — vedi [POSTMORTEM-2026-08-11.md](POSTMORTEM-2026-08-11.md).

## Installazione di Proxmox — note

L'ISO ufficiale **non fa boot UEFI su questo hardware**: si ferma con

```
relocation 0x41615252 is not implemented yet
```

Quel valore è ASCII `RRaA`, la firma di un blocco FSInfo FAT: il firmware interpreta il filesystem come codice PE da rilocare. È un bug del boot ibrido HFS+ dell'immagine Proxmox su certi UEFI, non un problema di Secure Boot né della scrittura della chiavetta.

**Risolto con Ventoy**, che usa il proprio bootloader:

```bash
yay -S ventoy-bin
sudo ventoy -i -g -I /dev/sdX          # -g = GPT, richiesto da UEFI puro
sudo mount /dev/sdX1 /mnt/ventoy
sudo cp proxmox-ve_9.2-1.iso /mnt/ventoy/
sudo umount /mnt/ventoy
```

L'installer di Proxmox è interattivo e va seguito da monitor. Da lì in avanti tutto il resto si fa via SSH.
