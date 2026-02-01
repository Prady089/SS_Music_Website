param(
    [string]$RepoUrl = 'https://github.com/Prady089/SS_Music_Website.git',
    [string]$LocalSitePath = (Resolve-Path ".").Path,
    [string]$Branch = 'gh-pages',
    [switch]$UseGhCli
)

function ExitWithError([string]$msg, [int]$code = 1) {
    Write-Error $msg
    exit $code
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    ExitWithError 'Git is not installed or not in PATH. Install Git and try again.'
}

if ($UseGhCli -and -not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Warning 'gh CLI not found; skipping gh pages enable step.'
    $UseGhCli = $false
}

$TempDir = Join-Path $env:TEMP ("site-deploy-{0}" -f ([guid]::NewGuid().ToString()))
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
Write-Host ('Cloning {0} into {1} ...' -f $RepoUrl, $TempDir)

$cloneOutput = git clone $RepoUrl --depth 1 $TempDir 2>&1
if ($LASTEXITCODE -ne 0) { ExitWithError ('git clone failed: {0}' -f $cloneOutput) }

Push-Location $TempDir
try {
    Write-Host 'Cleaning repo clone (preserving .git) ...'
    Get-ChildItem -Force | Where-Object { $_.Name -ne '.git' } | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force }

    Write-Host ('Copying site files from: {0}' -f $LocalSitePath)
    if (-not (Test-Path -Path $LocalSitePath)) { ExitWithError ('Local site path not found: {0}' -f $LocalSitePath) }

    if (Get-Command robocopy -ErrorAction SilentlyContinue) {
        $source = (Resolve-Path -LiteralPath $LocalSitePath).ProviderPath
        $dest = (Get-Location).ProviderPath
        $args = @($source, $dest, '/E', '/COPY:DAT', '/R:2', '/W:1', '/XD', "$($source)\\.git")
        Write-Host ('Running: robocopy {0}' -f ($args -join ' '))
        $proc = Start-Process -FilePath robocopy -ArgumentList $args -NoNewWindow -Wait -PassThru
        if ($proc.ExitCode -ge 8) { Write-Warning ('robocopy exit code {0} — check copy results' -f $proc.ExitCode) }
    } else {
        Get-ChildItem -Path $LocalSitePath -Force | Where-Object { $_.Name -ne '.git' } | ForEach-Object {
            $dest = Join-Path $PWD $_.Name
            if ($_.PSIsContainer) { Copy-Item -LiteralPath $_.FullName -Destination $dest -Recurse -Force } else { Copy-Item -LiteralPath $_.FullName -Destination $dest -Force }
        }
    }

    $nojekyll = Join-Path $PWD '.nojekyll'
    if (-not (Test-Path $nojekyll)) { New-Item -Path $nojekyll -ItemType File -Force | Out-Null }

    git checkout -B $Branch 2>&1 | Out-Null

    $status = git status --porcelain
    if ($status) {
        git add -A
        git commit -m ("Deploy site: {0}" -f (Get-Date -Format o))
    } else {
        Write-Host 'No changes to commit; creating touch commit.'
        git add -A
        git commit -m ("Touch commit: {0}" -f (Get-Date -Format o)) | Out-Null
    }

    Write-Host ('Pushing to origin/{0} (force)...' -f $Branch)
    git push -u origin $Branch --force
    if ($LASTEXITCODE -ne 0) { ExitWithError 'git push failed' }

    if ($UseGhCli) {
        Write-Host 'Enabling GitHub Pages via gh CLI...'
        $ghOut = gh pages enable --branch $Branch --path / 2>&1
        if ($LASTEXITCODE -ne 0) { Write-Warning 'gh pages enable failed or is not supported for this repo.' }
    }

    Write-Host 'Deployment complete.'
}
finally {
    Pop-Location
}

Write-Host ('Temporary clone left at: {0} (remove it when done)' -f $TempDir)
