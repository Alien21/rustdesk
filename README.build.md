# Sestavení upraveného RustDesku

Skripty v kořeni klientského repozitáře sestavují desktopového klienta i oba
serverové procesy. Předpokládané rozložení zdrojů:

~~~text
RustDesk/
  rustdesk/          # build_linux.sh, build_windows.sh, build_all.sh
  rustdesk-server/
  hbb_common/
~~~

Používá se aktuální obsah pracovních kopií, včetně necommitnutých a nových
neignorovaných souborů a obsahu inicializovaných submodulů. Umístění serveru
lze změnit proměnnou prostředí RUSTDESK_SERVER_DIR. Skripty nemění větev ani
neaktualizují zdrojové repozitáře z internetu.

## Výsledky

| Složka pod klientským repozitářem | Obsah |
| --- | --- |
| artifacts/publish/windows-x64/ | rustdesk-VERSION-install.exe, hbbs.exe, hbbr.exe, rustdesk-utils.exe |
| artifacts/publish/linux-x64/ | rustdesk-VERSION.deb, hbbs, hbbr, rustdesk-utils, rustdesk-server-{hbbs,hbbr,utils}_VERSION_amd64.deb |
| artifacts/build/PLATFORM/ | pracovní kopie zdrojů, bin/obj, Flutter build a balicí mezisoubory |
| artifacts/cache/PLATFORM/ | izolované SDK, Rust toolchainy, Cargo/Pub/vcpkg a dočasné soubory |

Windows klient je stejný typ samorozbalovacího instalačního EXE jako běžné
stažení RustDesku; obsahuje instalaci služby. Vlastní build nemá podpis
vydavatele oficiálního RustDesku. Linuxový klient je balíček pro Debian 13
amd64. Linuxové serverové binárky i balíčky vznikají v témže Debianu 13.
Server běží přímo jako hbbs/hbbr nebo přes existující systemd jednotky.
Serverové sestavení vytváří také samostatnou utilitu rustdesk-utils
(rustdesk-utils.exe na Windows); vzniká i s volbou --only server.

Pracovní kopie pod artifacts/build se při dalším sestavení vybrané komponenty
obnovují včetně jejich Rust target adresáře; tato komponenta se překládá znovu.
Ruční změny dělejte v původních zdrojích. Cache nástrojů, SDK a stažených
závislostí se zachovávají.
Všechny vygenerované projektové soubory vznikají uvnitř artifacts; původní
zdroje zůstávají čisté. Publikované výstupy se nenahrávají ani neinstalují na
běžící RustDesk server.

## Windows x64

Spusťte z Git Bashe, MSYS2 nebo Cygwinu v adresáři rustdesk:

~~~bash
bash build_windows.sh --check
bash build_windows.sh
~~~

Systémové předpoklady pro klienta:

- Git for Windows a Python 3.9+ s modulem venv. PYTHON může obsahovat cestu k python.exe.
- Visual Studio **2022** nebo Build Tools 2022 s Desktop development with C++,
  MSVC x64/x86, C++ CMake tools for Windows a Windows 10/11 SDK.
  Použitý Flutter 3.24.5 vybírá CMake generátor pro VS 2022.
- Oprávnění pro Windows symbolické odkazy: zapnutý Developer Mode nebo spuštění Git Bashe jako správce.
- LLVM s libclang.dll (upstream CI používá 15.0.6); LIBCLANG_PATH ukazuje na jeho bin.

Skript inicializuje vývojové prostředí Visual Studia sám. Globální SDK ani
PATH neupravuje. Rust, Flutter, vcpkg, CMake a Python balíčky si při prvním
sestavení stáhne do artifacts/cache/windows-x64. Samotný server nevyžaduje
Flutter, LLVM ani vcpkg; stále potřebuje C++ nástroje a Windows SDK.

### Přesný postup pro nový Windows počítač

1. Otevřete PowerShell. Nainstalujte Git a Python (případná oprávnění potvrďte):

~~~powershell
winget install --exact --id Git.Git --source winget
winget install --exact --id Python.Python.3.12 --source winget
~~~

