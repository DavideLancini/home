# Postmortem — 11 agosto 2026

Un'installazione che avrebbe richiesto un'ora ne ha richieste otto. Home Assistant ha funzionato quasi da subito; il tempo è andato in una diagnosi sbagliata, ripetuta e mai messa in discussione.

## Cosa è successo

Dopo l'installazione, HA risultava irraggiungibile. Ogni verifica su `192.168.1.37:8123` falliva: `curl` non rispondeva, `netstat` dentro la VM non trovava la porta in ascolto, il tunnel SSH restituiva `502`.

Ne è seguita una diagnosi che ha attraversato, in ordine: spegnimento improvviso, corruzione del Supervisor, database SQLite corrotto, integrazione Bluetooth su hardware assente, incompatibilità della CPU virtuale, segmentation fault in librerie native, e infine il sospetto di RAM difettosa.

**Quattro VM distrutte e ricreate. Tre onboarding fatti rifare all'utente.**

La causa vera: **questa installazione di HAOS serve l'interfaccia sulla porta 80, non sulla 8123.** Home Assistant non ha mai smesso di funzionare. Ogni test falliva correttamente, perché interrogava una porta che non è mai stata in uso.

Risolto quando l'utente ha scritto: *"http://192.168.1.37/ funziona"*.

## Le due cause sovrapposte

**Depistaggio.** Dopo ogni ricreazione la VM prendeva un IP DHCP nuovo (`.87`, poi `.73`), mentre l'entry ARP di `.37` sopravviveva come residuo della VM precedente — stesso MAC. Il `ping` su `.37` rispondeva, quindi sembrava la macchina giusta. Questo ha spostato il sospetto dentro HA anziché sull'indirizzamento, e ha portato a dichiarare "risolto" un problema che non lo era.

**Il guasto vero.** La porta sbagliata. `netstat` che non trovava la 8123 è stato letto come *"HA non parte"* invece che *"HA ascolta altrove"*. Da quella singola inferenza errata è derivato tutto il resto.

## Ipotesi inseguite e scartate

| Ipotesi | Come è stata scartata |
|---|---|
| Spegnimento col pulsante (`Power key pressed short` nei log) | Il problema si è ripresentato senza spegnimenti |
| Blocco `http:`/`trusted_proxies` errato | Rimosso, nessun cambiamento |
| Database SQLite corrotto (WAL 659 KB, `.db` 4 KB) | WAL spostato, nessun cambiamento |
| Integrazione Bluetooth su VM senza hardware | Assente da `core.config_entries` |
| Configurazione o integrazioni | La recovery mode le bypassa, sintomo invariato |
| CPU `host` incompatibile | Provate `x86-64-v2-AES`, `x86-64-v3`, `kvm64`: nessuna differenza |
| Segmentation fault in librerie native | Il dump era reale, ma **conseguenza del `SIGABRT` inviato per ottenerlo** |
| RAM difettosa | Mai verificata — ipotesi formulata per esclusione, senza evidenza |

Le ultime due meritano attenzione: erano diagnosi *inventate per giustificare i sintomi*, non dedotte da prove. Il segfault in particolare è stato presentato all'utente come causa accertata, mentre era un artefatto del metodo di indagine.

## Errori commessi

**Interpretare un'assenza come un guasto.** `netstat` senza risultati per la porta 8123 era un dato corretto e informativo. Bastava un `netstat -tln` *senza filtro* per vedere la 80 in ascolto.

**Non prendere sul serio l'utente.** Alla frase "in locale funziona" la risposta è stata spiegare perché non era possibile, invece di chiedere *quale URL* stesse guardando. Quella domanda avrebbe chiuso il caso ore prima. Quando l'osservazione di chi guarda contraddice i test, la contraddizione *è* il dato più importante.

**Dichiarare risolto senza verificare.** Il problema è stato dato per chiuso tre volte. Ogni volta la verifica era parziale o interpretata con ottimismo.

**Distruggere prima di capire.** Quattro VM ricreate senza aver isolato la causa: ogni ricreazione azzerava lo stato e costava un onboarding all'utente, senza aggiungere informazione.

**Scartare lo strumento ufficiale.** Lo script della community è stato saltato perché interattivo, replicandone i comandi a mano. Bastava `tmux` — già installato sull'host — per pilotarlo.

**Sovrascrivere invece di accodare.** Un `cat >> configuration.yaml` ha cancellato il file invece di estenderlo, rimuovendo `default_config:` e gli include. Ha aggiunto un guasto reale a uno immaginario.

## Cosa avrebbe funzionato

```bash
ssh proxmox 'qm guest exec 100 --timeout 30 -- /bin/sh -c "netstat -tln"'
```

Senza `grep 8123`. Cinque minuti invece di otto ore.

In alternativa, leggere i log del container: dicevano `Start webserver on http://0.0.0.0:8123` all'avvio del wrapper, ma soprattutto annunciavano via mDNS l'indirizzo reale. L'informazione era disponibile fin dal primo minuto.

## Regole ricavate

1. **Verificare su quale porta ascolta un servizio** prima di concludere che non funzioni. Enumerare, non filtrare.
2. **Chiedere l'IP al guest agent** dopo aver ricreato una VM. La cache ARP sopravvive con lo stesso MAC e mente.
3. **Quando l'utente dice che qualcosa funziona**, chiedere cosa sta guardando. La discrepanza è la diagnosi.
4. **Non presentare come accertata** una causa dedotta per esclusione.
5. **Usare l'installer ufficiale** quando esiste, anche se è scomodo da automatizzare.
6. **Leggere i log dell'applicazione** prima di formulare ipotesi sull'infrastruttura.
