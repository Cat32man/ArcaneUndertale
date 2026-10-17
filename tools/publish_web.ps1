<#
.SYNOPSIS
  Publishes the Godot Web build to the GitHub Pages site (https://cat32man.github.io/ArcaneUndertale/).

.DESCRIPTION
  How the site works: .github/workflows/static.yml runs on every push to `main`. It unzips
  "arcaneundertale (1).zip" from the repo root and deploys that to GitHub Pages. So updating the site means:
  export for Web -> zip the export -> commit the zip -> push.   This script does everything after the export.

  1. In Godot:  Project > Export... > Web > Export Project...  and save it as  build\web\index.html
     (uncheck "Export With Debug"). One time only: keep your usual options, including
     Progressive Web App > "Ensure Cross Origin Isolation Headers" ON. That is what makes it run on Pages.
  2. Double-click  publish_web.bat  (or run this script).

  Options:
    -Source <dir>   the export folder (default: build\web)
    -Message <txt>  commit message (default: "Update web build (date time)")
    -Export         run the Godot export first (needs an export preset named "Web" and the web export templates)
    -Godot <path>   Godot executable for -Export (default: $env:GODOT, or the 4.5.1 console exe in Downloads)
    -NoPush         make the commit but do not push (then press "Push origin" in GitHub Desktop)
    -DryRun         check the export and build the zip in a temp folder; touch nothing in the repo
    -Force          do not stop to ask about a possibly stale export

  Only the zip is ever staged - nothing else in your working folder gets committed by this script.
#>
[CmdletBinding()]
param(
    [string]$Source = "build\web",
    [string]$Message = "",
    [switch]$Export,
    [string]$Godot = "",
    [switch]$NoPush,
    [switch]$DryRun,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# ---- settings ---------------------------------------------------------------------------
$ZipName = "arcaneundertale (1).zip"     # the file name .github/workflows/static.yml unzips - keep in sync
$SiteUrl = "https://cat32man.github.io/ArcaneUndertale/"
$ActionsUrl = "https://github.com/Cat32man/ArcaneUndertale/actions"
$MaxZipMB = 95                            # GitHub rejects any single file over 100 MB
# -----------------------------------------------------------------------------------------

$Repo = Split-Path -Parent $PSScriptRoot  # tools\ -> project root
Set-Location $Repo

function Step([string]$text) { Write-Host ""; Write-Host "== $text" -ForegroundColor Cyan }
function Info([string]$text) { Write-Host "   $text" }
function Warn([string]$text) { Write-Host "   WARNING: $text" -ForegroundColor Yellow }
function Fail([string]$text) { Write-Host ""; Write-Host "ERROR: $text" -ForegroundColor Red; exit 1 }
function Invoke-Git {
    & git @args
    if ($LASTEXITCODE -ne 0) { Fail ("git " + ($args -join " ") + " failed (exit code $LASTEXITCODE)") }
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Fail "git was not found on PATH. Install Git for Windows, or use GitHub Desktop." }

# Sign-in: if the GitHub CLI is installed and logged in (gh auth login), let git use that login for this run.
# It is done with environment variables, so your global git config is never changed.
$GhExe = $null
$ghCmd = Get-Command gh -ErrorAction SilentlyContinue
if ($ghCmd) { $GhExe = $ghCmd.Source }
elseif (Test-Path "C:\Program Files\GitHub CLI\gh.exe") { $GhExe = "C:\Program Files\GitHub CLI\gh.exe" }
if ($GhExe) {
    & $GhExe auth status *> $null
    if ($LASTEXITCODE -eq 0) {
        $env:GIT_TERMINAL_PROMPT = "0"
        $env:GIT_CONFIG_COUNT = "2"
        $env:GIT_CONFIG_KEY_0 = "credential.helper"
        $env:GIT_CONFIG_VALUE_0 = ""    # forget any other helpers first
        $env:GIT_CONFIG_KEY_1 = "credential.helper"
        $env:GIT_CONFIG_VALUE_1 = '!"' + ($GhExe -replace "\\", "/") + '" auth git-credential'
        Info "Using the GitHub CLI login for git."
    }
}

# build\ lives inside the project, so tell Godot not to scan/import anything in it (its PNGs would become game assets)
New-Item -ItemType Directory -Force -Path (Join-Path $Repo "build") | Out-Null
$gdignore = Join-Path $Repo "build\.gdignore"
if (-not (Test-Path $gdignore)) { New-Item -ItemType File -Path $gdignore | Out-Null }

# ---- 1. optional: run the Godot export ----------------------------------------------------
if ($Export) {
    Step "Exporting with Godot"
    if (-not (Test-Path "export_presets.cfg") -or -not (Select-String -Path "export_presets.cfg" -Pattern 'name="Web"' -Quiet)) {
        Fail "No export preset named ""Web"" in export_presets.cfg. In Godot: Project > Export... > Add... > Web (name it Web), then try again - or export by hand to build\web\index.html and run this without -Export."
    }
    if (-not $Godot) { $Godot = $env:GODOT }
    if (-not $Godot) {
        $guess = Join-Path $env:USERPROFILE "Downloads\Godot_v4.5.1-stable_win64.exe\Godot_v4.5.1-stable_win64_console.exe"
        if (Test-Path $guess) { $Godot = $guess }
    }
    if (-not $Godot -or -not (Test-Path $Godot)) { Fail "Godot executable not found. Pass -Godot <path to the _console.exe>, or set the GODOT environment variable." }
    $out = Join-Path $Source "index.html"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $out) | Out-Null
    Info "$Godot --headless --export-release Web $out"
    & $Godot --headless --path $Repo --export-release "Web" $out
    if ($LASTEXITCODE -ne 0) { Fail "The Godot export failed (exit code $LASTEXITCODE). If it mentions export templates: in the Godot editor use Editor > Manage Export Templates and install the 4.5.1 templates." }
}

# ---- 2. check the export -------------------------------------------------------------------
Step "Checking the export in $Source"
if (-not (Test-Path $Source)) {
    Fail "Export folder not found: $Source`n   Export from Godot first: Project > Export... > Web > Export Project... and save it as build\web\index.html (or pass -Source <folder>)."
}
$src = (Resolve-Path $Source).Path
$html = Join-Path $src "index.html"
if (-not (Test-Path $html)) { Fail "No index.html in $src - the Web export must be named index.html." }
$wasm = @(Get-ChildItem $src -Filter *.wasm -File)
$pck = @(Get-ChildItem $src -Filter *.pck -File)
$js = @(Get-ChildItem $src -Filter *.js -File)
if ($wasm.Count -eq 0 -or $pck.Count -eq 0 -or $js.Count -eq 0) { Fail "The export folder is missing its .wasm / .pck / .js files. Re-export for Web." }
Get-ChildItem $src -File | ForEach-Object { Info ("{0,-34} {1,10:N0} bytes" -f $_.Name, $_.Length) }

# a stale export is the easy mistake: warn if the project changed after the .pck was built
$newest = Get-ChildItem -Path $Repo -Recurse -File -Include *.gd, *.tscn, *.png, *.wav, project.godot -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch "\\(build|\.godot|\.git|Arcane)\\" } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($newest -and $pck[0].LastWriteTime -lt $newest.LastWriteTime) {
    Warn ("The export looks OLDER than your latest change ({0}, edited {1}; the .pck was built {2})." -f $newest.Name, $newest.LastWriteTime, $pck[0].LastWriteTime)
    Warn "Re-export from Godot so the site gets your newest version."
    if (-not $Force -and -not $DryRun) {
        $answer = Read-Host "   Publish this older export anyway? (y/N)"
        if ($answer -notmatch "^[yY]") { Fail "Cancelled. Re-export, then run this again." }
    }
}