2. Otevřete nový PowerShell v kořeni repozitáře rustdesk a nainstalujte
   Build Tools 2022. Následující příkazy stáhnou oficiální Microsoft bootstrapper,
   vyžádají administrátorské oprávnění a zakážou automatický restart:

~~~powershell
New-Item -ItemType Directory -Force artifacts/cache/setup | Out-Null
Invoke-WebRequest https://aka.ms/vs/17/release/vs_buildtools.exe -OutFile artifacts/cache/setup/vs_buildtools.exe
Start-Process -FilePath (Resolve-Path artifacts/cache/setup/vs_buildtools.exe) -Verb RunAs -Wait -ArgumentList '--quiet --wait --norestart --nocache --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --add Microsoft.VisualStudio.Component.VC.CMake.Project'
~~~

   Pokud instalátor vyžádá restart, dokončete jej před buildem. Alternativou
   je instalátor VS 2022 → Modify → Desktop development with C++, včetně
   MSVC x64/x86, C++ CMake tools for Windows a Windows 10/11 SDK.

3. Flutter pluginy potřebují symbolické odkazy. Buď otevřete Git Bash přes **Spustit jako správce**,
   nebo jednorázově zapněte Windows Developer Mode: v PowerShellu spusťte
   Start-Process ms-settings:developers a v otevřeném nastavení zapněte režim pro vývojáře.
   Předkontrola ověřuje skutečné vytvoření odkazu a testovací soubory odstraní.

