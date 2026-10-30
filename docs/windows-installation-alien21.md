# Instalace klienta Windows

Vlastní klient se instaluje běžným způsobem, aby GUI a místní služba používaly stejnou verzi. Kontrola identity IPC, původní ověření administrátora Windows při odemykání nastavení a případný Unlock PIN zůstávají zachované. Souběžný provoz rozdílných instalovaných a přenosných verzí se kvůli testování neobchází.

## Instalační soubor

Po sestavení použijte instalátor `artifacts/rustdesk/publish/windows-x64/rustdesk-1.5.1-a21-install.exe` v hlavním workspace `C:\Git\RustDesk`. Postup sestavení uvádí [README.build.md](../README.build.md).

## Běžná instalace nové verze

1. Zavřete otevřená okna RustDesku. Původní instalaci předem neodinstalovávejte.
2. Spusťte nové `rustdesk-1.5.1-a21-install.exe`, použijte běžnou volbu instalace a potvrďte požadavek Windows na oprávnění správce. Instalace aktualizuje také službu; pouhé přenosné spuštění EXE to neudělá.
3. Spouštějte klienta z aktualizované instalace, například z nabídky Start, aby GUI i služba používaly stejnou kopii programu. Ověřte své ID, zelený stav Ready, jednorázové heslo a možnost odemknout Network / Security Settings s původním ověřením oprávnění. Po odemčení musí jít otevřít také řádek ID/Relay Server.
4. Dokud hbbs/hbbr zůstávají původní, ponechte Private key prázdné. ID server může zůstat `rustdesk.home.alien21.com`, relay prázdné a veřejný Key původní. Pokud používáte místní API, jeho ověřená adresa je `https://rustdesk.home.alien21.com` bez `/api` a bez portu.

Po aktualizaci obou serverů hbbs/hbbr lze do **Private key** zadat jejich ACCESS_KEY. Původní PC bez PSK mohou dál sloužit jako cíle pro PSK klienta; dvě původní PC se přes chráněný relay vzájemně spojit nesmějí. Na každém aktualizovaném cílovém PC je **Allow clients without the private key to connect to this device** výchozím stavem vypnuté. Zapněte jej jen pro přístup původních klientů na skutečné ID tohoto PC; P pozvánky fungují samostatně a heslo/potvrzení dál platí. Starší služba nový přepínač nepovolí, proto aktualizujte GUI i službu společně. Podrobnosti uvádí [nasazení a smíšený režim](deployment-alien21.md).

Ikony importu/exportu v ID/Relay dialogu přenášejí pouze ID server, relay, API a veřejný Key. Private key se nepřenáší ani nepřepisuje importem; nové souhlasy a platnost pozvánek se nastavují zvlášť. Původní ověření Windows UAC, Unlock PIN a shoda IPC procesů zůstávají zachované.

Zelený stav Ready byl ověřen při přenosném testu. Odemčení nastavení a běžná instalace finální sestavy zatím ověřeny nejsou; kontrola balíčků tento test nenahrazuje.
