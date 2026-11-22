#requires -Version 5.1
<#
.SYNOPSIS
  Instala una receta de El Completo, su foto y su ficha en la galeria de categoria.
.DESCRIPTION
  Paquete ZIP: manifiesto.json con sha256 por ruta, una receta en
  01 - Recetas/<Categoria>/<Receta>.md y fotografia(s) en 03 - Recursos/.
  La categoria se toma de la carpeta de la receta, no de una lista fija.
  Compatible con Windows PowerShell 5.1; Git autenticado para publicar.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Instalar-Receta-El-Completo-v6.ps1
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Instalar-Receta-El-Completo-v6.ps1 -ZipPath .\Otra_Receta.zip -Simular
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Instalar-Receta-El-Completo-v6.ps1 -ZipPath .\Otra_Receta.zip -SoloLocal
#>
[CmdletBinding()]
param(
  [string] $VaultPath = 'C:\Users\mpine\Documents\El Completo',
  [string] $ZipPath = '',
  [string] $RepoUrl = 'https://github.com/mariopineda/el-completo.git',
  [switch] $Simular,
  [switch] $SoloLocal,
  [switch] $ReemplazarExistentes
)
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir = (Get-Location).Path }
if ([string]::IsNullOrWhiteSpace($ZipPath)) {
  $ZipPath = Join-Path $scriptDir 'El_Completo_Burrito_Por_Probar.zip'
}
$ZipPath = [IO.Path]::GetFullPath($ZipPath)
$utf8 = New-Object System.Text.UTF8Encoding($false)
$work = Join-Path ([IO.Path]::GetTempPath()) ('ElCompletoInstaller-' + [guid]::NewGuid().ToString('N'))

