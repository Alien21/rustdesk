# Rozsah změn develop-alien21

Přehled změn k 21. 10. 2026 zahrnuje DNS veřejného klíče, soukromý přístup a pozvánky na stávajících serverových portech, smíšený režim původních a PSK klientů s přepínačem na cílovém PC, řazení podle posledního použití, přesun výstupů a nové build skripty. Ověření jednotlivých sestavení a jejich praktické meze jsou uvedeny níže.

## Existující runtime soubory a cesty

Nová logika je soustředěna v samostatných modulech `dns_key.rs`, `access_config.rs`, `access_transport.rs` a `server_access.rs` a v nových UI widgetech. V existujících souborech zůstávají následující nutné zásahy:

| Repozitář / existující soubor | Změněná cesta a nutný důvod |
| --- | --- |
| klient: `src/common.rs` | Přidaný paralelní `get_key_with_dns` a jeho použití pro serverový HTTP proxy požadavek. U vlastního serveru bez vyplněného Key musí i tato autentizace použít stejný ověřený DNS klíč. Původní `get_key` zůstává pro ostatní volání. |
| klient: `src/client.rs` | Připojení na `ID@server` doplňuje chybějící veřejný Key; vlastní spojení s odpovídajícím PSK přechází do autentizovaného relay tunelu. Health-check používá DNS Key stejným způsobem. Přímá IP a cizí server nedostávají vlastní PSK. |
| klient: `src/ui_session_interface.rs` | Před spuštěním relace vybírá DNS Key pouze pro vlastní rendezvous. Přímé adresy a `ID@jinýserver` zachovávají původní výběr, aby nastavení vlastního serveru neblokovalo nezávislé cíle. |
| klient: `src/rendezvous_mediator.rs` | Nakonfigurovaný soukromý hostitel používá nový řídicí kanál; bez soukromé konfigurace pokračuje původní registrace. TCP/WebRTC signalizace používá ověřený DNS Key, pokud nebyl zadán ručně. Výchozí metadata nesoukromých spojení nemají kontext pozvánky. |
| klient: `src/server.rs` | Volitelný kontext spojení předává identitu aliasu do podpisu handshake. Soukromá spojení vyžadují šifrovaný handshake. Globální ID zařízení se nepřepisuje; běžné spojení používá původní ID. Relay požadavek podporuje DNS Key. |
| klient: `src/server/connection.rs` | Přenesení stejného kontextu do přihlášení, přesná kontrola očekávané identity a ověření pozvánky nebo veřejného přístupu na skutečné ID těsně před autorizací. Již autorizované spojení pokračuje i po expiraci. |
| klient: `src/ipc.rs` | Jeden nový typ požadavku a jeho obsluha propojují UI se službou, která drží soukromé přihlašovací údaje. Před jeho odesláním zpětně kompatibilní konfigurační dotaz ověří podporu, aby stará místní služba neukončila IPC spojení na neznámém typu. Hodnota PSK není běžnou veřejnou konfigurační volbou. |
| klient: `src/flutter_ffi.rs` | Nový příkaz UI. Synchronní vstup na workeru odpovídá připnutému FRB 1.80.1; jeho lokální Tokio runtime obsluhuje pouze tento nový asynchronní IPC požadavek. Existující FFI volání ani backendový runtime se nepřestavují. |
| klient: `src/lib.rs` | Pouze zapojení nových modulů. |
| klient: `flutter/lib/desktop/pages/desktop_home_page.dart` | Připojení nového tlačítka pozvánky pod stávající údaje hostitele; pouze nativní příchozí režim. |
| klient: `flutter/lib/mobile/widgets/dialog.dart` | Připojení pole PSK, nastavení pozvánek a přepínače veřejného přístupu do společného dialogu ID/Relay Server včetně validace a uložení. Import/export nadále používá jen čtyři veřejná pole. |
| klient: `flutter/lib/web/bridge.dart` | Odpovídající metoda vrací pro web srozumitelně nepodporovanou nativní operaci. Web nezískává PSK ani novou implementaci soukromého transportu. |
| klient: `flutter/lib/common/widgets/peer_tab_page.dart` | Volba Last used vyžádá existující seznam posledních relací a uloží výběr stejnou dosavadní cestou. |
| klient: `flutter/lib/common/widgets/peers_view.dart` | Jedna nová větev řazení využívá pořadí posledních relací a obnovuje jej při jejich načtení. Dosavadní způsoby řazení zachovávají své větve. |
| klient: `src/lang/*.rs` | Pouze připojení nových textových klíčů a českých hodnot pro nové funkce; existující překlady se nemažou ani nepřepisují. |
| server: `src/main.rs`, `src/hbbr.rs`, `src/lib.rs` | Zapojení nových modulů a parametru přístupového klíče pro hbbs/hbbr. |
| server: `src/rendezvous_server.rs` | Na stávajícím TCP 21116 rozliší soukromý úvodní rámec od veřejných protobuf zpráv. Při aktivním PSK přijímá původní registrace jako cíle, propojuje je s autentizovanými PSK volajícími a veřejné volající směruje jen na platnou pozvánku nebo soukromý skutečný ID s povoleným přístupem. Online stav spojuje oba typy živých registrací. Bez PSK používá původní veřejný protokol. |
| server: `src/relay_server.rs` | Na stávajícím TCP 21117 rozliší soukromý transport od veřejných požadavků. Při aktivním PSK směruje veřejné požadavky před původním párováním do autorizované varianty; ta vyžaduje serverový grant a alespoň jednu ověřenou PSK stranu v určené roli. Zachovává stávající přenosový limit, blocklist a usage záznamy. Bez PSK pokračuje původní párování. |