4. Z [oficiálního LLVM 15.0.6](https://github.com/llvm/llvm-project/releases/tag/llvmorg-15.0.6)
   stáhněte LLVM-15.0.6-win64.exe, spusťte jej a ponechte cílový adresář
   C:\Program Files\LLVM. Přidání LLVM do systémového PATH není potřeba.
   Je možné i přenosné rozbalení do artifacts; potom nastavte LIBCLANG_PATH.

5. Otevřete **Git Bash** v adresáři rustdesk (případně Cygwin s dostupnými
   příkazy powershell.exe a cygpath). Ověřte a spusťte sestavení:

~~~bash
export LIBCLANG_PATH='C:/Program Files/LLVM/bin'
python --version
git --version
bash build_windows.sh --check
bash build_windows.sh
~~~

   Pokud používáte vlastní Python mimo PATH, nastavte před spuštěním například
   export PYTHON='C:/Tools/Python312/python.exe'. Visual Studio ani LLVM není
   nutné přidávat do uživatelského PATH.

### Už připravené nástroje na tomto počítači

Pro aktuální pracovní kopii byly Build Tools 2022 registrované z
C:/Git/RustDesk/artifacts/tools/vs2022 a LLVM je přenosné. V Git Bashi spuštěném
jako správce lze použít existující Python a LLVM takto:

~~~bash
cd /c/Git/RustDesk/rustdesk
export LIBCLANG_PATH='C:/Git/RustDesk/artifacts/tools/llvm-15.0.6/bin'
export PYTHON='C:/Users/Alien21/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
bash build_windows.sh --check
bash build_windows.sh
~~~

PYTHON zde ukazuje na aktuální přenosný runtime vývojového prostředí.
Pro samostatnou instalaci na jiném PC použijte standardní Python podle
postupu výše. Proměnné se nastavují jen pro právě otevřený terminál.

## Debian 13 / x86_64

Spusťte přímo v Debianu 13:

~~~bash
bash build_linux.sh --check
bash build_linux.sh
~~~

Předkontrola vypíše přesný apt-get příkaz pro chybějící systémové balíky.
Úplný seznam je v scripts/build/debian-packages.txt. Skript sám nespouští
sudo ani nemění systémové balíky. Rust/Flutter/CMake/vcpkg se připravují
izolovaně pod artifacts/cache/linux-x64.
Balicí kroky používají fakeroot a normalizují POSIX oprávnění i na Windows
NTFS disku ve WSL; změna mount nastavení není nutná. Serverové .deb mají
závislosti na skutečně použitých systémových knihovnách.

Z Windows může stejný příkaz použít **WSL s Debianem 13**:

~~~bash
RUSTDESK_WSL_DISTRO=Debian bash build_linux.sh --check
RUSTDESK_WSL_DISTRO=Debian bash build_linux.sh
~~~

Výchozí název distribuce je Debian. WSL musí být nainstalované a distribuce
připravená před sestavením. Cygwin nebo Git Bash zde zajišťuje spuštění;
Linuxové nástroje běží uvnitř Debianu. Docker se nepoužívá.

### Instalace systémových balíků v Debianu

V kořeni klientského repozitáře spusťte:

~~~bash
sudo apt-get update
grep -vE '^[[:space:]]*(#|$)' scripts/build/debian-packages.txt | xargs sudo apt-get install -y --no-install-recommends
bash build_linux.sh --check
bash build_linux.sh
~~~

Tím se instalují build závislosti pro klienta i server. Při samotném serverovém
buildu stačí balíky ze sekce common; --check --only server vypíše jejich chybějící
podmnožinu. Pokud jste v Debianu přihlášeni jako root, vynechte sudo.

### První příprava WSL na Windows

V PowerShellu **jako administrátor** spusťte:

~~~powershell
wsl --install --web-download --no-distribution
~~~

Pokud příkaz vyžádá restart, restartujte Windows a pokračujte dalším příkazem.
Z kořene klientského repozitáře poté:

~~~powershell
wsl --install --distribution Debian --web-download --no-launch --location "$PWD/artifacts/wsl/Debian"
wsl --distribution Debian --user root --exec cat /etc/os-release
~~~

Výstup musí obsahovat VERSION_ID="13". Spusťte Debian z nabídky Start a dokončete
případné vytvoření uživatele. V Debianu přejděte do zdrojů, například
cd /mnt/c/Git/RustDesk/rustdesk, a nainstalujte balíky příkazy výše.
Pak můžete build spouštět i z Windows Bashe. Distribuce WSL je uložena pod
artifacts/wsl/Debian; pokud už funkční Debian 13 ve WSL máte, použijte jej
bez další instalace a nastavte RUSTDESK_WSL_DISTRO na jeho název.

## Výběr sestavení

~~~bash
bash build_windows.sh --only client
bash build_linux.sh --only server
bash build_all.sh --check
bash build_all.sh
bash build_all.sh --platform linux --only client
~~~

build_all.sh znamená Windows x64 + Debian 13 amd64. Nejprve zkontroluje obě
prostředí a až potom začne sestavovat. Oba cíle lze takto sestavit na Windows
s připraveným WSL. Nativní Linux sám Windows Flutter klienta nesestaví;
použijte --platform linux nebo Windows build spusťte na Windows.
macOS, mobilní klienti a další architektury do tohoto „all“ nepatří.

## Připnuté nástroje

Klient používá verze z existujícího CI: Rust 1.75.0, Flutter 3.24.5,
Flutter 3.22.3 pro generování bridge, flutter_rust_bridge_codegen 1.80.1,
cargo-expand 1.0.95, vcpkg 9e593bb18ea69cc5095e012465dcd675a822ed0d a
CMake 4.3.0. Server používá Rust 1.99.1, protože jeho nynější Cargo.lock
vyžaduje novější Rust než klient. Cargo buildy respektují --locked.
SDK patch a dočasná změna extended_text pro bridge probíhají jen v izolované
kopii, podle CI. Klientské buildy mají hwcodec; Windows navíc vram, Linux
unix-file-copy-paste. Funkce drm/drm-wake se nezapínají.

Windows přebírá také upravený Flutter engine z upstream CI. Jeho release
URL main není neměnná; stažený archiv zůstává v cache a jeho SHA-256 je
zaznamenáno v markeru izolovaného Flutter SDK. Reprodukci proto provádějte
se stejnou cache, dokud upstream neposkytne neměnný release.

Kontrola regrese: změněny jsou jen nové build spouštěče/pomocníci a pravidla
LF pro Bash a seznam Debian balíků v .gitattributes. README.md odkazuje na tento návod. Běžící aplikace, stávající build.py a CI workflow
nemění chování; nové skripty je používají až při výslovném spuštění.

Instalační parametry vycházejí z [Microsoft Build Tools](https://learn.microsoft.com/en-us/visualstudio/install/use-command-line-parameters-to-install-visual-studio?view=visualstudio) a [dokumentace WSL](https://learn.microsoft.com/en-us/windows/wsl/install).