# ---- 3. get the repo up to date BEFORE making the zip (the zip may also change on GitHub) ---
if (-not $DryRun) {
    Step "Syncing with GitHub"
    $branch = (& git rev-parse --abbrev-ref HEAD).Trim()
    if ($branch -ne "main") { Fail "You are on branch '$branch'. The site deploys from 'main'; switch to it first." }
    Invoke-Git pull --rebase --autostash origin main
}

# ---- 4. zip ---------------------------------------------------------------------------------
Step "Building the zip"
$zip = if ($DryRun) { Join-Path $env:TEMP "au_dryrun.zip" } else { Join-Path $Repo $ZipName }
if (Test-Path $zip) { Remove-Item -LiteralPath $zip -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($src, $zip, [System.IO.Compression.CompressionLevel]::Optimal, $false)
$mb = [math]::Round((Get-Item -LiteralPath $zip).Length / 1MB, 1)
Info "$zip  ($mb MB)"
if ($mb -gt $MaxZipMB) { Fail "The zip is $mb MB - GitHub rejects files over 100 MB." }
$z = [System.IO.Compression.ZipFile]::OpenRead($zip)
try { $z.Entries | ForEach-Object { Info ("  in zip: " + $_.FullName) } } finally { $z.Dispose() }

if ($DryRun) {
    Step "Dry run finished"
    Info "Everything looks publishable. Nothing in the repo was changed."
    exit 0
}

# ---- 5. commit just the zip, then push -----------------------------------------------------
Step "Committing"
Invoke-Git add -f -- $ZipName   # -f: *.zip is in .gitignore on purpose, this is the one zip we do want
& git diff --cached --quiet
if ($LASTEXITCODE -eq 0) {
    Info "The zip is identical to what is already committed - nothing to publish."
    exit 0
}
if (-not $Message) { $Message = "Update web build (" + (Get-Date -Format "yyyy-MM-dd HH:mm") + ")" }
Invoke-Git commit -m $Message -- $ZipName

$ahead = (& git rev-list --count origin/main..HEAD).Trim()
if ($ahead -ne "1") { Info "Note: $ahead commits will be pushed (your earlier unpushed commits go along with this one)." }

if ($NoPush) {
    Step "Not pushing (-NoPush)"
    Info "Committed locally. Open GitHub Desktop and press 'Push origin' to publish."
    exit 0
}

Step "Pushing"
& git push origin main
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "The commit is made but the push failed (probably a sign-in prompt was closed)." -ForegroundColor Yellow
    Write-Host "Open GitHub Desktop and press 'Push origin' - it will upload the same commit." -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "Done! GitHub is building the site now (about 1-2 minutes)." -ForegroundColor Green
Info "Progress: $ActionsUrl"
Info "Site:     $SiteUrl   (hard refresh with Ctrl+F5 to skip the cached version)"
