function Get-ApiCommand {
    param([string]$Name)
    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    throw "The API build requires $Name on PATH."
}
function Invoke-ApiCommand {
    param([string]$Executable, [string[]]$Arguments = @())
    & $Executable @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "$Executable failed with exit code $LASTEXITCODE." }
}
function Assert-ApiFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing API build input or output: $Path" }
}
function Assert-ApiGeneratedPath {
    param([string]$Source, [string]$RelativePath)
    $root = [IO.Path]::GetFullPath($Source).TrimEnd('\')
    $absolute = [IO.Path]::GetFullPath((Join-Path $root $RelativePath))
    if (-not $absolute.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Generated API path is outside its source directory: $absolute" }
    $ancestor = $absolute
    while ($ancestor) {
        $item = $null
        try { $item = Get-Item -LiteralPath $ancestor -Force -ErrorAction Stop }
        catch [System.Management.Automation.ItemNotFoundException] { }
        if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Refusing redirected API build path: $ancestor" }
        $ancestor = [IO.Path]::GetDirectoryName($ancestor)
    }
    return $absolute
}
function Assert-ApiSeparatePaths {
    param([string]$Source, [string]$Artifacts)
    $sourcePath = [IO.Path]::GetFullPath($Source).TrimEnd('\')
    $artifactPath = [IO.Path]::GetFullPath($Artifacts).TrimEnd('\')
    if ($sourcePath.Equals($artifactPath, [StringComparison]::OrdinalIgnoreCase) -or
        $sourcePath.StartsWith($artifactPath + '\', [StringComparison]::OrdinalIgnoreCase) -or
        $artifactPath.StartsWith($sourcePath + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "API source and artifact namespace must be separate: $Source / $Artifacts"
    }
}
function Copy-ApiWebSource {
    param([string]$Source, [string]$Destination, [switch]$Nested)
    foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
        if (-not $Nested -and $item.Name -in @('.git', 'artifacts', 'node_modules', 'dist')) { continue }
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Refusing redirected APIweb source: $($item.FullName)" }
        $target = Join-Path $Destination $item.Name
        if ($item.PSIsContainer) {
            New-Item -ItemType Directory -Path $target -Force | Out-Null
            Copy-ApiWebSource -Source $item.FullName -Destination $target -Nested
        } else {
            Copy-Item -LiteralPath $item.FullName -Destination $target -Force
        }
    }
}
function Remove-ApiGeneratedTree {
    param([string]$Path)
    $entry = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        if ($entry.PSIsContainer) { [IO.Directory]::Delete($Path, $false) }
        else { [IO.File]::Delete($Path) }
        return
    }
    if ($entry.PSIsContainer) {
        foreach ($child in Get-ChildItem -LiteralPath $Path -Force) {
            Remove-ApiGeneratedTree -Path $child.FullName
        }
    }
    $entry.Attributes = $entry.Attributes -band (-bnot [IO.FileAttributes]::ReadOnly)
    if ($entry.PSIsContainer) { [IO.Directory]::Delete($Path, $false) }
    else { [IO.File]::Delete($Path) }
}
function Find-ApiGo {
    param([string]$Artifacts)
    $candidates = @((Join-Path $Artifacts 'go-toolchain\go\bin\go.exe'))
    if ($env:GOROOT) { $candidates += (Join-Path $env:GOROOT 'bin\go.exe') }
    $command = Get-Command go.exe -CommandType Application -ErrorAction SilentlyContinue
    if ($command) { $candidates += $command.Source }
    foreach ($candidate in $candidates) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        $version = & $candidate version 2>$null
        if ($LASTEXITCODE -eq 0 -and $version -match '^go version go(\d+\.\d+\.\d+) windows/amd64' -and [version]$matches[1] -ge [version]'1.23.10') {
            return $candidate
        }
    }
    throw 'The API requires native Windows x64 Go 1.23.10 or newer. Put its go.exe on PATH, set GOROOT, or extract portable Go into artifacts/tools/rustdesk-api/go-toolchain/go.'
}
function Find-ApiCompiler {
    param([string]$ArtifactsRoot)
    $candidates = @()
    if ($env:CC -and [IO.Path]::GetFileName($env:CC) -notmatch '^(cl|clang-cl)(\.exe)?$') {
        $command = Get-Command $env:CC -CommandType Application -ErrorAction SilentlyContinue
        if ($command) { $candidates += $command.Source }
    }
    $candidates += (Join-Path $ArtifactsRoot 'tools\llvm-mingw-20261020-ucrt-x86_64\bin\gcc.exe')
    foreach ($name in @('x86_64-w64-mingw32-gcc.exe', 'gcc.exe', 'clang.exe')) {
        $command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue
        if ($command) { $candidates += $command.Source }
    }
    foreach ($candidate in $candidates) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        $target = & $candidate -dumpmachine 2>$null
        if ($LASTEXITCODE -eq 0 -and $target -match '^x86_64-.*(mingw|windows-gnu)') { return $candidate }
    }
    throw 'The API requires an x64 MinGW C compiler for CGO (for example llvm-mingw gcc.exe). Set CC or put it on PATH; MSVC cl.exe is not supported.'
}
function Invoke-ApiWindows {
    param([string]$ApiSource, [string]$ApiWebSource, [string]$ArtifactsRoot, [switch]$WebOnly, [switch]$Check)
    $ApiSource = [IO.Path]::GetFullPath($ApiSource)
    $ApiWebSource = [IO.Path]::GetFullPath($ApiWebSource)
    if (-not $ArtifactsRoot) { $ArtifactsRoot = Join-Path (Split-Path $ApiWebSource -Parent) 'artifacts' }
    $ArtifactsRoot = [IO.Path]::GetFullPath($ArtifactsRoot)
    $apiArtifacts = Join-Path $ArtifactsRoot 'rustdesk-api'
    $webArtifacts = Join-Path $ArtifactsRoot 'rustdesk-api-web'
    $apiTools = Join-Path $ArtifactsRoot 'tools\rustdesk-api'
    $webTools = Join-Path $ArtifactsRoot 'tools\rustdesk-api-web'
    $apiTemp = Join-Path $ArtifactsRoot 'tmp\windows-x64\rustdesk-api'
    $webTemp = Join-Path $ArtifactsRoot 'tmp\windows-x64\rustdesk-api-web'
    foreach ($source in @($ApiSource, $ApiWebSource)) {
        foreach ($namespace in @($apiArtifacts, $webArtifacts, $apiTools, $webTools, $apiTemp, $webTemp)) {
            Assert-ApiSeparatePaths $source $namespace
        }
    }
    Assert-ApiFile (Join-Path $ApiWebSource 'package.json')
    Assert-ApiFile (Join-Path $ApiWebSource 'package-lock.json')
    if (-not $WebOnly) {
        Assert-ApiFile (Join-Path $ApiSource 'build.bat')
        Assert-ApiFile (Join-Path $ApiSource 'go.mod')
    }
    foreach ($relative in @('build\windows-amd64\source', 'publish\web')) {
        Assert-ApiGeneratedPath $webArtifacts $relative | Out-Null
    }
    foreach ($relative in @('npm', 'vite')) {
        Assert-ApiGeneratedPath $webTools $relative | Out-Null
    }
    Assert-ApiGeneratedPath $ArtifactsRoot 'tmp\windows-x64\rustdesk-api-web' | Out-Null
    if (-not $WebOnly) {
        foreach ($relative in @('build\windows-amd64', 'publish\windows-amd64')) {
            Assert-ApiGeneratedPath $apiArtifacts $relative | Out-Null
        }
        foreach ($relative in @('go-build', 'go-mod', 'gopath', 'go-toolchain\go')) {
            Assert-ApiGeneratedPath $apiTools $relative | Out-Null
        }
        Assert-ApiGeneratedPath $ArtifactsRoot 'tmp\windows-x64\rustdesk-api' | Out-Null
    }
    $saved = @{}
    foreach ($name in @('PATH', 'GOROOT', 'GOENV', 'GOTOOLCHAIN', 'GOWORK', 'CC', 'CXX', 'CGO_ENABLED', 'GOOS', 'GOARCH', 'WEB_DIST', 'TEMP', 'TMP', 'TMPDIR', 'npm_config_cache', 'RUSTDESK_ARTIFACTS_DIR')) {
        $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    }
    try {
        $env:RUSTDESK_ARTIFACTS_DIR = $ArtifactsRoot
        $env:GOENV = 'off'
        $env:GOTOOLCHAIN = 'local'
        $env:GOWORK = 'off'
        $npmCache = Join-Path $webTools 'npm'
        $env:npm_config_cache = $npmCache
        $env:TEMP = $webTemp
        $env:TMP = $webTemp
        $env:TMPDIR = $webTemp
        $node = Get-ApiCommand 'node.exe'
        $npm = Get-ApiCommand 'npm.cmd'
        $nodeVersion = & $node --version
        if ($LASTEXITCODE -ne 0 -or $nodeVersion -notmatch '^v(\d+)\.' -or [int]$matches[1] -lt 18) { throw 'The API web build requires Node.js 18 or newer.' }
        Invoke-ApiCommand $npm @('--version')
        Write-Host "Node: $node ($nodeVersion)"
        Write-Host "npm: $npm"
        if (-not $WebOnly) {
            $go = Find-ApiGo $apiTools
            $compiler = Find-ApiCompiler $ArtifactsRoot
            $env:GOROOT = Split-Path (Split-Path $go -Parent) -Parent
            $env:PATH = (Split-Path $go -Parent) + ';' + (Split-Path $compiler -Parent) + ';' + $env:PATH
            $env:CC = $compiler
            $cxx = Join-Path (Split-Path $compiler -Parent) 'g++.exe'
            $env:CXX = $null
            if (Test-Path -LiteralPath $cxx -PathType Leaf) { $env:CXX = $cxx }
            $env:CGO_ENABLED = '1'
            $env:GOOS = 'windows'
            $env:GOARCH = 'amd64'
            Write-Host "Go: $go"
            Write-Host "CGO compiler: $compiler"
        }
        $webDist = Join-Path $webArtifacts 'publish\web'
        $webStage = Join-Path $webArtifacts 'build\windows-amd64\source'
        Write-Host "API web source: $ApiWebSource"
        Write-Host "API web stage: $webStage"
        Write-Host "API web publish: $webDist"
        if (-not $WebOnly) { Write-Host "API publish: $(Join-Path $apiArtifacts 'publish\windows-amd64')" }
        if ($Check) {
            Write-Host 'API prerequisites passed. No downloads or compilation were performed.'
            return
        }
        New-Item -ItemType Directory -Path $webTemp -Force | Out-Null
        Assert-ApiGeneratedPath $webArtifacts 'build\windows-amd64\source' | Out-Null
        if (Test-Path -LiteralPath $webStage) { Remove-ApiGeneratedTree -Path $webStage }
        New-Item -ItemType Directory -Path $webStage -Force | Out-Null
        Copy-ApiWebSource -Source $ApiWebSource -Destination $webStage
        Push-Location $webStage
        try {
            Invoke-ApiCommand $npm @('ci', '--include=dev', '--include=optional', '--no-audit', '--no-fund', '--cache', $npmCache)
            Invoke-ApiCommand $npm @('run', 'build', '--', '--outDir', $webDist, '--emptyOutDir')
        } finally { Pop-Location }
        Assert-ApiFile (Join-Path $webDist 'index.html')
        if (-not $WebOnly) {
            $env:WEB_DIST = $webDist
            New-Item -ItemType Directory -Path $apiTemp -Force | Out-Null
            $env:TEMP = $apiTemp
            $env:TMP = $apiTemp
            $env:TMPDIR = $apiTemp
            Push-Location $ApiSource
            try { Invoke-ApiCommand (Join-Path $ApiSource 'build.bat') } finally { Pop-Location }
            Assert-ApiFile (Join-Path $apiArtifacts 'publish\windows-amd64\rustdesk-api.exe')
        }
        Write-Host 'API build completed.'
    } finally {
        foreach ($name in $saved.Keys) {
            if ($null -eq $saved[$name]) { Remove-Item -LiteralPath ('Env:' + $name) -ErrorAction SilentlyContinue }
            else { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
        }
    }
}
