#requires -Version 5.1
param(
    [Parameter(Mandatory=$true)][string]$ContentPath
)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$ContentPath = (Resolve-Path -LiteralPath $ContentPath).Path
$recipesRoot = Join-Path $ContentPath '01 - Recetas'
$categories = @('Bebidas', 'Desayunos', 'Ensaladas y acompañamientos', 'Panes y masas', 'Platos principales', 'Postres y dulces', 'Salsas y aderezos', 'Sopas y guisos')

function Get-Meta([string]$Text) {
    $match = [regex]::Match($Text, '\A\uFEFF?---\r?\n(?<body>[\s\S]*?)\r?\n---(?:\r?\n|$)')
    if (-not $match.Success) { throw 'Receta sin frontmatter YAML.' }
    return $match.Groups['body'].Value
}
function Is-Flag([string]$Meta, [string]$Key) {
    return [regex]::IsMatch($Meta, '(?im)^' + [regex]::Escape($Key) + ':\s*(?:true|yes)\s*$')
}
function Is-ToTry([string]$Meta) {
    return [regex]::IsMatch($Meta, '(?im)^estado:\s*["'']?por[ -]probar["'']?\s*$')
}
function Has-Warning([string]$Meta) {
    return (Is-Flag $Meta 'revision_pendiente') -or
       [regex]::IsMatch($Meta, '(?im)^alertas_de_importacion:\s*[1-9]\d*\s*$')
}
function Read-Collection([string]$Path) {
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $content = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
        foreach ($link in [regex]::Matches($content, '\[\[(?<target>[^\]|\r\n]+)(?:\|[^\]]*)?\]\]')) {
            $stem = [IO.Path]::GetFileName($link.Groups['target'].Value)
            [void]$set.Add($stem)
        }
    }
    return ,$set
}

$favorites = Read-Collection (Join-Path $ContentPath 'Favoritas.md')
$toTry = Read-Collection (Join-Path $ContentPath 'Por probar.md')
$updates = New-Object 'System.Collections.Generic.List[object]'
$total = 0
$withIcons = 0

foreach ($category in $categories) {
    $folder = Join-Path $recipesRoot $category
    $index = Join-Path $folder 'index.md'
    if (-not (Test-Path -LiteralPath $index -PathType Leaf)) { throw "No se encuentra la galeria: $category" }
    $existing = [IO.File]::ReadAllText($index, [Text.Encoding]::UTF8)
    if ($existing -notmatch '(?m)^## Recetas ilustradas \(\d+\)' -or $existing -notmatch 'el-completo-galeria') {
        throw "Indice de recetas no compatible: $category"
    }
    $lines = [regex]::Split($existing, '\r?\n')
    $inside = $false
    $found = 0
    $marked = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^## Recetas ilustradas \(\d+\)') { $inside = $true; continue }
        if ($inside -and ($lines[$i] -match '^> \[!' -or $lines[$i] -match '^\[Volver ' -or $lines[$i] -match '^## ')) {
            $inside = $false
        }
        if (-not $inside -or $i -eq 0) { continue }
        if ($lines[$i-1] -notmatch '^\s*-\s*!\[\[') { continue }
        $link = [regex]::Match($lines[$i], '^\s{2}\[\[(?<name>[^\]\r\n]+)\]\](?<tail>.*)$')
        if (-not $link.Success) { throw "Tarjeta con formato inesperado en $category, linea $($i+1)." }
        $fullName = $link.Groups['name'].Value
        $stem = ($fullName -split '\|', 2)[0]
        $stem = [IO.Path]::GetFileName($stem.Replace('/', '\'))
        $notePath = Join-Path $folder ($stem + '.md')
        if (-not (Test-Path -LiteralPath $notePath -PathType Leaf)) {
            throw "No se encuentra la receta vinculada: $category / $stem"
        }
        $meta = Get-Meta ([IO.File]::ReadAllText($notePath, [Text.Encoding]::UTF8))
        $emojis = New-Object 'System.Collections.Generic.List[string]'
        $labels = New-Object 'System.Collections.Generic.List[string]'
        if ((Is-Flag $meta 'favorita') -or $favorites.Contains($stem)) {
            $emojis.Add('❤️'); $labels.Add('Favorita')
        }
        if ((Is-ToTry $meta) -or $toTry.Contains($stem)) {
            $emojis.Add('🧪'); $labels.Add('Por probar')
        }
        if (Has-Warning $meta) {
            $emojis.Add('⚠️'); $labels.Add('Datos pendientes de revisión')
        }
        $base = $link.Groups[0].Value.Substring(0, $link.Groups[0].Value.Length - $link.Groups['tail'].Value.Length)
        $tail = $link.Groups['tail'].Value
        # Only remove the older manually added status text; keep any unrelated annotation.
        $tail = [regex]::Replace($tail, '(?i)\s*·\s*\*\*Por probar\*\*\s*$', '')
        $tail = [regex]::Replace($tail, '(?i)\s*<span class="el-completo-estados"[^>]*>.*?</span>\s*$', '')
        if ($emojis.Count -gt 0) {
            $label = [string]::Join('; ', $labels.ToArray())
            $tail = $tail.TrimEnd() + ' <span class="el-completo-estados" title="' + $label + '" aria-label="' + $label + '">' + [string]::Join(' ', $emojis.ToArray()) + '</span>'
            $marked++
        }
        $lines[$i] = $base + $tail
        $found++
    }
    $countMatch = [regex]::Match($existing, '(?m)^## Recetas ilustradas \((?<n>\d+)\)')
    if (-not $countMatch.Success -or $found -ne [int]$countMatch.Groups['n'].Value) {
        throw "La galeria $category declara $($countMatch.Groups['n'].Value) tarjetas pero se reconocieron $found."
    }
    $candidate = [string]::Join("`n", $lines)
    if ($candidate -ne $existing) {
        $updates.Add([pscustomobject]@{ Path = $index; Content = $candidate })
    }
    $total += $found
    $withIcons += $marked
}
$sourceCount = @(Get-ChildItem -LiteralPath $recipesRoot -File -Recurse -Filter '*.md' | Where-Object { $_.Name -ne 'index.md' }).Count
if ($total -ne $sourceCount -or $total -lt 50) {
    throw "Inconsistencia: $total tarjetas frente a $sourceCount recetas. No se modifico ninguna galeria."
}
foreach ($item in $updates) {
    [IO.File]::WriteAllText($item.Path, $item.Content, $utf8)
}
Write-Host "Estados listos: $total tarjetas, $withIcons con al menos un emoji, $($updates.Count) galerias actualizadas." -ForegroundColor Green