DNS funkce má jeden vědomý dopad i bez soukromého režimu: vlastní server s prázdným Key nově vyžaduje úspěšné ověřené DNS zjištění klíče. Chyba se vrací uživateli; nevede k tichému nezabezpečenému pokračování. Explicitní Key a výchozí veřejná služba zachovávají svou cestu. Soukromá konfigurace s chybou čtení/dešifrování rovněž nespadne do anonymního režimu.

Soukromé řízení i relay sdílejí stávající TCP 21116/21117 s neupravenými veřejnými klienty; nejsou potřeba nové příchozí porty. Upravený klient pošle jednoznačný úvodní rámec v existujícím RustDesk rámování. Teprve poté proběhne podepsaný handshake serveru a šifrovaný transport, uvnitř kterého se ověřuje PSK. Samotná znalost rozlišovacího rámce přístup neumožní. Veřejný klient nadále používá svůj běžný protobuf požadavek. V chráněném režimu smí navázat spojení jen na platný alias pozvánky nebo na skutečné ID PSK zařízení, které výslovně povolilo veřejný přístup; registrace původního cíle sama neopravňuje k obecnému použití relay. Funkce je součástí upraveného OSS sestavení a nevyžaduje Server Pro ani změnu vlastního API.

Nové soukromé ovládání nejprve ověřuje podporu místní služby přes původní konfigurační IPC zprávu. Při starší nebo nedostupné službě zobrazí výzvu k instalaci/restartu a nesoukromé připojení nepřesměruje do soukromého transportu. Nakonfigurovaný soukromý režim při chybě služby selže bezpečně. Tato úprava neobchází původní Windows ověřování identity IPC procesů: při současném spuštění jiné přenosné binárky a staré instalace se může odpojovat i základní stavový kanál, proto GUI a služba musí používat stejnou aktualizovanou instalaci. Dotaz na stav nevolá hbbs. Oranžové upozornění HTTP API je samostatnou dosavadní logikou API adresy.

## Změny pouze pro sestavení a balení

| Existující soubory / oblast | Nutný důvod |
| --- | --- |
| `.cargo/config.toml` a `.gitignore` ve všech třech repozitářích | Výstupy Cargo a lokální artefakty směřují pod ignorované `artifacts`. Samostatné `hbb_common` nemá změnu runtime, protokolu, socketů ani Config API. |
| klient: `build.py` | Navazující čtení knihoven, balicí staging a publikované soubory odpovídají novému umístění. Generovaný Debian control vzniká ve stagingu místo přepisování zdrojové šablony. |
| klient: `flutter/linux/CMakeLists.txt`, `flutter/windows/CMakeLists.txt`, iOS/macOS Xcode projekty | Linkování a přibalení knihovny musí sledovat přesunutý Cargo target adresář. Instalované názvy knihoven a cesty aplikace zůstávají stejné. |
| klient: `entrypoint.sh`, `flutter/build_android.sh`, `flutter/build_fdroid.sh`, `flutter/build_ios.sh`, `libs/enigo/.vscode/launch.json` | Kopírování knihoven, debug symboly a vývojový launcher používají nové build cesty. |
| klient: MSI projekty a `res/rpm*.spec` | Výstupy MSI bin/obj a vstupy balíčků odpovídají `artifacts`; nejde o změnu běžící relace. |
| server: `ui/html/vite.config.js`, `ui/tauri.conf.json`, `ui/setup.nsi` | Generované webové UI, instalační staging a výsledný instalátor mají shodné nové cesty. |
| CI workflow soubory v klientovi a serveru | Build, cache, balení, podpisy a publikování musí číst přesunuté soubory. |
| README, překlady README, build dokumentace a `.gitattributes` | Návody ukazují platné cesty; nové Bash skripty a seznam balíků mají LF. |

