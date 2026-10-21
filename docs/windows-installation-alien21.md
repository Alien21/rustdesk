# Instalace klienta Windows a návrat k originálu

Vlastní klient se instaluje běžným způsobem, aby GUI a místní služba používaly stejnou verzi. Kontrola identity IPC, původní ověření administrátora Windows při odemykání nastavení a případný Unlock PIN zůstávají zachované. Souběžný provoz rozdílných instalovaných a přenosných verzí se kvůli testování neobchází.

## Připravené soubory na tomto počítači

- Nový instalátor: `artifacts/publish/windows-x64/rustdesk-1.5.1-a21-install.exe`.
- Původní oficiální instalátor: `artifacts/rollback/before-a21-install-20261021/rustdesk-1.5.0-x86_64.exe`.
- Záloha dosavadního stavu: `artifacts/rollback/before-a21-install-20261021/snapshot`.
- Výsledek zálohy: `artifacts/rollback/before-a21-install-20261021/backup-result.json`.

Oficiální instalátor pochází z [vydání RustDesk 1.5.0](https://github.com/rustdesk/rustdesk/releases/tag/1.5.0). Jeho SHA-256 je `8555777215510d83d2d61c9dc984e4fcc838bd7e79f9d18a42585431f5e8bb47`; souhlasí s údajem vydavatele a ověření Authenticode má stav Valid (PURSLANE).

Záloha obsahuje přesnou kopii původního adresáře `C:\Program Files\RustDesk` (verze EXE `1.5.0+68`), uživatelskou konfiguraci v `%APPDATA%\RustDesk\config`, konfiguraci služby v `C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config` a export příslušných registračních údajů. U všech 441 zkopírovaných souborů byla ověřena shoda SHA-256 se zdrojem. Seznam a původní cesty jsou v `snapshot/files.json` a `snapshot/locations.json`.

Záloha obsahuje identitu a přihlašovací údaje klienta. Přístup k jejímu adresáři je omezen na tohoto uživatele, správce a SYSTEM; nesdílejte ji. Programové soubory a konfigurace byly kopírovány se zastavenou původní službou a ukončenými procesy. Služba i tray byly potom obnoveny. Nová verze se při přípravě zálohy neinstalovala.

## Běžná instalace nové verze

1. Zavřete otevřená okna RustDesku. Původní instalaci předem neodinstalovávejte.
2. Spusťte nové `rustdesk-1.5.1-a21-install.exe`, použijte běžnou volbu instalace a potvrďte požadavek Windows na oprávnění správce. Instalace aktualizuje také službu; pouhé přenosné spuštění EXE to neudělá.
3. Spouštějte klienta z aktualizované instalace. Ověřte své ID, zelený stav Ready, jednorázové heslo a možnost odemknout Network / Security Settings s původním ověřením oprávnění. Po odemčení musí jít otevřít také řádek ID/Relay Server.
4. Dokud hbbs/hbbr zůstávají původní, ponechte Private key prázdné. ID server může zůstat `rustdesk.home.alien21.com`, relay prázdné a veřejný Key původní. Pokud používáte místní API, jeho ověřená adresa je `https://rustdesk.home.alien21.com` bez `/api` a bez portu.

Zelený stav Ready byl ověřen při přenosném testu. Odemčení nastavení a běžná instalace finální sestavy zatím ověřeny nejsou; kontrola balíčků tento test nenahrazuje.

## Návrat k původní verzi

1. Ukončete testovaného klienta a spusťte uložený oficiální `rustdesk-1.5.0-x86_64.exe`. Proveďte běžnou instalaci s oprávněním správce.
2. Pokud starší instalátor instalaci přes novější verzi nenabídne nebo odmítne, odinstalujte vlastní verzi přes Windows a potom nainstalujte originál. Pokud se odinstalátor ptá na odstranění nastavení, ponechte je zachované. Před případným mazáním konfigurace je k dispozici výše uvedená záloha.
3. Ověřte stav služby, původní ID a nastavení serveru. Pokud se konfigurace změnila nebo ztratila, lze ji obnovit ze zálohy `snapshot/user-config` a `snapshot/localservice-config` do původních cest uvedených výše. Při obnovování musí být ukončené všechny procesy RustDesku a zastavená služba `RustDesk`; před přepsáním si uchovejte také stav vzniklý během testování. Po obnově spusťte službu a původního klienta. Exporty registru ani programový adresář nepřepisujte při běžícím klientovi; běžný návrat nejprve řešte oficiálním instalátorem.

Stejné ID a uložená hesla závisejí na zachování správné uživatelské i servisní konfigurace. Proto je uložená záloha důležitá i tehdy, když samotné přeinstalování proběhne bez chyb. Celý návrat přes instalátor zatím nebyl na tomto počítači proveden.
