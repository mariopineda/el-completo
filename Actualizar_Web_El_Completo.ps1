# Ejecutar en Windows PowerShell cuando haya nuevas recetas revisadas.
$ErrorActionPreference = 'Stop'
$vault = Join-Path $HOME 'Documents\El Completo'
$site = Join-Path $HOME 'Documents\El Completo - Sitio Web'
if (-not (Test-Path -LiteralPath (Join-Path $site '.git'))) { throw 'Primero ejecuta Publicar_El_Completo.ps1.' }
if (-not (Test-Path -LiteralPath $vault)) { throw "No encuentro la boveda: $vault" }
$remote = (& git -C $site remote get-url origin | Out-String).Trim()
if ($remote -notmatch 'mariopineda/el-completo(?:\.git)?$') { throw 'Repositorio GitHub inesperado. No se publicara.' }
& (Join-Path $site 'Exportar-Contenido-Publico.ps1') -VaultPath $vault -RepoPath $site
& git -C $site add -- content
& git -C $site diff --cached --quiet
if ($LASTEXITCODE -eq 0) {
    Write-Host 'No hay nuevas notas aprobadas para publicar.' -ForegroundColor Green
    exit 0
}
& git -C $site -c user.name='El Completo' -c user.email='el-completo@users.noreply.github.com' commit -m 'Actualizar recetas publicadas de El Completo'
if ($LASTEXITCODE -ne 0) { throw 'Falló el commit.' }
& git -C $site push origin main
if ($LASTEXITCODE -ne 0) { throw 'Falló el push.' }
Write-Host 'Contenido aprobado enviado a GitHub. Revisa GitHub Actions.' -ForegroundColor Green