Nové spouštěče a pomocníci buildů pracují s izolovanými kopiemi aktuálních pracovních stromů. Opravy skutečně zjištěné při sestavování jsou omezené na tyto pomocníky: výběr nativních nástrojů, LLVM, dlouhé cesty, bezpečné čištění a Debian oprávnění na DrvFS. Původní runtime se kvůli buildům nepřepisuje. Gitlinky `libs/hbb_common` v parent repozitářích nebyly plošně posunuty; nepřibylo nesouvisející období změn knihovny.

## Ověření a praktické meze

- DNS modul dříve prošel 5 testy. Předchozí přechod na sdílené porty a IPC kompatibilita prošly 37 Rust testy: 12 klientských, 23 knihovních serverových a 2 cílené hbbr regrese pro fragmentaci a lokální konzoli. Analýza změněného Dart widgetu skončila bez nálezu.
- Předchozí sestava hbbs/hbbr prošla loopback wire testem na sdílených portech: autentizovaná registrace, odmítnutí chybného PSK a podpisového klíče, standardní guest protobuf/WebSocket, podepsaný alias a obousměrný přenos. Anonymní skutečné ID a dvě veřejné poloviny byly odmítnuty. Zrušení aliasu i skutečná minutová expirace odmítly nové přijetí, zatímco přenos a heartbeat pokračovaly. Bez ACCESS_KEY prošla původní UDP registrace a obecný relay bez P-ID/PSK. Další soukromé porty neposlouchaly.
- Bash/PowerShell předkontroly a fixture testy ověřily omezení mazání, odmítnutí přesměrovaných cest a Debian oprávnění/UID/GID včetně zachování symlinků. Kontrola zdrojů nenahrazuje instalaci finálního GUI balíčku.
- Celé připojení z neupraveného veřejného GUI klienta včetně E2E přihlášení zatím nebylo provedeno. Jeho parser formátu `P-…@server?key=<raw base64>` byl porovnán s [oficiálním upstream zdrojem](https://github.com/rustdesk/rustdesk/blob/master/src/client.rs); protobuf/relay kompatibilitu pokryl smoke test.
- Předchozí sestava zahrnuje Windows instalační EXE, Linux klient pro Debian 13 amd64 i hbbs/hbbr pro oba systémy. Linuxový .deb prošel kontrolou metadat, ELF64 AMD64, vlastnictví a oprávnění obou archivů, shody zabalených binárek s hotovou aplikací a dostupnosti knihoven přes ldd. Výsledek je v `artifacts/logs/linux-client-package-verification.json`. Finální balení využilo již hotový bundle přes existující `build.py --package`; jeho SHA-256 se při balení nezměnilo. Instalace finálních GUI klientů tím ověřena není.
- První soukromá verze používá relay i pro vlastní spojení. Pozvánka dovoluje opakovaná přijetí do vypršení platnosti; expirace/odvolání blokuje nová přijetí, nikoli již přijaté relace. Web tuto nativní funkci nepodporuje.
- Nový Windows EXE, Debian 13 amd64 klient, Windows/Linux hbbs/hbbr a samostatné utils byly sestaveny v zachovaných pracovních kopiích pod artifacts. SDK, vcpkg a generované FFI se znovu nepřipravovaly; existující Cargo a Flutter cache zůstaly zachované. Manifest předchozího sestavení všech 11 výstupů s SHA-256 a kontrolami je `artifacts/logs/release-20261021-shared-ports.json`. Instalace aktualizované Windows služby ani celé původní GUI E2E tím ověřeny nejsou.

## Verze a přenosný test Windows

Klient zachovává výchozí upstream `1.5.1` a používá označení `1.5.1-a21`. Cargo.lock mění pouze vlastní dvě verze, nikoli závislosti. Windows instalační/aktualizační registry mají číselnou verzi bez přípony a textovou verzi s příponou. API upozornění už obsahoval upstream; skutečná HTTPS adresa místního API byla ověřena bez změny serveru.

Historický přenosný test s dočasně vypnutou původní službou potvrdil vlastní backend, zachované ID, odpověď hbbs přes UDP 21116 a vymizení resetů IPC. Původní služba i tray byly obnoveny; nová verze se během tohoto experimentu neinstalovala. Samostatný profil, nové ID ani změna IPC autentizace nejsou součástí opravy.

Výjimka z UAC pro vlastní přenosný backend byla na výslovný požadavek uživatele odstraněna. `src/ui_interface.rs::check_super_user_permission` znovu přesně odpovídá původnímu upstreamu; odemčení nadále vyžaduje původní ověření administrátora a případný PIN. Zelený stav Ready potvrdil uživatel. Přenosný experiment je historický; uživatel následně nainstaloval novou kopii. Původní UAC flow zůstává zachované.

## Online indikace soukromých zařízení

První oprava online indikace přidala živé autentizované registrace do stávajícího OnlineRequest na TCP 21115. Tato předchozí oprava prošla 25 serverovými a 12 klientskými testy i wire kontrolou životního cyklu kanálu. Aktuální smíšený režim kombinuje tyto živé řídicí kanály s živými původními klienty v PeerMap; soukromé ID se po uzavření řídicího kanálu nezobrazuje online jen kvůli starému záznamu. Nové porty nevznikají.

## Smíšený režim a jeho regresní plocha

Smíšený režim je implementovaný ve zdrojích: PSK klient se může připojit k registrovanému původnímu klientovi, dva klienti bez PSK se vzájemně spojit nesmějí. Původní klient smí na skutečné ID PSK zařízení jen při zapnutém přepínači **Allow clients without the private key to connect to this device** na cílovém PC; výchozí stav je OFF. P pozvánky fungují nezávisle. Zapnutí přijímá libovolného veřejného volajícího se správným veřejným Key, nikoli ověřený seznam známých PC; heslo/potvrzení cíle dál platí. Vypnutí odmítá nová a čekající přijetí, přijaté relace pokračují. Uživatel dříve potvrdil hostovské připojení; výsledky nového sestavení a celého smíšeného GUI spojení je nutné ověřit samostatně od výše uvedených starších výsledků.

Aktuálně prošlo 34 serverových testů, 14 klientských testů nad skutečnými feature moduly a jeden Flutter test oddělení soukromých údajů při importu/exportu. Finální wire test skončil úspěšně s exit 0; log je artifacts/logs/mixed-mode-wire-smoke-final.log. Potvrdil obousměrný přenos PSK klienta k původnímu cíli, veřejný přístup OFF/ON/OFF včetně validate RPC, společný online stav, odmítnutí převzetí připnutého klíče, stock-to-stock spojení a dvou anonymních relay polovin, P expiraci/odvolání se zachováním přijaté relace i původní režim bez ACCESS_KEY. Celé GUI E2E spojení tím ověřeno není.

Kontrolní manifest finálního vydání je artifacts/logs/release-20261021-mixed-access.json. Obsahuje SHA-256 výstupů a výsledky jednotlivých kontrol; celkový výsledek určuje pole passed. Audit balíčků nenahrazuje instalaci a GUI E2E test.

| Existující soubor / cesta | Nezbytná změna smíšeného režimu |
| --- | --- |
| klient: src/access_config.rs | Serverově vázaný souhlas s výchozím OFF, kompatibilní stará konfigurace a stav podpory místní služby. |
| klient: src/server_access.rs | Odeslání policy při autentizované registraci, rozlišení veřejné relace na skutečné ID a místní i serverové ověření těsně před přijetím. |
| klient: src/server/connection.rs | Dodatečná kontrola validate_admission před přípravou terminálového přihlášení a port-forwardingu odmítá nepovolený požadavek dříve, než tyto operace začnou; dosavadní závěrečný guard zůstává. |
| klient: flutter/lib/common/widgets/server_access_settings.dart | Samostatný přepínač, bezpečné vypnutí při změně serveru nebo odstranění PSK a neaktivní volba u starší služby. |
| server: src/server_access.rs | Oddělené granty pro PSK dvojice, původní cíl, P pozvánku a veřejný přístup k PSK hostiteli; tím se nepovolí stock-to-stock relay. |
| server: src/peer.rs | Připnutí veřejných klíčů a trvalé označení soukromého ID brání jeho převzetí původní registrací. |
| server: src/rendezvous_server.rs a src/relay_server.rs | Registrace/oznámení původního cíle, společný online stav a párování pouze rolí povolených konkrétním grantem. |

Při vypnutém ACCESS_KEY zůstává původní serverová registrace i obecné párování relay. Smíšený režim nemění UAC, Unlock PIN ani autentizaci místních IPC procesů; používá dosavadní ServerAccess zprávu bez nové FFI funkce. Clipboard import/export nadále přenáší pouze ID server, relay, API a veřejný Key. Plaintext, šifrovaný Private key ani jeho maska se neexportují; neznámá tajná pole v importu nemění uložený klíč ani stav jeho úpravy.
