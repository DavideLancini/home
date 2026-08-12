# Accesso remoto

Home Assistant è pubblicato su <https://ha.lancini.net> tramite un reverse tunnel SSH verso il VPS `elisabetta` (`87.106.233.97`), che fa da reverse proxy. Serve perché la rete di casa non ha IP fisso.

## Catena

```
browser → https://ha.lancini.net        (nginx su elisabetta, TLS)
        → 127.0.0.1:8123                (capo del tunnel su elisabetta)
        → tunnel SSH                    (aperto da proxmox verso elisabetta)
        → 192.168.1.37:80               (Home Assistant in LAN)
```

Il tunnel è aperto **da** casa verso il VPS, non viceversa: è quello che permette di aggirare l'assenza di IP fisso e di non aprire porte sul router.

Nota le due porte diverse: `8123` è solo il capo locale del tunnel su elisabetta, mentre HA ascolta davvero sulla **80**.

## Su Proxmox

`/etc/systemd/system/ha-tunnel.service`:

```ini
[Unit]
Description=Reverse SSH tunnel: Home Assistant -> elisabetta
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/ssh -NT \
  -i /root/.ssh/id_ed25519_tunnel \
  -o BatchMode=yes \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3 \
  -o StrictHostKeyChecking=accept-new \
  -R 127.0.0.1:8123:192.168.1.37:80 \
  elisabetta@87.106.233.97
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

`ServerAliveInterval` rileva le connessioni morte, `ExitOnForwardFailure` evita che il tunnel resti su senza aver stabilito il forward, `Restart=always` lo riporta su. La combinazione ha già superato un blocco temporaneo dell'host, riconnettendosi da sola.

Usa la chiave dedicata `/root/.ssh/id_ed25519_tunnel`, separata dalle altre così è revocabile da sola.

## Su elisabetta

**Chiave in `~/.ssh/authorized_keys`**, con restrizioni:

```
restrict,port-forwarding ssh-ed25519 AAAA... proxmox-ha-tunnel
```

`restrict` nega tutto (shell, agent forwarding, X11, PTY), `port-forwarding` riabilita solo l'inoltro. Se la chiave venisse compromessa, non darebbe accesso al VPS.

Attenzione: `permitopen="127.0.0.1:8123"` **non** funziona qui — vale per i forward locali (`-L`), non per quelli remoti (`-R`), e la sua presenza fa fallire il tunnel con `Connection reset by peer`.

**`/etc/nginx/sites-available/ha.lancini.net`:**

```nginx
server {
    listen 443 ssl;
    server_name ha.lancini.net;

    ssl_certificate /etc/letsencrypt/live/ha.lancini.net/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/ha.lancini.net/privkey.pem;

    client_max_body_size 128M;

    location / {
        proxy_pass http://127.0.0.1:8123;
        proxy_http_version 1.1;
        proxy_set_header Host $host;

        # Senza questi la UI si carica ma resta congelata
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_read_timeout 90s;
        proxy_send_timeout 90s;
    }
}
```

Gli header `X-Real-IP`, `X-Forwarded-For` e `X-Forwarded-Proto` sono stati **rimossi**: HA li rifiutava con `400` nonostante `trusted_proxies` fosse configurato correttamente. Vedi *Punto aperto* più sotto.

**`/etc/nginx/sites-available/ha-acme`** — serve le challenge ACME in HTTP senza redirect:

```nginx
server {
    listen 80;
    server_name ha.lancini.net;
    location /.well-known/acme-challenge/ {
        root /var/www/ha.lancini.net;
    }
    location / { return 301 https://$host$request_uri; }
}
```

Necessario perché `00-redirect-80-to-443` (redirect globale) manderebbe la challenge su HTTPS, e il rinnovo fallirebbe. Senza questo file il certificato scadrebbe silenziosamente.

**Certificato:** Let's Encrypt via webroot, rinnovo automatico. Verificato con:

```bash
sudo certbot renew --cert-name ha.lancini.net --dry-run
```

Da rifare dopo ogni modifica ai vhost sulla porta 80.

## In Home Assistant

`configuration.yaml` contiene:

```yaml
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 192.168.1.2
    - 172.30.32.0/23
    - 127.0.0.1
```

## Punto aperto

Questa configurazione è incoerente e andrebbe sistemata: HA ha `use_x_forwarded_for: true` ma nginx non invia più gli header `X-Forwarded-*`.

Funziona, ma con una conseguenza: **nei log HA l'IP dei client sarà sempre quello del tunnel**, non quello reale. Questo rende inutile il ban automatico per tentativi di login falliti (`http.ban`), che vedrebbe un solo IP per tutti.

Da capire perché `trusted_proxies` non veniva applicato pur essendo corretto nel file. Ipotesi da verificare: HA riceveva le richieste da `127.0.0.1` (capo del tunnel) e non da `192.168.1.2` come indicato nel messaggio d'errore.

## Sicurezza

L'istanza è **esposta su internet**. L'unica difesa è l'autenticazione di Home Assistant.

Da valutare:

- `fail2ban` su elisabetta per i tentativi di login ripetuti
- Autenticazione a due fattori in HA (Impostazioni → Persone → il tuo utente)
- Risolvere il punto aperto sopra, per rendere efficace il ban per IP

Nota: l'hostname `ha.lancini.net` è pubblico nei log di Certificate Transparency, quindi non è segreto.
