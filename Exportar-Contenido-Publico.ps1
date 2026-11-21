param(
    [Parameter(Mandatory=$true)][string]$VaultPath,
    [Parameter(Mandatory=$true)][string]$RepoPath
)
$ErrorActionPreference = 'Stop'
$VaultPath = (Resolve-Path -LiteralPath $VaultPath).Path
$RepoPath = (Resolve-Path -LiteralPath $RepoPath).Path
$public = Join-Path $RepoPath 'content'
if (-not (Test-Path -LiteralPath (Join-Path $VaultPath '04 - Sistema\Normas de las recetas.md'))) {
    throw 'No parece ser la boveda correcta de El Completo.'
}

function Publicable([string]$path) {
    $raw = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    if ($raw -notmatch '(?m)^draft:[ ]*false[ ]*$') { return $false }
    # Las fotos importadas NO estan aprobadas para una web publica.
    if ($raw -match 'Importadas de Paprika|imagen_importada:[ ]*true') { return $false }
    return $true
}

# Este directorio contiene solo archivos seleccionados para PUBLICAR,
# nunca una copia ciega de la boveda local.
if (Test-Path -LiteralPath $public) { Remove-Item -LiteralPath $public -Recurse -Force }
[void](New-Item -ItemType Directory -Path $public -Force)
$approved = New-Object System.Collections.Generic.List[string]

function Copy-Safe([string]$relativePath) {
    $src = Join-Path $VaultPath $relativePath
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { return }
    if (-not (Publicable $src)) { return }
    $dst = Join-Path $public $relativePath
    [void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst))
    Copy-Item -LiteralPath $src -Destination $dst -Force
    [void]$approved.Add($relativePath)
}

Copy-Safe 'index.md'
foreach ($dir in @('00 - Categorías','01 - Recetas','02 - Colecciones')) {
    $src = Join-Path $VaultPath $dir
    if (-not (Test-Path -LiteralPath $src)) { continue }
    Get-ChildItem -LiteralPath $src -Filter '*.md' -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($VaultPath.Length).TrimStart('\','/')
        Copy-Safe $rel
    }
}
Copy-Safe '03 - Recursos\Glosario culinario chileno.md'

# Identidad visual: creada para este proyecto.
$logoRelative = '03 - Recursos\Identidad visual'
$srcBrand = Join-Path $VaultPath $logoRelative
$dstBrand = Join-Path $public $logoRelative
[void](New-Item -ItemType Directory -Force -Path $dstBrand)
foreach ($name in @('El Completo - Logo.png','El Completo - Icono.png')) {
    $src = Join-Path $srcBrand $name
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { throw "Falta el archivo de marca: $src" }
    Copy-Item -LiteralPath $src -Destination (Join-Path $dstBrand $name) -Force
}

# Solo fotos de una carpeta creada especificamente para imagenes propias APROBADAS.
$ownRel = '03 - Recursos\Fotografías\Propias aprobadas'
$ownSource = Join-Path $VaultPath $ownRel
if (Test-Path -LiteralPath $ownSource) {
    $ownTarget = Join-Path $public $ownRel
    Copy-Item -LiteralPath $ownSource -Destination $ownTarget -Recurse -Force
}

# Verificaciones para impedir publicar accidentalmente material privado.
$forbidden = @(Get-ChildItem -LiteralPath $public -Recurse -File | Where-Object {
    $_.FullName -match 'Importadas de Paprika|\.paprikarecipes$|\.obsidian|04 - Sistema|00 - Plantillas'
})
if ($forbidden.Count -gt 0) { throw 'Hay archivos prohibidos en el contenido publico. Se detuvo la exportacion.' }
$drafts = @(Get-ChildItem -LiteralPath $public -Filter '*.md' -Recurse -File | Where-Object {
    [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8) -match '(?m)^draft:[ ]*true[ ]*$'
})
if ($drafts.Count -gt 0) { throw 'Se detectaron borradores en el contenido publico.' }

Write-Host ('Paginas publicables copiadas: ' + $approved.Count) -ForegroundColor Green
Write-Host 'Imagenes importadas de Paprika: NO publicadas.' -ForegroundColor Yellow
Write-Host 'Borradores de Obsidian: NO publicados.' -ForegroundColor Yellow
