function Install-Tachytome {
    $ErrorActionPreference = "Stop"
    $ProgressPreference    = "SilentlyContinue"
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $repo = "nnra6864/tachytome"
    $url  = "https://github.com/$repo"

    function Has($name) {
        [bool](Get-Command $name -ErrorAction SilentlyContinue)
    }

    function Ask($question, $default) {
        $hint   = if ($default -eq "y") { "[Y/n]" } else { "[y/N]" }
        $answer = Read-Host "$question $hint"
        if ([string]::IsNullOrWhiteSpace($answer)) { $answer = $default }
        return $answer -match "^[yY]"
    }

    function Refresh-Path {
        $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
    }

    function Offer($name, $id) {
        if (-not (Ask "$name is missing, install it?" "y")) { return $false }
        if (-not (Has "winget")) {
            Write-Warning "winget not found, install App Installer from the Microsoft Store"
            return $false
        }
        winget install -e --id $id --accept-source-agreements --accept-package-agreements | Out-Host
        $ok = $LASTEXITCODE -eq 0
        Refresh-Path
        if (-not $ok) { Write-Warning "Failed to install $name" }
        return $ok
    }

    function Newest-Tag($names) {
        $tags = foreach ($name in $names) {
            $v = $name -replace "^v", ""
            if ($v -notmatch "^\d+(\.\d+)*$") { continue }
            $parts = @($v.Split(".") | ForEach-Object { [int]$_ })
            $padded = $parts + @(0, 0, 0, 0)
            $key    = (($padded[0..3] | ForEach-Object { "{0:D6}" -f $_ }) -join "") + ("{0:D2}" -f $parts.Count)
            [pscustomobject]@{ Key = $key; Name = $name }
        }
        if (-not $tags) { return $null }
        return ($tags | Sort-Object Key | Select-Object -Last 1).Name
    }

    function Install-Git($target) {
        $names = git ls-remote --tags --refs "$url.git" | ForEach-Object { ($_ -split "/")[-1] }
        if ($LASTEXITCODE -ne 0) { throw "Failed to list the releases of $url" }
        $tag = Newest-Tag $names
        if ($tag) {
            Write-Host "Cloning Tachytome $tag into $target..."
            git clone -q --no-checkout "$url.git" $target
            if ($LASTEXITCODE -ne 0) { throw "Failed to clone $url" }
            git -C $target -c advice.detachedHead=false checkout -q $tag
            if ($LASTEXITCODE -ne 0) { throw "Failed to check out $tag" }
        } else {
            Write-Host "No release found, cloning master into $target..."
            git clone -q "$url.git" $target
            if ($LASTEXITCODE -ne 0) { throw "Failed to clone $url" }
        }
    }

    function Install-Archive($target) {
        $names = (Invoke-RestMethod "https://api.github.com/repos/$repo/tags?per_page=100").name
        $tag   = Newest-Tag $names
        $ref   = "refs/heads/master"
        $label = "master"
        if ($tag) {
            $ref   = "refs/tags/$tag"
            $label = $tag
        }
        Write-Host "Downloading Tachytome $label into $target..."
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ("tachytome_" + [guid]::NewGuid())
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        try {
            $zip = Join-Path $tmp "tachytome.zip"
            Invoke-WebRequest -UseBasicParsing -Uri "$url/archive/$ref.zip" -OutFile $zip
            Expand-Archive -Path $zip -DestinationPath $tmp
            $inner = Get-ChildItem -Path $tmp -Directory | Select-Object -First 1
            New-Item -ItemType Directory -Force -Path $target | Out-Null
            Copy-Item -Path (Join-Path $inner.FullName "*") -Destination $target -Recurse -Force
        } finally {
            Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
        }
    }

    $mpv     = Get-Command mpv -ErrorAction SilentlyContinue
    $mpv_dir = $null
    if ($mpv) {
        $exe_dir = Split-Path $mpv.Source
        if ($mpv.Source -match "\\scoop\\shims\\") { $exe_dir = Join-Path (Split-Path $exe_dir) "apps\mpv\current" }
        $portable = Join-Path $exe_dir "portable_config"
        if (Test-Path $portable) { $mpv_dir = $portable }
    } else {
        Write-Warning "mpv not found, install it from https://mpv.io/installation"
    }
    if (-not $mpv_dir -and $env:MPV_HOME) { $mpv_dir = $env:MPV_HOME }
    if (-not $mpv_dir) { $mpv_dir = Join-Path $env:APPDATA "mpv" }

    $target = Join-Path $mpv_dir "scripts\tachytome"

    if (Test-Path $target) {
        Write-Host "Tachytome is already installed at $target"
        if (-not (Ask "Reinstall it? The current install is moved out of the scripts dir first" "n")) {
            Write-Host "Nothing to do, use Update from the Tachytome menu to update it"
            return
        }
        $backup = Join-Path $mpv_dir ("tachytome-backup-" + (Get-Date -Format "yyyyMMddHHmmss"))
        Move-Item -Path $target -Destination $backup
        Write-Host "Moved the current install to $backup"
    }

    New-Item -ItemType Directory -Force -Path (Join-Path $mpv_dir "scripts") | Out-Null

    if ((Has "git") -or ((Offer "git" "Git.Git") -and (Has "git"))) {
        Install-Git $target
    } else {
        Write-Host "Installing without git, Update will download releases from GitHub"
        Install-Archive $target
    }

    if (-not (Has "ffmpeg")) {
        if (-not (Offer "FFmpeg" "Gyan.FFmpeg")) { Write-Warning "Tachytome needs FFmpeg, install it before rendering" }
    }

    Write-Host ""
    Write-Host "Tachytome is installed at $target"
    Write-Host "Restart mpv and press t to open the Tachytome menu"
}

Install-Tachytome
