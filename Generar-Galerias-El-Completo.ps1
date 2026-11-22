#requires -Version 5.1
param(
    [Parameter(Mandatory=$true)][string]$ContentPath
)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$ContentPath = (Resolve-Path -LiteralPath $ContentPath).Path
$recipesRoot = Join-Path $ContentPath '01 - Recetas'
$categoryRoot = Join-Path $ContentPath '00 - Categorías'
$icon = Join-Path $ContentPath '03 - Recursos\Identidad visual\El Completo - Icono.png'
if (-not (Test-Path -LiteralPath $recipesRoot -PathType Container) -or
    -not (Test-Path -LiteralPath $categoryRoot -PathType Container) -or
    -not (Test-Path -LiteralPath $icon -PathType Leaf)) {
    throw 'La exportación no contiene recetas, categorías o el icono de El Completo.'
}

$allRecipes = @(Get-ChildItem -LiteralPath $recipesRoot -Recurse -File -Filter '*.md' | Where-Object { $_.Name -ne 'index.md' })
if ($allRecipes.Count -lt 50) {
    throw "La galería requiere las recetas exportadas; encontradas: $($allRecipes.Count)."
}

# This reads exclusively the sanitized public copies that the existing exporter just created.
# No source vault files and no photographs imported from Paprika are used.
$byCategory = @{}
$approvedCount = 0
foreach ($note in $allRecipes) {
    $category = Split-Path -Leaf (Split-Path -Parent $note.FullName)
    if (-not $byCategory.ContainsKey($category)) {
        $byCategory[$category] = New-Object 'System.Collections.Generic.List[object]'
    }
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($note.Name)
    $raw = [System.IO.File]::ReadAllText($note.FullName, [System.Text.Encoding]::UTF8)
    $head = [regex]::Match($raw, '(?s)\A---\r?\n(.*?)\r?\n---\r?\n')
    if (-not $head.Success) { throw "No hay frontmatter YAML: $($note.FullName)" }

    $imageName = 'El Completo - Icono.png'
    $photo = [regex]::Match($head.Groups[1].Value, '(?m)^foto:\s*["'']?(03 - Recursos[/\\]Fotografías[/\\](?:Ilustraciones IA|Propias aprobadas)[/\\][^"''\r\n]+?\.(?:webp|png|jpe?g))["'']?\s*$')
    if ($photo.Success) {
        $rel = $photo.Groups[1].Value.Replace('/', '\')
        $approvedPath = Join-Path $ContentPath $rel
        if (-not (Test-Path -LiteralPath $approvedPath -PathType Leaf)) {
            throw "Falta imagen aprobada en el contenido público: $rel"
        }
        $imageName = [System.IO.Path]::GetFileName($rel)
        $approvedCount++
    }
    $byCategory[$category].Add([pscustomobject]@{ Name = $stem; Image = $imageName })
}

$categories = @(Get-ChildItem -LiteralPath $categoryRoot -File -Filter '*.md')
if ($categories.Count -ne 8) { throw "Se esperaban 8 categorías; encontradas: $($categories.Count)" }
$totalCards = 0
foreach ($categoryPage in $categories) {
    $category = [System.IO.Path]::GetFileNameWithoutExtension($categoryPage.Name)
    $items = @()
    if ($byCategory.ContainsKey($category)) { $items = @($byCategory[$category] | Sort-Object Name) }
    $count = $items.Count
    $lines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($item in $items) {
        if ($item.Name -match '[\[\]\|]' -or $item.Image -match '[\[\]\|]') {
            throw "Nombre con caracteres que requieren escape: $($item.Name)"
        }
        # Obsidian-style embeds and links are resolved by Quartz (including accents and URL slugs).
        # Two Markdown trailing spaces put the recipe title on its own line within the card.
        $lines.Add('- ![[' + $item.Image + ']]  ')
        $lines.Add('  [[' + $item.Name + ']]')
    }
    if ($count -eq 0) { $lines.Add('_Todavía no hay recetas en esta categoría._') }
    $gallery = "## Recetas ilustradas ($count)`n`n" + ($lines -join "`n") + "`n`n"
    $old = [System.IO.File]::ReadAllText($categoryPage.FullName, [System.Text.Encoding]::UTF8)
    $pattern = '(?ms)^## Recetas(?: ilustradas)? \(\d+\)\s*\r?\n.*?(?=^> \[!warning\])'
    $matches = [regex]::Matches($old, $pattern)
    if ($matches.Count -ne 1) {
        throw "No se puede localizar de manera segura la lista antigua: $($categoryPage.Name)"
    }
    $new = [regex]::Replace($old, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $gallery })
    [System.IO.File]::WriteAllText($categoryPage.FullName, $new, $utf8)
    $totalCards += $count
}
if ($totalCards -ne $allRecipes.Count) {
    throw "Error de integridad: $totalCards tarjetas para $($allRecipes.Count) recetas."
}
# EL_COMPLETO_FOLDER_GALLERIES_V1: render the same gallery on recipe folder routes.
foreach ($categoryPage in $categories) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($categoryPage.Name)
    $targetFolder = Join-Path $recipesRoot $name
    if (-not (Test-Path -LiteralPath $targetFolder -PathType Container)) {
        throw "No existe la carpeta para generar su portada: $name"
    }
    $target = Join-Path $targetFolder 'index.md'
    $source = [System.IO.File]::ReadAllText($categoryPage.FullName,[System.Text.Encoding]::UTF8)
    $folderMarkdown = [regex]::Replace($source,'(?m)^draft:[ \t]*false[ \t]*\r?$',"draft: false`ncssclasses:`n  - el-completo-galeria")
    if ($folderMarkdown -eq $source -or $folderMarkdown -notmatch '(?m)^## Recetas ilustradas \(\d+\)') {
        throw "La pagina de categoria no contiene una galeria valida: $name"
    }
    $folderMarkdown = $folderMarkdown.Replace('[[index|Volver a la portada]]', '[Volver a la portada](/el-completo/)')
    if (Test-Path -LiteralPath $target) {
        $previous = [System.IO.File]::ReadAllText($target,[System.Text.Encoding]::UTF8)
        if ($previous -notmatch '(?m)^\s*-\s*el-completo-galeria\s*$') {
            throw "Hay una portada de carpeta manual que no se puede sobrescribir: $target"
        }
    }
    [System.IO.File]::WriteAllText($target,$folderMarkdown,$utf8)
}
Write-Host "Galerías listas: $($categories.Count) categorías, $totalCards tarjetas, $approvedCount imágenes aprobadas." -ForegroundColor Green
