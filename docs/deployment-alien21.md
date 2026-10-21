# Nasazení na rustdesk.alien21.lan

Návod vychází z read-only auditu 21. 10. 2026. Příkazy provádí správce na Linux serveru; nic z tohoto návodu nebylo na server nasazeno.

## Váš bezplatný stack a RustDesk Server Pro

Používáte bezplatné nativní klienty RustDesk, vlastní OSS servery `hbbs`/`hbbr` a samostatné vlastní API. Audit u API uváděl verzi 2.7; jeho konkrétní implementaci tím neurčil. Tento návod zachovává vaši API službu a HTTPS reverse proxy a nenahrazuje je produktem RustDesk Server Pro.

Oficiální RustDesk Server Pro je placený serverový produkt s webovou konzolí, vlastním API a centrální správou. Jeho HTTP API standardně používá TCP 21114. Stejné číslo portu u vašeho samostatného free API neznamená použití Pro. [Oficiální rozdělení OSS a Pro](https://rustdesk.com/docs/en/self-host/), [funkce a licence Server Pro](https://rustdesk.com/docs/en/self-host/rustdesk-server-pro/).

Naše DNS načítání veřejného Key, Private key/ACCESS_KEY a dočasné pozvánky jsou úpravy tohoto OSS sestavení; licenci Pro nevyžadují. Pokud chcete nejprve jen DNS načítání Key, stačí aktualizovat klienta: server, jeho porty a vaše API mohou zůstat současné. Soukromý přístup a pozvánky vyžadují také oba upravené servery, ale sdílejí stávající TCP 21116/21117 a nevyžadují další otevřené porty.

## Výchozí stav a pořadí změn

Server je Debian 13.7 amd64, interní adresa `10.30.10.139`, veřejné jméno `rustdesk.home.alien21.com`. Balíčky hbbs/hbbr mají verzi 1.1.14. Jednotky `rustdesk-hbbs.service` a `rustdesk-hbbr.service` jsou v `/lib/systemd/system/`, spouštějí `/usr/bin/hbbs` a `/usr/bin/hbbr` a pracují v `/var/lib/rustdesk-server/`. Nemají EnvironmentFile; prázdné User/Group znamená výchozí root.

Nejprve aktualizujte vlastní klienty. Na Windows proveďte instalaci/aktualizaci z nového EXE, aby novou verzi používala i služba RustDesk. Potom klienta spusťte z aktualizované instalace, například z nabídky Start; GUI a služba musí používat stejnou kopii programu. Po zapnutí ACCESS_KEY se neupravené vlastní klienty přestanou registrovat a obecně používat relay; neupravení hosté budou potřebovat platnou pozvánku. První verze soukromých spojení používá vždy relay, proto počítejte s provozem přes server i tam, kde dříve fungovalo P2P.

Samotné DNS hledání veřejného Key funguje v upraveném klientu i se starým serverem. Ochrana pomocí ACCESS_KEY a pozvánky vyžadují oba upravené servery; vlastní klienty i neupravení hosté používají stávající porty serveru.

## Cloudflare DNS

Veřejné DNS nyní používá `rustdesk.home.alien21.com CNAME home.alien21.com` (TTL 300 s); jeho IPv4 odpověď při auditu byla 78.80.175.191. Zachovejte tento CNAME i současnou DDNS aktualizaci cíle `home.alien21.com`. Nový A záznam na stejném jméně nepřidávejte. V zóně `alien21.com` nastavte:

| Typ | Název v Cloudflare | Obsah | Nastavení |
| --- | --- | --- | --- |
| CNAME | `rustdesk.home` | `home.alien21.com` — zachovat současný cíl | DNS only, šedý obláček |
| TXT | `_rustdesk.rustdesk.home` | `v=1;key=KKh+mCbFddyWWVEtMONkRTtFY2fiw9mVAJa2MZOmXdU=` | TTL 300 s |

Veřejná kontrola přes Cloudflare DoH 21. 10. 2026 po dokončení DNSSEC vrací správný RustDesk Key a **`AD:true`** pro `_rustdesk.rustdesk.home.alien21.com` i `_rustdesk.rustdesk.home.alien21.cz`. DS záznamy obou domén jsou publikované a ověřené. DNS část pro vynechání pole Key v upraveném klientu je tedy připravená. TXT název vzniká přidáním předpony `_rustdesk.` před celý ID server: pro `rustdesk.home.alien21.cz` je tedy správně `_rustdesk.rustdesk.home.alien21.cz`, pro `.com` obdobně. Oba tyto záznamy jsou již správně nastavené.

TXT obsahuje veřejný `id_ed25519.pub` z auditu, nikdy ACCESS_KEY ani soukromý `id_ed25519`. Plný TXT název je `_rustdesk.rustdesk.home.alien21.com`. Vytvořte právě jeden takový záznam. Běžná oranžová HTTP proxy nepřenáší nativní RustDesk TCP/UDP provoz; proto musí být adresa DNS only. Toto nastavení se týká i HTTPS stejné domény: před změnou ověřte přímou dostupnost současné API/reverse proxy na 443 s platným TLS certifikátem. [Omezení Cloudflare proxy](https://developers.cloudflare.com/dns/proxy-status/limitations/).

Doména je registrovaná u WEDOSu, DNS spravuje Cloudflare. DNSSEC pro celou `alien21.com` nastavte jednorázově takto:

1. V Cloudflare otevřete **alien21.com → DNS → Settings → DNSSEC → DS record**. Podepisování při kontrole už běželo; pokud je v budoucnu vypnuté, nejprve zvolte Enable DNSSEC. Poznamenejte si hodnoty **Key Tag, Algorithm, Digest Type a Digest**. [Postup Cloudflare DNSSEC](https://developers.cloudflare.com/dns/dnssec/).
2. V zákaznické administraci WEDOS otevřete **Domény → alien21.com → Nastavení DNSSEC**. Zvolte **použít vlastní DNSSEC klíče**, v tabulce **Vlastní DNSSEC klíče** vyberte typ **Digest**, vyplňte odpovídající údaje z Cloudflare a potvrďte **Nastavit DNSSEC**. WEDOS uvádí propagaci až 6 hodin. Pro tuto `.com` doménu se používá část návodu pro generické domény. [Postup WEDOS](https://kb.vedos.cz/domeny-dnssec/).
   Vyplňte pouze první řádek Digest tabulky: **Key Tag = Key Tag z Cloudflare** (při kontrole 2371), **Typ šifrování = SHA256 (2)**, **Algoritmus = ECDSAP256SHA256 (13)** a **Digest = celé pole Digest z Cloudflare**. Ostatní řádky ponechte prázdné. Nekopírujte do Digest celý řádek DS Record ani Public Key. Horní upozornění WEDOSu na jiné DNS servery odpovídá použití Cloudflare.

3. Ponechte nameservery Cloudflare. Do tohoto formuláře patří údaje DNSSEC z Cloudflare, nikoli RustDesk veřejný Key nebo ACCESS_KEY. Po propagaci ověřte níže uvedeným dotazem `AD:true`.

Ověřte zvenku; `dig` poskytuje balíček `dnsutils`:

```bash
dig @1.1.1.1 _rustdesk.rustdesk.home.alien21.com TXT +dnssec
curl --fail --get 'https://cloudflare-dns.com/dns-query' \
  --header 'Accept: application/dns-json' \
  --data-urlencode 'name=_rustdesk.rustdesk.home.alien21.com' \
  --data 'type=TXT&do=true&cd=false'
```

`dig` musí vrátit správný TXT a příznak `ad`. DoH odpověď musí mít `Status:0`, `AD:true`, `CD:false`, `TC:false` a správný TXT. Upravený klient bez vyplněného Key odmítne neověřenou/chybějící DNS odpověď; ručně vyplněný Key má přednost. Klientům povolte odchozí HTTPS 443 na `cloudflare-dns.com`. Interní jméno `rustdesk.alien21.lan` veřejné DNS vyhledání nenahradí; v LAN používejte veřejné jméno s lokálním DNS směrováním na 10.30.10.139 nebo funkční NAT loopback.

## Firewall a NAT

Pro běžné připojení nativních desktopových klientů k OSS serveru zachovejte toto minimum. Na routeru případně přesměrujte stejné externí porty na `10.30.10.139` a povolte je i ve firewallu serveru:

| Porty | Účel |
| --- | --- |
| TCP 21115 | NAT test hbbs |
| TCP a UDP 21116 | registrace, rendezvous a navazování spojení přes hbbs |
| TCP 21117 | přenos přes relay hbbr |

Soukromé řízení používá **TCP 21116 (hbbs)** a autentizovaný relay **TCP 21117 (hbbr)**. Neupravený host s platnou pozvánkou používá stejné porty. Upravený klient na začátku pošle jednoznačný rozlišovací rámec v existujícím RustDesk rámování; server podle něj zvolí soukromý transport, zatímco běžné zprávy veřejných klientů zpracuje jejich dosavadní cestou. Soukromý transport ověří podpis serveru a používá šifrované záznamy; PSK se posílá až uvnitř tohoto šifrovaného přihlášení. Rozlišovací rámec sám žádné oprávnění nedává. Pro DNS hledání Key ani pro tento soukromý režim neotvírejte další příchozí porty. [Oficiální minimum portů](https://rustdesk.com/docs/en/self-host/#ports-required).

Ostatní služby posuzujte samostatně:

| Port | Kdy jej potřebujete | Co platí pro váš server |
| --- | --- | --- |
| TCP 21114 | HTTP API; v oficiálním Server Pro také webová konzole | Zde jej již používá vaše samostatné free API. Zachovejte současné interní napojení reverse proxy; není potřeba jej nově vystavovat do internetu. |
| TCP 443 | HTTPS reverse proxy pro API, případně WSS | Zachovejte současný HTTPS přístup k vašemu API. Samotné nativní OSS spojení tento příchozí port nepotřebuje. |
| TCP 21118 a 21119 | Volitelné WebSocket rozhraní hbbs/hbbr | Pro běžné nativní spojení nejsou potřeba. Pokud používáte WS/web klienta, zachovejte odpovídající proxy; s WSS obvykle stačí dostupnost těchto portů z reverse proxy. |

WebSocket listenery 21118/21119 obsahuje i OSS server; samotné tyto porty nejsou důkazem Pro ani kompletním webovým klientem. [Porty OSS serveru](https://github.com/rustdesk/rustdesk-server/blob/master/docs/environment-variables.md#port-reference). Příchozí HTTPS vašeho API je také oddělené od odchozího HTTPS 443 na Cloudflare DoH, které upravený klient používá pro DNS načítání Key.

Audit našel pouze prázdnou výchozí `/etc/nftables.conf`. Runtime firewall a pravidla routeru tím nejsou ověřena. Před změnou si zobrazte `sudo nft list ruleset` a doplňte pravidla do používaného firewallu; existující pravidla nemažte ani neprovádějte `flush ruleset`.

## Výměna binárek a záloha

Z výstupu [sestavení](../README.build.md) `artifacts/publish/linux-x64/` přeneste oba nové soubory `hbbs` a `hbbr` do `/root/rustdesk-release/` na serveru. Musí jít o Linux x64 binárky ze stejného sestavení. Pro tento existující server použijte výměnu binárek; instalace nových .deb by mohla současně změnit správu služeb.

V následujícím bloku pracujte jako root. Zastavení přeruší aktuální relace; zastavený hbbs umožní konzistentní kopii SQLite včetně případných WAL/SHM souborů.

```bash
sudo -i
set -e
umask 077
command -v openssl >/dev/null
test -s /root/rustdesk-release/hbbs && test -s /root/rustdesk-release/hbbr
backup=/root/rustdesk-backup-$(date +%Y%m%d-%H%M%S)
mkdir -p "$backup"
systemctl stop rustdesk-hbbs.service rustdesk-hbbr.service
cp -a /var/lib/rustdesk-server "$backup/state"
cp -a /usr/bin/hbbs /usr/bin/hbbr "$backup/"
cp -a /lib/systemd/system/rustdesk-hbbs.service /lib/systemd/system/rustdesk-hbbr.service "$backup/"
for binary in hbbs hbbr; do
  install -o "$(stat -c %u /usr/bin/$binary)" -g "$(stat -c %g /usr/bin/$binary)" \
    -m "$(stat -c %a /usr/bin/$binary)" /root/rustdesk-release/$binary /usr/bin/$binary
done
```

Ponechte celý původní datový adresář, vlastníky a oprávnění. Oba procesy musí dál sdílet původní `id_ed25519` a `id_ed25519.pub`. Nevytvářejte nové podpisové klíče; změnil by se Key v DNS i u klientů. `rustdesk-api.service`, jeho binárka, konfigurace i data zůstávají původní.

## Soukromý přístup v systemd

Stále jako root vytvořte jeden náhodný přístupový klíč pro oba procesy. Při opakování návodu se existující hodnota nepřegeneruje:

```bash
install -d -o root -g root -m 0700 /etc/rustdesk
if [ ! -e /etc/rustdesk/private-access.env ]; then
  { printf 'ACCESS_KEY='; openssl rand -hex 32; } > /etc/rustdesk/private-access.env
fi
chown root:root /etc/rustdesk/private-access.env
chmod 0600 /etc/rustdesk/private-access.env
install -d /etc/systemd/system/rustdesk-hbbs.service.d /etc/systemd/system/rustdesk-hbbr.service.d
cat > /etc/systemd/system/rustdesk-hbbs.service.d/private-access.conf <<'EOF'
[Service]
EnvironmentFile=/etc/rustdesk/private-access.env
ExecStart=
ExecStart=/usr/bin/hbbs -r rustdesk.home.alien21.com
EOF
cat > /etc/systemd/system/rustdesk-hbbr.service.d/private-access.conf <<'EOF'
[Service]
EnvironmentFile=/etc/rustdesk/private-access.env
EOF
systemctl daemon-reload
systemctl restart rustdesk-hbbs.service rustdesk-hbbr.service
systemctl status rustdesk-hbbs.service rustdesk-hbbr.service --no-pager
journalctl -u rustdesk-hbbs.service -u rustdesk-hbbr.service -n 80 --no-pager
ss -lntup | grep -E ':211(15|16|17|18|19)\b'
tail -n 40 /var/log/rustdesk-server/hbbs.log /var/log/rustdesk-server/hbbs.error
```

Soukromé i veřejné spojení obsluhují stejné listenery TCP 21116/21117. Původní jednotky zapisují hlavní logy do `/var/log/rustdesk-server/`, proto kontrolujte i tyto soubory. Soukromý ACCESS_KEY předejte pouze vlastním upraveným klientům. Při další údržbě zálohujte také env soubor a oba drop-in adresáře. Při výměně samotných binárek zůstává verze v databázi dpkg původní; skutečnou ověříte `/usr/bin/hbbs --version` a `/usr/bin/hbbr --version`. Aby aktualizace balíčků nepřepsala vlastní binárky, nastavte `apt-mark hold rustdesk-server-hbbs rustdesk-server-hbbr`; další verze pak nasazujte vlastním sestavením.

## Klienti a pozvánka

Na vlastních aktualizovaných počítačích nastavte ID server `rustdesk.home.alien21.com`, relay ponechte automatický nebo stejnou doménu a do nového pole Private key vložte hodnotu ACCESS_KEY z chráněného env souboru (bez `ACCESS_KEY=`). Je to jiný údaj než veřejný Key. Po uložení pole ukazuje pevných 20 teček. Veřejný Key lze ponechat prázdný po úspěšném ověření DNSSEC výše.

Zapněte pozvánky hostů, zvolte platnost v minutách a vytvořte pozvánku. Hostovi stačí neupravený veřejný **bezplatný desktopový klient** RustDesk; Pro účet ani Pro klient není potřeba. Pošlete celý vygenerovaný řetězec, například (ukázkové ID nahraďte skutečným):

```text
P-254785236@rustdesk.home.alien21.com?key=KKh+mCbFddyWWVEtMONkRTtFY2fiw9mVAJa2MZOmXdU=
```

Neupravený klient potřebuje `?key=`; neumí toto nové DNS hledání. Base64 vložte přímo v uvedeném tvaru včetně `+` a `=`. Upravenému klientu s podporou DNS lze poslat jen `P-…@rustdesk.home.alien21.com`. Host nedostane ACCESS_KEY a samotným nastavením vašeho relay nezíská obecný přístup. Nadále platí heslo/potvrzení/2FA hostitelského klienta.

Pozvánka je opakovaně použitelná po zvolenou dobu. Expirace či odvolání zabrání přijetí nových spojení, včetně dosud nepotvrzeného požadavku; již přijaté relace pokračují. Po restartu registrace hostitele vytvořte novou pozvánku. Ověřte zvlášť vlastní připojení, stock hosta s platnou pozvánkou a odmítnutí staré pozvánky i anonymního skutečného ID.

Pozvánky potřebují dosažitelné výše uvedené TCP porty serveru; DNS only v Cloudflare ponechá přímé směrování na server, samo však nenahrazuje firewall/NAT. Kvůli tomuto relay režimu není potřeba přesměrovávat veřejné porty na počítač sdílející plochu ani na počítač hosta. Celé připojení z neupraveného veřejného GUI klienta zatím nebylo ověřeno; ověřené jsou parser formátu a serverový protokol.

## Upozornění API a místní služba Windows

Výchozí upstream tohoto forku už obsahoval verzi `1.5.1`; vlastní sestava ji označuje příponou `-a21` jako `1.5.1-a21`. Nejde o naše zvýšení z `1.5.0`. Karta „Your installation is lower version“ porovnává datum sestavení spuštěné aplikace s instalací, takže se může objevit i při pouhém přenosném spuštění novější kopie.

Oranžové upozornění přidal upstream v commitu `c7f212df2` (20. 10. 2026); starší `1.5.0` ho ještě nemusí zobrazovat. Vztahuje se na HTTP/HTTPS adresu samostatného API. Dosavadní klient může při prázdném poli API odvodit HTTP adresu z ID serveru; toto upozornění samo nevypovídá o šifrování soukromého relay transportu ani o správnosti DNS Key. Pro své API vyplňte `https://rustdesk.home.alien21.com` bez portu a bez `/api`. Tuto adresu uvádí vaše API konfigurace a ověření `GET /api/login-options` vrací HTTP 200 s platným HTTPS certifikátem. Prázdné pole naproti tomu odvozuje `http://rustdesk.home.alien21.com:21114`. Adresa v konfiguraci samostatné API služby se do klienta automaticky nepřenese; současný hbbs protokol oznamuje relay, ale tuto API adresu neposílá. Pokud API nechcete používat, jeho chování je potřeba posoudit odděleně od nastavení ID/relay serveru.

V místním logu klienta se při souběhu nového přenosného EXE a starší nainstalované verze 1.5.0+68 opakovaně odpojuje IPC kanál (`reset by the peer`). Červený stav a heslo „Generating…“ proto nelze považovat za důkaz nedostupnosti hbbs: GUI nedostává stav od místního procesu. Základ klienta navíc při IPC ověřuje shodu cesty spustitelného souboru; konflikt cest původní instalace a přenosné kopie je podle zdroje a resetů nejpravděpodobnější příčina (přesný důvod odmítnutí by potvrdil log backendu). Tuto ochranu neoslabujeme. Pro běžný provoz aktualizujte klienta včetně jeho místní služby a ověřte, že GUI i služba používají stejnou instalaci. Samotné spuštění přenosného EXE službu neaktualizuje. Přenosný test se stávajícím profilem a ID funguje po dočasném zastavení původní služby a ukončení jejího tray. Oddělený profil ani nové testovací ID se v této sestavě nezavádějí. Původní hbbs/hbbr mohou při prázdném Private key zůstat beze změny.

Nový dialog se nyní nejprve ptá na podporu přes původní konfigurační IPC zprávu. Starší nebo nedostupná služba tak místo surové chyby v novém ovládání vyvolá srozumitelnou výzvu k aktualizaci/restartu. Dotaz na stav nevolá hbbs. Prázdný Private key zachovává původní síťovou cestu; pokud je soukromý režim již nakonfigurován, nedostupná služba nesmí jeho přihlašovací údaje potichu zahodit. Upravený server bez nastaveného ACCESS_KEY používá původní veřejný režim; s ACCESS_KEY naopak odmítá obecné použití bez PSK a veřejné hosty omezuje na platné pozvánky.

### Přenosný test vedle zachované instalace

Původní instalace může zůstat na disku. Po dobu testu ale musí skončit její služba a tray, aby nový EXE mohl převzít místní IPC a spustit vlastní backend. Zavření samotného hlavního okna službu nevypne. Test nepřepisuje instalační soubory; používá dosavadní uživatelský profil a ID, proto si před změnou nastavení poznamenejte původní hodnoty.

1. Ukončete otevřená okna klientů. V administrátorském PowerShellu spusťte `Stop-Service RustDesk`. Ukončete původní tray přes jeho nabídku.
2. Nový EXE spusťte s parametrem `--noinstall`, například `& .\rustdesk-1.5.1-a21-install.exe --noinstall`.
3. V nastavení sítě ponechte ID server `rustdesk.home.alien21.com`, relay může zůstat prázdné, API nastavte na `https://rustdesk.home.alien21.com` a Private key zatím ponechte prázdné. Veřejný Key lze zachovat.
4. Po testu ukončete přenosný klient. V administrátorském PowerShellu spusťte `Start-Service RustDesk` a původní klient spusťte z nabídky Start. Před restartem původní služby musí přenosný backend skončit.

Při testu 21. 10. 2026 přenosný klient zachoval ID, spustil vlastní IPC/backend a dostal odpověď původního hbbs přes UDP 21116 (latence přibližně 1,7 ms); opakované IPC resety ustaly. Původní služba byla po testu obnovena.

Odemčení síťových a bezpečnostních nastavení zachovává původní kontrolu administrátora Windows (UAC) i případný Unlock PIN. Výjimka pro přenosný backend byla při testu odmítnuta a odstraněna. Zelený stav Ready byl ověřen uživatelem; potíže se stále neaktivními ovládacími prvky po odemčení se ověřují samostatně.

### Běžná instalace a návrat k originálu

Pro další testování byla zvolena běžná instalace klienta včetně jeho služby, s původními kontrolami oprávnění. Postup, umístění zálohy původní verze 1.5.0+68 a ověřeného oficiálního instalátoru pro návrat uvádí [návod pro Windows](windows-installation-alien21.md). Záloha byla dokončena a původní služba obnovena; vlastní instalace ani následné odemčení nastavení zatím ověřeny nejsou.
