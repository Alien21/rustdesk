# Rozsah změn develop-alien21

Závěrečná kontrola zdrojů k 21. 10. 2026 zahrnuje DNS veřejného klíče, soukromý přístup a pozvánky, řazení podle posledního použití, přesun výstupů a nové build skripty. Kontrola nevyžadovala další změny runtime ani nesouvisející refaktor.

## Existující runtime soubory a cesty

Nová logika je soustředěna v samostatných modulech `dns_key.rs`, `access_config.rs`, `access_transport.rs` a `server_access.rs` a v nových UI widgetech. V existujících souborech zůstávají následující nutné zásahy:

| Repozitář / existující soubor | Změněná cesta a nutný důvod |
| --- | --- |
| klient: `src/common.rs` | Přidaný paralelní `get_key_with_dns` a jeho použití pro serverový HTTP proxy požadavek. U vlastního serveru bez vyplněného Key musí i tato autentizace použít stejný ověřený DNS klíč. Původní `get_key` zůstává pro ostatní volání. |
| klient: `src/client.rs` | Připojení na `ID@server` doplňuje chybějící veřejný Key; vlastní spojení s odpovídajícím PSK přechází do autentizovaného relay tunelu. Health-check používá DNS Key stejným způsobem. Přímá IP a cizí server nedostávají vlastní PSK. |
| klient: `src/ui_session_interface.rs` | Před spuštěním relace vybírá DNS Key pouze pro vlastní rendezvous. Přímé adresy a `ID@jinýserver` zachovávají původní výběr, aby nastavení vlastního serveru neblokovalo nezávislé cíle. |
| klient: `src/rendezvous_mediator.rs` | Nakonfigurovaný soukromý hostitel používá nový řídicí kanál; bez soukromé konfigurace pokračuje původní registrace. TCP/WebRTC signalizace používá ověřený DNS Key, pokud nebyl zadán ručně. Výchozí metadata nesoukromých spojení nemají kontext pozvánky. |
| klient: `src/server.rs` | Volitelný kontext spojení předává identitu aliasu do podpisu handshake. Soukromá spojení vyžadují šifrovaný handshake. Globální ID zařízení se nepřepisuje; běžné spojení používá původní ID. Relay požadavek podporuje DNS Key. |
| klient: `src/server/connection.rs` | Přenesení stejného kontextu do přihlášení, přesná kontrola očekávaného aliasu a ověření pozvánky těsně před autorizací. Již autorizované spojení pokračuje i po expiraci. |
| klient: `src/ipc.rs` | Jeden nový typ požadavku a jeho obsluha propojují UI se službou, která drží soukromé přihlašovací údaje. Hodnota PSK není běžnou veřejnou konfigurační volbou. |
| klient: `src/flutter_ffi.rs` | Nový příkaz UI. Synchronní vstup na workeru odpovídá připnutému FRB 1.80.1; jeho lokální Tokio runtime obsluhuje pouze tento nový asynchronní IPC požadavek. Existující FFI volání ani backendový runtime se nepřestavují. |
| klient: `src/lib.rs` | Pouze zapojení nových modulů. |
| klient: `flutter/lib/desktop/pages/desktop_home_page.dart` | Připojení nového tlačítka pozvánky pod stávající údaje hostitele; pouze nativní příchozí režim. |
| klient: `flutter/lib/mobile/widgets/dialog.dart` | Připojení nového pole PSK a nastavení pozvánek do společného dialogu ID/Relay Server včetně validace a uložení. |
| klient: `flutter/lib/web/bridge.dart` | Odpovídající metoda vrací pro web srozumitelně nepodporovanou nativní operaci. Web nezískává PSK ani novou implementaci soukromého transportu. |
| klient: `flutter/lib/common/widgets/peer_tab_page.dart` | Volba Last used vyžádá existující seznam posledních relací a uloží výběr stejnou dosavadní cestou. |
| klient: `flutter/lib/common/widgets/peers_view.dart` | Jedna nová větev řazení využívá pořadí posledních relací a obnovuje jej při jejich načtení. Dosavadní způsoby řazení zachovávají své větve. |
| klient: `src/lang/*.rs` | Pouze připojení nových textových klíčů a českých hodnot pro nové funkce; existující překlady se nemažou ani nepřepisují. |
| server: `src/main.rs`, `src/hbbr.rs`, `src/lib.rs` | Zapojení nových modulů a parametru přístupového klíče pro hbbs/hbbr. |
| server: `src/rendezvous_server.rs` | Při aktivním PSK otevře autentizované řízení, odmítá starou veřejnou registraci a veřejným hostům vystavuje pouze platnou pozvánku. Bez PSK používá původní veřejný protokol. |
| server: `src/relay_server.rs` | Při aktivním PSK směruje veřejné požadavky před původním párováním do autorizované varianty; ta vyžaduje ověřeného hostitele. Zachovává stávající přenosový limit, blocklist a usage záznamy. Bez PSK pokračuje původní párování. |

DNS funkce má jeden vědomý dopad i bez soukromého režimu: vlastní server s prázdným Key nově vyžaduje úspěšné ověřené DNS zjištění klíče. Chyba se vrací uživateli; nevede k tichému nezabezpečenému pokračování. Explicitní Key a výchozí veřejná služba zachovávají svou cestu. Soukromá konfigurace s chybou čtení/dešifrování rovněž nespadne do anonymního režimu.

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

- Přesný zdroj DNS modulu prošel 5 testy; nativní access/transport/config moduly 8 testy se skutečně připnutým `hbb_common`. Serverové protokolové testy prošly 11 testy.
- Skutečné procesy hbbs/hbbr prošly samostatným loopback smoke testem: registrace s PSK, vytvoření aliasu, standardní guest protobuf, ověření alias certifikátu, obousměrný přenos, odmítnutí anonymního skutečného ID a dvou veřejných polovin. Zrušení aliasu novou registrací nezastavilo již spojený přenos.
- Bash/PowerShell předkontroly a fixture testy ověřily omezení mazání, odmítnutí přesměrovaných cest a Debian oprávnění/UID/GID včetně zachování symlinků. Kontrola zdrojů nenahrazuje instalaci finálního GUI balíčku.
- Celé připojení z neupraveného veřejného GUI klienta včetně E2E přihlášení zatím nebylo provedeno. Jeho parser formátu `P-…@server?key=<raw base64>` byl porovnán s [oficiálním upstream zdrojem](https://github.com/rustdesk/rustdesk/blob/master/src/client.rs); protobuf/relay kompatibilitu pokryl smoke test.
- Windows instalační EXE, Linux klient pro Debian 13 amd64 i hbbs/hbbr pro oba systémy jsou sestavené. Linuxový .deb prošel kontrolou metadat, ELF64 AMD64, vlastnictví a oprávnění obou archivů, shody zabalených binárek s hotovou aplikací a dostupnosti knihoven přes ldd. Výsledek je v `artifacts/logs/linux-client-package-verification.json`. Finální balení využilo již hotový bundle přes existující `build.py --package`; jeho SHA-256 se při balení nezměnilo. Instalace finálních GUI klientů tím ověřena není.
- První soukromá verze používá relay i pro vlastní spojení. Pozvánka dovoluje opakovaná přijetí do vypršení platnosti; expirace/odvolání blokuje nová přijetí, nikoli již přijaté relace. Web tuto nativní funkci nepodporuje.