function Invoke-Git([string] $directory, [string[]] $arguments) {
  & git -C $directory @arguments
  if ($LASTEXITCODE -ne 0) { throw ('Git fallo: git ' + ($arguments -join ' ')) }
}
function Read-Text([string] $path) {
  return [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
}
function Write-Text([string] $path, [string] $value) {
  [IO.File]::WriteAllText($path, $value, $utf8)
}
function Add-ToGallery([string] $original, [string] $recipeName, [string] $imageName, [string] $status) {
  # Normalize the damaged UTF-8 strings produced by older PowerShell scripts.
  $badRecipeName = [Text.Encoding]::GetEncoding(1252).GetString([Text.Encoding]::UTF8.GetBytes($recipeName))
  $badImageName = [Text.Encoding]::GetEncoding(1252).GetString([Text.Encoding]::UTF8.GetBytes($imageName))
  $original = $original.Replace($badRecipeName, $recipeName).Replace($badImageName, $imageName)
  $badSeparator = ([char]0x00C2).ToString() + ([char]0x00B7).ToString()
  $original = $original.Replace($badSeparator, ([char]0x00B7).ToString())
  $target = '[[' + $recipeName + ']]'
  if ($original.Contains($target)) { return $original }
  $header = [regex]::Match($original, '(?m)^## Recetas ilustradas \((\d+)\)[ \t]*$')
  if (!$header.Success) { throw 'Indice sin cabecera "## Recetas ilustradas (N)". No se modifica.' }
  $number = [int]$header.Groups[1].Value
  $suffix = if ($status) { ' · **' + $status + '**' } else { '' }
  $entry = '- ![[' + $imageName + ']]  ' + "`n" + '  [[' + $recipeName + ']]' + $suffix
  $newHeader = '## Recetas ilustradas (' + ($number + 1) + ')'
  # Mantener exactamente las entradas previas y su orden; agregar la nueva tras la cabecera.
  $result = $original.Remove($header.Index, $header.Length).Insert($header.Index, $newHeader)
  $position = $header.Index + $newHeader.Length
  return $result.Insert($position, "`n`n" + $entry)
}

function Ensure-NutritionTemplate([string] $recipeFile) {
  $text = Read-Text $recipeFile
  if ($text -match '(?m)^## Información nutricional\s*$' -and $text -match '(?m)^nutricion:\s*$') { return }
  throw 'La receta no cumple el estándar nutricional v1. Use Plantilla-Receta-El-Completo-Nutricion.md y rellene la porción, la tabla resumida, el detalle desplegable y YAML nutricion. Los valores desconocidos deben ser null/ND.'
}

function Ensure-Files([string] $baseDir, [string] $sourceDir, [string[]] $paths, [string] $backupDir) {
  foreach ($relative in $paths) {
    $source = Join-Path $sourceDir ($relative.Replace('/', '\'))
    $target = Join-Path $baseDir ($relative.Replace('/', '\'))
    if (Test-Path -LiteralPath $target -PathType Leaf) {
      $oldHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
      $newHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
      if ($oldHash -eq $newHash) { Write-Host ('Ya existe, identico: ' + $relative); continue }
      if (!$ReemplazarExistentes) { throw "Archivo distinto ya existe: $target. Use -ReemplazarExistentes para reemplazar con copia de seguridad." }
      if ($backupDir) {
        $oldPath = Join-Path $backupDir ($relative.Replace('/', '\'))
        New-Item -ItemType Directory -Path (Split-Path -Parent $oldPath) -Force | Out-Null
        Copy-Item -LiteralPath $target -Destination $oldPath -Force
      }
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $target -Force
    Write-Host ('Instalado: ' + $relative)
  }
}
try {
  if (!(Test-Path -LiteralPath $ZipPath -PathType Leaf)) { throw "No se encontro ZIP: $ZipPath" }
  if (!(Test-Path -LiteralPath (Join-Path $VaultPath '01 - Recetas') -PathType Container) -or
      !(Test-Path -LiteralPath (Join-Path $VaultPath '04 - Sistema') -PathType Container)) {
    throw "Vault no reconocido: $VaultPath"
  }
  New-Item -ItemType Directory -Path $work -Force | Out-Null
  $sourceRoot = Join-Path $work 'paquete'
  Expand-Archive -LiteralPath $ZipPath -DestinationPath $sourceRoot
  $manifestPath = Join-Path $sourceRoot 'manifiesto.json'
  if (!(Test-Path -LiteralPath $manifestPath)) { throw 'Falta manifiesto.json en el ZIP.' }
  $manifest = Read-Text $manifestPath | ConvertFrom-Json
  $paths = @($manifest.sha256.PSObject.Properties | ForEach-Object { $_.Name })
  if (!$paths.Count) { throw 'Manifiesto SHA256 vacio.' }
  foreach ($relative in $paths) {
    if ($relative -notmatch '^(01 - Recetas|03 - Recursos)/' -or $relative -match '(^|/)\.\.?(/|$)' -or $relative.Contains('\')) {
      throw "Ruta no permitida en el paquete: $relative"
    }
    $src = Join-Path $sourceRoot ($relative.Replace('/', '\'))
    if (!(Test-Path -LiteralPath $src -PathType Leaf)) { throw "Falta archivo de paquete: $relative" }
    $hash = (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne ([string]$manifest.sha256.PSObject.Properties[$relative].Value).ToLowerInvariant()) {
      throw "SHA256 incorrecto para $relative"
    }
  }
  $recipes = @($paths | Where-Object { $_ -match '^01 - Recetas/[^/]+/[^/]+\.md$' -and $_ -notmatch '/index\.md$' })
  $images = @($paths | Where-Object { $_ -match '^03 - Recursos/.+\.(png|jpg|jpeg|webp)$' })
  if ($recipes.Count -ne 1) { throw 'El paquete debe incluir exactamente UNA receta .md en 01 - Recetas/<categoria>/.' }
  if (!$images.Count) { throw 'El paquete debe incluir por lo menos UNA imagen.' }
  $recipePath = $recipes[0]
  $category = ($recipePath -split '/')[1]
  $recipeName = [IO.Path]::GetFileNameWithoutExtension($recipePath)
  Ensure-NutritionTemplate (Join-Path $sourceRoot ($recipePath.Replace('/', '\')))
  $recipeText = Read-Text (Join-Path $sourceRoot ($recipePath.Replace('/', '\')))
  $firstImage = ($images | Where-Object { [IO.Path]::GetFileNameWithoutExtension($_) -eq $recipeName } | Select-Object -First 1)
  if (!$firstImage) { $firstImage = $images[0] }
  $imageName = [IO.Path]::GetFileName($firstImage)
  if (!$recipeText.Contains('![[' + $imageName + ']]')) {
    throw "La receta no referencia la imagen $imageName; revise los nombres antes de publicar."
  }
  $statusMatch = [regex]::Match($recipeText, '(?m)^estado:\s*["'']?([^\r\n"'']+)')
  $status = if ($statusMatch.Success) { $statusMatch.Groups[1].Value.Trim() } else { '' }
  $indexRelative = '01 - Recetas/' + $category + '/index.md'
  $indexVault = Join-Path $VaultPath ($indexRelative.Replace('/', '\'))
  if (!(Test-Path -LiteralPath $indexVault -PathType Leaf)) {
    throw "No existe indice local de categoria: $indexRelative"
  }
  $localIndexOriginal = Read-Text $indexVault
  $localIndexUpdated = Add-ToGallery $localIndexOriginal $recipeName $imageName $status
  if ($Simular) {
    Write-Host ('SIMULACION: ' + $recipeName + ' -> ' + $category) -ForegroundColor Cyan
    foreach ($p in $paths) { Write-Host ('  Archivo: ' + $p) }
    Write-Host ('  Galeria: ' + $indexRelative)
    if ($localIndexOriginal -eq $localIndexUpdated) { Write-Host '  La galeria local ya incluye esta receta.' }
    if (!$SoloLocal) { Write-Host '  Se comprobaria y actualizaria el repositorio remoto.' }
    return
  }
  # Detectar conflictos locales ANTES de publicar; una segunda ejecucion identica es segura.
  foreach ($p in $paths) {
    $localFile = Join-Path $VaultPath ($p.Replace('/', '\'))
    if ((Test-Path -LiteralPath $localFile -PathType Leaf) -and !$ReemplazarExistentes) {
      if ((Get-FileHash -LiteralPath $localFile -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath (Join-Path $sourceRoot ($p.Replace('/', '\'))) -Algorithm SHA256).Hash) {
        throw "Conflicto local: $p. No se publico. Use -ReemplazarExistentes si lo desea."
      }
    }
  }
  if (!$SoloLocal) {
    if (!(Get-Command git -ErrorAction SilentlyContinue)) { throw 'No se encontro Git. Utilice -SoloLocal o instale Git.' }
    $clone = Join-Path $work 'repo'
    & git clone --depth 1 $RepoUrl $clone
    if ($LASTEXITCODE -ne 0) { throw 'No fue posible clonar el repositorio.' }
    $remoteIndex = Join-Path $clone ('content\' + $indexRelative.Replace('/', '\'))
    if (!(Test-Path -LiteralPath $remoteIndex -PathType Leaf)) { throw "Indice de categoria ausente en GitHub: $indexRelative" }
    $remoteOriginal = Read-Text $remoteIndex
    $remoteUpdated = Add-ToGallery $remoteOriginal $recipeName $imageName $status
    # Nunca sobrescribir silenciosamente una receta diferente ya publicada.
    foreach ($p in $paths) {
      $src = Join-Path $sourceRoot ($p.Replace('/', '\'))
      $dst = Join-Path $clone ('content\' + $p.Replace('/', '\'))
      if (Test-Path -LiteralPath $dst -PathType Leaf) {
        if ((Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash -and !$ReemplazarExistentes) {
          throw "Conflicto remoto: $p. No se publico."
        }
      }
      New-Item -ItemType Directory -Path (Split-Path -Parent $dst) -Force | Out-Null
      Copy-Item -LiteralPath $src -Destination $dst -Force
    }
    if ($remoteUpdated -ne $remoteOriginal) { Write-Text $remoteIndex $remoteUpdated }
    $staging = @($paths | ForEach-Object { 'content/' + $_ })
    $staging += ('content/' + $indexRelative)
    Invoke-Git $clone (@('add','--') + $staging)
    & git -C $clone diff --cached --quiet
    if ($LASTEXITCODE -eq 1) {
      Invoke-Git $clone @('commit','-m',('Install recipe and update '+$category+' gallery: '+$recipeName))
      Invoke-Git $clone @('push','origin','HEAD:main')
      Write-Host 'GitHub actualizado: receta, foto y galeria.' -ForegroundColor Green
    } elseif ($LASTEXITCODE -eq 0) {
      Write-Host 'GitHub ya esta actualizado; sin cambios.' -ForegroundColor Green
    } else { throw 'No se pudo comprobar el estado de Git.' }
  }
  $backupDir = Join-Path (Split-Path -Parent $VaultPath) ('El Completo - Respaldos\Recetas-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
  Ensure-Files $VaultPath $sourceRoot $paths $backupDir
  if ($localIndexUpdated -ne $localIndexOriginal) {
    $backupIndex = Join-Path $backupDir ($indexRelative.Replace('/', '\'))
    New-Item -ItemType Directory -Path (Split-Path -Parent $backupIndex) -Force | Out-Null
    Copy-Item -LiteralPath $indexVault -Destination $backupIndex -Force
    Write-Text $indexVault $localIndexUpdated
    Write-Host ('Galeria local actualizada: ' + $indexRelative) -ForegroundColor Green
  } else { Write-Host 'La receta ya figura en la galeria local.' }
  Write-Host 'LISTO. GitHub Pages/Quartz publicara el contenido si el workflow termina correctamente.' -ForegroundColor Green
} finally {
  if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
