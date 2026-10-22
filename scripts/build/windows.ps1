[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ClientSource,
    [Parameter(Mandatory = $true)][string]$ServerSource,
    [string]$ApiSource,
    [string]$ApiWebSource,
    [string]$ArtifactsRoot = $env:RUSTDESK_ARTIFACTS_DIR,
    [switch]$Check,
    [ValidateSet('client', 'server', 'api', 'apiweb', 'all')][string]$Only = 'all'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$NeedsClient = $Only -in @('client', 'all')
$NeedsServer = $Only -in @('server', 'all')
$NeedsApiWeb = $Only -in @('api', 'apiweb', 'all')
$ClientRust = '1.75.0'
$ServerRust = '1.99.1'
$VcpkgCommit = '9e593bb18ea69cc5095e012465dcd675a822ed0d'

function Invoke-Checked {
    param([string]$Executable, [string[]]$Arguments = @())
    & $Executable @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "$Executable failed with exit code $LASTEXITCODE." }
}
function Find-Python {
    $candidates = @()
    if ($env:PYTHON) { $candidates += $env:PYTHON }
    $candidates += @('python3.exe', 'python.exe', 'py.exe')
    foreach ($candidate in $candidates) {
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if (-not $command) { continue }
        $prefix = @()
        if ($command.Name -eq 'py.exe') { $prefix = @('-3') }
        try {
            $executable = & $command.Source @prefix -c "import sys; assert sys.platform == 'win32' and sys.version_info >= (3,9); print(sys.executable)" 2>$null
            if ($LASTEXITCODE -eq 0 -and $executable) { return ($executable | Select-Object -Last 1).Trim() }
        } catch { }
    }
    throw 'Native Windows Python 3.9 or newer is required. Install Python or set PYTHON to its python.exe.'
}
function Assert-SymlinkSupport {
    $probeDirectory = Assert-ArtifactPath (Join-Path $Artifacts 'cache\windows-x64\preflight')
    New-Item -ItemType Directory -Path $probeDirectory -Force | Out-Null
    $probe = @'
import os, sys, tempfile
from pathlib import Path
with tempfile.TemporaryDirectory(prefix='symlink-', dir=sys.argv[1]) as directory:
    target = Path(directory) / 'target'
    target.mkdir()
    os.symlink(target, Path(directory) / 'link', target_is_directory=True)
'@
    & $Python -c $probe $probeDirectory 2>$null | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Flutter requires directory symlinks. Enable Windows Developer Mode or run the build with an account that can create symbolic links.' }
}
function Require-File {
    param([string]$Path, [string]$Explanation)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw $Explanation }
}
function Assert-ArtifactPath {
    param([string]$Path)
    $absolute = [IO.Path]::GetFullPath($Path)
    $artifactRoot = [IO.Path]::GetFullPath($ArtifactsRoot).TrimEnd('\')
    $prefix = [IO.Path]::GetFullPath($Artifacts).TrimEnd('\') + '\'
    if (-not $absolute.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Build path is outside artifacts: $absolute" }
    # A redirected parent could otherwise move a lexically safe deletion outside artifacts.
    $ancestor = $absolute
    while ($ancestor.Length -ge $artifactRoot.Length) {
        if (Test-Path -LiteralPath $ancestor) {
            $item = Get-Item -LiteralPath $ancestor -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Refusing redirected build path: $ancestor" }
        }
        if ($ancestor.Equals($artifactRoot, [StringComparison]::OrdinalIgnoreCase)) { break }
        $ancestor = [IO.Path]::GetDirectoryName($ancestor)
    }
    return $absolute
}
function Remove-ArtifactDirectory {
    param([string]$Path)
    $absolute = Assert-ArtifactPath $Path
    if (Test-Path -LiteralPath $absolute) {
        if ((Get-Item -LiteralPath $absolute -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Refusing redirected build directory: $absolute" }
        Remove-Item -LiteralPath $absolute -Recurse -Force
    }
}
function Import-VisualStudio {
    $programFilesX86 = [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFilesX86)
    $vswhere = Join-Path $programFilesX86 'Microsoft Visual Studio\Installer\vswhere.exe'
    Require-File $vswhere 'Visual Studio Build Tools with Desktop development with C++ and a Windows 10/11 SDK are required.'
    $requirements = @('Microsoft.VisualStudio.Component.VC.Tools.x86.x64')
    if ($NeedsClient) { $requirements += 'Microsoft.VisualStudio.Component.VC.CMake.Project' }
    $arguments = @('-latest', '-products', '*', '-requires') + $requirements + @('-property', 'installationPath')
    # Flutter 3.24.5 selects the Visual Studio 2022 CMake generator.
    if ($NeedsClient) { $arguments += @('-version', '[17.0,18.0)') }
    $installation = & $vswhere @arguments
    if ($LASTEXITCODE -ne 0 -or -not $installation) { throw 'Install Visual Studio 2022 Build Tools: Desktop development with C++, MSVC x64/x86 tools, and Windows 10/11 SDK. No system components are installed by this script.' }
    $installation = ($installation | Select-Object -First 1).Trim()
    $developerCommand = Join-Path $installation 'Common7\Tools\VsDevCmd.bat'
    Require-File $developerCommand "Missing Visual Studio developer command: $developerCommand"
    $command = '""{0}" -no_logo -arch=x64 -host_arch=x64 && set"' -f $developerCommand
    $commandInterpreter = Join-Path ([Environment]::SystemDirectory) 'cmd.exe'
    $variables = & $commandInterpreter /d /s /c $command
    if ($LASTEXITCODE -ne 0) { throw 'Visual Studio developer environment initialization failed.' }
    foreach ($line in $variables) {
        if ($line -match '^([^=]+)=(.*)$') { [Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process') }
    }
    if (-not $env:VCToolsInstallDir -or -not $env:WindowsSdkDir -or -not $env:WindowsSDKVersion) { throw 'The Visual Studio C++ tools and Windows SDK developer environment are incomplete.' }
    Require-File (Join-Path $env:VCToolsInstallDir 'include\vector') 'The MSVC C++ standard library headers are missing.'
    Require-File (Join-Path $env:VCToolsInstallDir 'lib\x64\libcmt.lib') 'The MSVC x64 runtime libraries are missing.'
    $sdkVersion = $env:WindowsSDKVersion.TrimEnd('\')
    Require-File (Join-Path $env:WindowsSdkDir "Include\$sdkVersion\um\Windows.h") 'The Windows SDK headers are missing.'
    Require-File (Join-Path $env:WindowsSdkDir "Include\$sdkVersion\ucrt\stdio.h") 'The Windows SDK Universal CRT headers are missing.'
    Require-File (Join-Path $env:WindowsSdkDir "Lib\$sdkVersion\um\x64\kernel32.lib") 'The Windows SDK x64 libraries are missing.'
    Require-File (Join-Path $env:WindowsSdkDir "Lib\$sdkVersion\ucrt\x64\ucrt.lib") 'The Windows SDK Universal CRT libraries are missing.'
    Write-Host "Visual Studio: $installation"
}
function Find-Libclang {
    $candidates = @()
    if ($env:LIBCLANG_PATH) { $candidates += $env:LIBCLANG_PATH }
    $candidates += @((Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)) 'LLVM\bin'))
    if ($env:VSINSTALLDIR) { $candidates += (Join-Path $env:VSINSTALLDIR 'VC\Tools\Llvm\x64\bin') }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $candidate 'libclang.dll') -PathType Leaf) { return $candidate }
    }
    throw 'The client requires LLVM/libclang 15.0.6. Install it separately and set LIBCLANG_PATH to the directory containing libclang.dll. The build does not run a system-wide LLVM installer.'
}
function Get-Download {
    param([string]$Uri, [string]$Name)
    $path = Join-Path $Downloads $Name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $partial = "$path.part"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Write-Host "Downloading $Name"
        Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $partial
        Move-Item -LiteralPath $partial -Destination $path -Force
    }
    return $path
}
function Get-ZipTool {
    param([string]$Uri, [string]$Name, [string]$Directory, [string]$Expected)
    if (-not (Test-Path -LiteralPath (Join-Path $Directory $Expected) -PathType Leaf)) {
        $archive = Get-Download $Uri $Name
        Remove-ArtifactDirectory $Directory
        New-Item -ItemType Directory -Path $Directory -Force | Out-Null
        Expand-Archive -LiteralPath $archive -DestinationPath $Directory -Force
        Require-File (Join-Path $Directory $Expected) "Downloaded tool is incomplete: $Expected"
    }
    return (Join-Path $Directory $Expected)
}
function Initialize-GitConfiguration {
    $configurationPath = Join-Path $Cache 'gitconfig'
    $candidates = @()
    if ($env:GIT_CONFIG_GLOBAL) { $candidates += $env:GIT_CONFIG_GLOBAL }
    else {
        if ($env:XDG_CONFIG_HOME) { $candidates += (Join-Path $env:XDG_CONFIG_HOME 'git\config') }
        else { $candidates += (Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)) '.config\git\config') }
        $candidates += (Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)) '.gitconfig')
    }
    $configuration = ''
    foreach ($candidate in $candidates) {
        if ((Test-Path -LiteralPath $candidate -PathType Leaf) -and [IO.Path]::GetFullPath($candidate) -ne [IO.Path]::GetFullPath($configurationPath)) {
            $includePath = [IO.Path]::GetFullPath($candidate).Replace('\', '/').Replace('"', '\"')
            $configuration += "[include]`n`tpath = " + [char]34 + $includePath + [char]34 + "`n"
        }
    }
    $configuration += "[core]`n`tlongpaths = true`n"
    [IO.File]::WriteAllText($configurationPath, $configuration, (New-Object Text.UTF8Encoding($false)))
    $env:GIT_CONFIG_GLOBAL = $configurationPath
    $env:CARGO_NET_GIT_FETCH_WITH_CLI = 'true'
}
function Initialize-Rust {
    $rustup = Join-Path $env:CARGO_HOME 'bin\rustup.exe'
    if (-not (Test-Path -LiteralPath $rustup -PathType Leaf)) {
        $installer = Get-Download 'https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe' 'rustup-init.exe'
        Invoke-Checked $installer @('-y', '--no-modify-path', '--profile', 'minimal', '--default-toolchain', 'none', '--default-host', 'x86_64-pc-windows-msvc')
    }
    $env:PATH = (Join-Path $env:CARGO_HOME 'bin') + ';' + $env:PATH
    $toolchains = @()
    if ($NeedsClient) { $toolchains += $ClientRust }
    if ($NeedsServer) { $toolchains += $ServerRust }
    foreach ($toolchain in $toolchains) {
        $installArguments = @('toolchain', 'install', "$toolchain-x86_64-pc-windows-msvc", '--profile', 'minimal', '--no-self-update')
        if ($toolchain -eq $ClientRust) { $installArguments += @('--component', 'rustfmt') }
        Invoke-Checked $rustup $installArguments
    }
    return $rustup
}
function Initialize-ClientTools {
    $cmake = Get-ZipTool 'https://github.com/Kitware/CMake/releases/download/v4.3.0/cmake-4.3.0-windows-x86_64.zip' 'cmake-4.3.0-windows-x86_64.zip' (Join-Path $Cache 'cmake-4.3.0') 'cmake-4.3.0-windows-x86_64\bin\cmake.exe'
    $env:PATH = (Split-Path $cmake) + ';' + $env:PATH
    $flutterBuild = Get-ZipTool 'https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.24.5-stable.zip' 'flutter_windows_3.24.5-stable.zip' (Join-Path $Cache 'flutter-3.24.5') 'flutter\bin\flutter.bat'
    $flutterCodegen = Get-ZipTool 'https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.22.3-stable.zip' 'flutter_windows_3.22.3-stable.zip' (Join-Path $Cache 'flutter-3.22.3') 'flutter\bin\flutter.bat'
    $pythonEnvironment = Join-Path $Cache 'python'
    $venvPython = Join-Path $pythonEnvironment 'Scripts\python.exe'
    if (-not (Test-Path -LiteralPath $venvPython -PathType Leaf)) { Invoke-Checked $Python @('-m', 'venv', $pythonEnvironment) }
    $shimDirectory = Join-Path $Cache 'command-shims'
    New-Item -ItemType Directory -Path $shimDirectory -Force | Out-Null
    # build.py invokes these conventional command names through cmd.exe.
    $pythonShim = '@echo off' + [Environment]::NewLine + '"' + $venvPython + '" %*' + [Environment]::NewLine
    $pipShim = '@echo off' + [Environment]::NewLine + '"' + $venvPython + '" -m pip %*' + [Environment]::NewLine
    [IO.File]::WriteAllText((Join-Path $shimDirectory 'python3.cmd'), $pythonShim)
    [IO.File]::WriteAllText((Join-Path $shimDirectory 'pip3.cmd'), $pipShim)
    $env:PATH = "$shimDirectory;$pythonEnvironment\Scripts;" + $env:PATH
    $env:PIP_CACHE_DIR = Join-Path $Cache 'pip'
    Invoke-Checked $venvPython @('-m', 'pip', 'install', '--disable-pip-version-check', '-r', (Join-Path $StagedClient 'libs\portable\requirements.txt'))
    $codegenDirectory = Join-Path $Cache 'codegen-1.80.1-expand-1.0.95'
    $env:RUSTUP_TOOLCHAIN = "$ClientRust-x86_64-pc-windows-msvc"
    $env:CARGO_TARGET_DIR = Join-Path $Cache 'codegen-target'
    if (-not (Test-Path -LiteralPath (Join-Path $codegenDirectory 'bin\cargo-expand.exe') -PathType Leaf)) {
        Invoke-Checked $Rustup @('run', $env:RUSTUP_TOOLCHAIN, 'cargo', 'install', 'cargo-expand', '--version', '1.0.95', '--locked', '--root', $codegenDirectory)
    }
    if (-not (Test-Path -LiteralPath (Join-Path $codegenDirectory 'bin\flutter_rust_bridge_codegen.exe') -PathType Leaf)) {
        Invoke-Checked $Rustup @('run', $env:RUSTUP_TOOLCHAIN, 'cargo', 'install', 'flutter_rust_bridge_codegen', '--version', '1.80.1', '--features', 'uuid', '--locked', '--root', $codegenDirectory)
    }
    $env:PATH = (Join-Path $codegenDirectory 'bin') + ';' + $env:PATH
    $vcpkg = Join-Path $Cache 'vcpkg'
    if (-not (Test-Path -LiteralPath (Join-Path $vcpkg '.git') -PathType Container)) { Invoke-Checked $Git @('clone', 'https://github.com/microsoft/vcpkg', $vcpkg) }
    Invoke-Checked $Git @('-C', $vcpkg, 'checkout', '--detach', $VcpkgCommit)
    Invoke-Checked (Join-Path $vcpkg 'bootstrap-vcpkg.bat') @('-disableMetrics')
    $env:VCPKG_ROOT = $vcpkg
    $env:VCPKG_DISABLE_METRICS = '1'
    $env:VCPKG_DEFAULT_HOST_TRIPLET = 'x64-windows-static'
    $env:VCPKG_DOWNLOADS = Join-Path $Cache 'vcpkg-downloads'
    $env:VCPKG_DEFAULT_BINARY_CACHE = Join-Path $Cache 'vcpkg-binary'
    New-Item -ItemType Directory -Path $env:VCPKG_DOWNLOADS, $env:VCPKG_DEFAULT_BINARY_CACHE -Force | Out-Null
    Invoke-Checked (Join-Path $vcpkg 'vcpkg.exe') @('install', '--clean-after-build', '--triplet', 'x64-windows-static', "--x-manifest-root=$StagedClient", "--x-install-root=$vcpkg\installed")
    return @{ BuildFlutter = $flutterBuild; CodegenFlutter = $flutterCodegen; Python = $venvPython; Codegen = (Join-Path $codegenDirectory 'bin\flutter_rust_bridge_codegen.exe') }
}
function Build-Client {
    param([hashtable]$Tools)
    $env:RUSTUP_TOOLCHAIN = "$ClientRust-x86_64-pc-windows-msvc"
    $env:CARGO_TARGET_DIR = Join-Path $StagedClient 'artifacts\target'
    $env:PATH = (Split-Path $Tools.CodegenFlutter) + ';' + $env:PATH
    $pubspec = Join-Path $StagedClient 'flutter\pubspec.yaml'
    $lockfile = Join-Path $StagedClient 'flutter\pubspec.lock'
    $originalPubspec = [IO.File]::ReadAllBytes($pubspec)
    $originalLock = $null
    if (Test-Path -LiteralPath $lockfile) { $originalLock = [IO.File]::ReadAllBytes($lockfile) }
    Push-Location $StagedClient
    try {
        $temporary = [IO.File]::ReadAllText($pubspec) -replace 'extended_text:\s*14\.0\.0', 'extended_text: 13.0.0'
        [IO.File]::WriteAllText($pubspec, $temporary, (New-Object Text.UTF8Encoding($false)))
        Push-Location (Join-Path $StagedClient 'flutter')
        try { Invoke-Checked $Tools.CodegenFlutter @('pub', 'get') } finally { Pop-Location }
        # Written for the explicit build pipeline; agents must not execute codegen during editing.
        Invoke-Checked $Tools.Codegen @('--rust-input', './src/flutter_ffi.rs', '--dart-output', './flutter/lib/generated_bridge.dart', '--c-output', './flutter/macos/Runner/bridge_generated.h', '--llvm-path', (Split-Path $Libclang))
        Copy-Item -LiteralPath (Join-Path $StagedClient 'flutter\macos\Runner\bridge_generated.h') -Destination (Join-Path $StagedClient 'flutter\ios\Runner\bridge_generated.h') -Force
    } finally {
        [IO.File]::WriteAllBytes($pubspec, $originalPubspec)
        if ($null -ne $originalLock) { [IO.File]::WriteAllBytes($lockfile, $originalLock) }
        elseif (Test-Path -LiteralPath $lockfile) { Remove-Item -LiteralPath $lockfile -Force }
        Pop-Location
    }
    $env:PATH = (Split-Path $Tools.BuildFlutter) + ';' + $env:PATH
    $flutterRoot = Split-Path (Split-Path $Tools.BuildFlutter)
    $dropdownPatch = Join-Path $StagedClient '.github\patches\flutter_3.24.4_dropdown_menu_enableFilter.diff'
    $patchMarker = Join-Path $flutterRoot '.rustdesk-dropdown-applied'
    if (-not (Test-Path -LiteralPath $patchMarker)) {
        Invoke-Checked $Git @('-C', $flutterRoot, 'apply', $dropdownPatch)
        [IO.File]::WriteAllText($patchMarker, 'Flutter 3.24.5 dropdown patch')
    }
    Invoke-Checked $Tools.BuildFlutter @('precache', '--windows')
    $engineMarker = Join-Path $flutterRoot '.rustdesk-windows-engine-applied'
    if (-not (Test-Path -LiteralPath $engineMarker)) {
        # This moving engine URL matches upstream CI; its downloaded digest is recorded locally.
        $engineZip = Get-Download 'https://github.com/rustdesk/engine/releases/download/main/windows-x64-release.zip' 'windows-x64-release.zip'
        $engineExtract = Join-Path $Cache 'windows-engine'
        Remove-ArtifactDirectory $engineExtract
        Expand-Archive -LiteralPath $engineZip -DestinationPath $engineExtract -Force
        $engineSource = $engineExtract
        if (-not (Test-Path -LiteralPath (Join-Path $engineSource 'flutter_windows.dll'))) {
            $engineSource = Join-Path $engineExtract 'windows-x64-release'
        }
        Require-File (Join-Path $engineSource 'flutter_windows.dll') 'The downloaded Windows engine archive has an unexpected layout.'
        $engineDestination = Join-Path $flutterRoot 'bin\cache\artifacts\engine\windows-x64-release'
        New-Item -ItemType Directory -Path $engineDestination -Force | Out-Null
        Get-ChildItem -LiteralPath $engineSource -Force | Copy-Item -Destination $engineDestination -Recurse -Force
        $engineStream = [IO.File]::OpenRead($engineZip)
        $engineHasher = [Security.Cryptography.SHA256]::Create()
        try { $engineHash = [BitConverter]::ToString($engineHasher.ComputeHash($engineStream)).Replace('-', '') }
        finally {
            $engineStream.Dispose()
            $engineHasher.Dispose()
        }
        [IO.File]::WriteAllText($engineMarker, $engineHash)
    }
    Push-Location (Join-Path $StagedClient 'flutter')
    try { Invoke-Checked $Tools.BuildFlutter @('pub', 'get') } finally { Pop-Location }
    Push-Location $StagedClient
    try { Invoke-Checked $Tools.Python @('build.py', '--flutter', '--portable', '--hwcodec', '--vram') } finally { Pop-Location }
    $installers = @(Get-ChildItem -LiteralPath (Join-Path $StagedClient 'artifacts\publish') -Filter 'rustdesk-*-install.exe' -File)
    if ($installers.Count -ne 1 -or $installers[0].Length -eq 0) { throw 'The build did not produce exactly one fresh RustDesk installer executable.' }
    return $installers[0].FullName
}
function Build-Server {
    $env:RUSTUP_TOOLCHAIN = "$ServerRust-x86_64-pc-windows-msvc"
    $env:CARGO_TARGET_DIR = Join-Path $StagedServer 'artifacts\target'
    Push-Location $StagedServer
    try { Invoke-Checked $Rustup @('run', $env:RUSTUP_TOOLCHAIN, 'cargo', 'build', '--locked', '--release', '--bin', 'hbbs', '--bin', 'hbbr', '--bin', 'rustdesk-utils') } finally { Pop-Location }
    $outputs = @()
    foreach ($name in @('hbbs.exe', 'hbbr.exe', 'rustdesk-utils.exe')) {
        $path = Join-Path $env:CARGO_TARGET_DIR "release\$name"
        Require-File $path "The server build did not produce $name."
        if ((Get-Item -LiteralPath $path).Length -eq 0) { throw "Server output is empty: $path" }
        $outputs += $path
    }
    return $outputs
}
try {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not [Environment]::Is64BitProcess -or [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString() -ne 'X64') { throw 'Run this build in native x64 Windows PowerShell. Linux/WSL cannot build the Windows Flutter installer.' }
    $ClientSource = [IO.Path]::GetFullPath($ClientSource)
    $ServerSource = [IO.Path]::GetFullPath($ServerSource)
    if (-not $ArtifactsRoot) { $ArtifactsRoot = Join-Path (Split-Path $ClientSource -Parent) 'artifacts' }
    $ArtifactsRoot = [IO.Path]::GetFullPath($ArtifactsRoot)
    if ($NeedsApiWeb) {
        if (-not $ApiSource) { $ApiSource = Join-Path (Split-Path $ClientSource -Parent) 'rustdesk-api' }
        if (-not $ApiWebSource) { $ApiWebSource = Join-Path (Split-Path $ClientSource -Parent) 'rustdesk-api-web' }
        . (Join-Path $PSScriptRoot 'api.ps1')
        if (-not ($NeedsClient -or $NeedsServer)) {
            Invoke-ApiWindows -ApiSource $ApiSource -ApiWebSource $ApiWebSource -ArtifactsRoot $ArtifactsRoot -WebOnly:($Only -eq 'apiweb') -Check:$Check
            exit 0
        }
        Invoke-ApiWindows -ApiSource $ApiSource -ApiWebSource $ApiWebSource -ArtifactsRoot $ArtifactsRoot -Check
    }
    $Artifacts = Join-Path $ArtifactsRoot 'rustdesk'
    $Cache = Join-Path $Artifacts 'cache\windows-x64'
    $Downloads = Join-Path $Cache 'downloads'
    $Stage = Join-Path $Artifacts 'build\windows-x64'
    $Publish = Join-Path $Artifacts 'publish\windows-x64'
    $StagedClient = Join-Path $Stage 'client'
    $StagedServer = Join-Path $Stage 'server'
    foreach ($artifactPath in @($Cache, $Downloads, $Stage, $Publish)) { Assert-ArtifactPath $artifactPath | Out-Null }
    $Python = Find-Python
    $nativeGit = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)) 'Git\cmd\git.exe'
    if (Test-Path -LiteralPath $nativeGit -PathType Leaf) { $Git = $nativeGit }
    else {
        $gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue
        if (-not $gitCommand) { throw 'Git for Windows is required and must be on PATH.' }
        $Git = $gitCommand.Source
    }
    $gitVersion = & $Git --version
    if ($LASTEXITCODE -ne 0 -or $gitVersion -notmatch '\.windows\.') { throw 'Use native Git for Windows, not Cygwin Git, for this MSVC build.' }
    Require-File (Join-Path $ClientSource 'scripts\build\stage.py') 'Missing scripts/build/stage.py.'
    if ($NeedsClient) { Require-File (Join-Path $ClientSource 'build.py') 'The RustDesk client source directory is incomplete.' }
    if ($NeedsServer) { Require-File (Join-Path $ServerSource 'Cargo.toml') 'The RustDesk server source directory is incomplete.' }
    $env:VSCMD_SKIP_SENDTELEMETRY = '1'
    Import-VisualStudio
    $env:PATH = (Split-Path $Git) + ';' + $env:PATH
    if ($NeedsClient) {
        $Libclang = Find-Libclang
        Assert-SymlinkSupport
    }
    Write-Host "Python: $Python"
    Write-Host "Git: $Git"
    Write-Host "Selected components: $Only"
    Write-Host "Build: $Stage"
    Write-Host "Publish: $Publish"
    if ($Check) {
        Write-Host "Prerequisites passed. Rust/Flutter/vcpkg/CMake/Python packages will be prepared only inside $Cache during a build."
        exit 0
    }
    New-Item -ItemType Directory -Path $Cache, $Downloads -Force | Out-Null
    $env:TEMP = Join-Path $Cache 'tmp'
    $env:TMP = $env:TEMP
    $env:CARGO_HOME = Join-Path $Cache 'cargo'
    $env:RUSTUP_HOME = Join-Path $Cache 'rustup'
    $env:PUB_CACHE = Join-Path $Cache 'pub'
    $env:PYTHONPYCACHEPREFIX = Join-Path $Cache 'python-pycache'
    $env:CI = 'true'
    $env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
    $env:DART_SUPPRESS_ANALYTICS = 'true'
    $env:PIP_DISABLE_PIP_VERSION_CHECK = '1'
    $env:CARGO_INCREMENTAL = '0'
    $env:CC = 'cl.exe'
    $env:CXX = 'cl.exe'
    Remove-Item Env:CARGO_BUILD_TARGET -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $env:TEMP, $env:CARGO_HOME, $env:RUSTUP_HOME, $env:PUB_CACHE -Force | Out-Null
    Invoke-Checked $Python @((Join-Path $ClientSource 'scripts\build\stage.py'), '--client-source', $ClientSource, '--server-source', $ServerSource, '--artifacts-root', $ArtifactsRoot, '--destination', $Stage, '--only', $Only)
    Initialize-GitConfiguration
    $Rustup = Initialize-Rust
    $outputs = @()
    if ($NeedsClient) {
        $env:LIBCLANG_PATH = $Libclang
        $tools = Initialize-ClientTools
        $outputs += Build-Client $tools
    }
    if ($NeedsServer) { $outputs += Build-Server }
    if ($NeedsApiWeb) { Invoke-ApiWindows -ApiSource $ApiSource -ApiWebSource $ApiWebSource -ArtifactsRoot $ArtifactsRoot }
    # Publish only after every selected component has completed successfully.
    $pending = Assert-ArtifactPath (Join-Path $Artifacts ('publish\.windows-x64-' + [Guid]::NewGuid().ToString('N')))
    New-Item -ItemType Directory -Path $pending -Force | Out-Null
    foreach ($output in $outputs) { Copy-Item -LiteralPath $output -Destination $pending }
    if ($Only -eq 'all') { Remove-ArtifactDirectory $Publish }
    Assert-ArtifactPath $Publish | Out-Null
    New-Item -ItemType Directory -Path $Publish -Force | Out-Null
    if ($NeedsClient) { Get-ChildItem -LiteralPath $Publish -Filter 'rustdesk-*-install.exe' -File | Remove-Item -Force }
    foreach ($output in $outputs) { Move-Item -LiteralPath (Join-Path $pending (Split-Path $output -Leaf)) -Destination $Publish -Force }
    Remove-ArtifactDirectory $pending
    Write-Host "Build completed: $Publish"
} catch {
    Write-Error $_
    exit 1
}
