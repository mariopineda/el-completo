param(
    [Parameter(Mandatory=$true)][string]$VaultPath,
    [Parameter(Mandatory=$true)][string]$RepoPath
)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$VaultPath = (Resolve-Path -LiteralPath $VaultPath).Path
$RepoPath = (Resolve-Path -LiteralPath $RepoPath).Path
$notesFolder = Join-Path $VaultPath '01 - Recetas'
if (-not (Test-Path -LiteralPath (Join-Path $VaultPath '04 - Sistema\Normas de las recetas.md') -PathType Leaf)) {
    throw 'La carpeta indicada no es la boveda El Completo.'
}
if (-not (Test-Path -LiteralPath $notesFolder -PathType Container)) {
    throw 'No existe la carpeta de recetas de Obsidian.'
}
$recipes = @(Get-ChildItem -LiteralPath $notesFolder -Filter '*.md' -File -Recurse)
if ($recipes.Count -lt 50) {
    throw "Se encontraron solo $($recipes.Count) recetas; se esperaban al menos 50. No se modificara el sitio."
}
$stage = Join-Path $RepoPath ('content.preparado.' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $stage -Force)
function Save-Text([string]$path, [string]$content) {
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force)
    [System.IO.File]::WriteAllText($path, $content, $utf8)
}
function Copy-From-Vault([string]$rel) {
    $src = Join-Path $VaultPath $rel
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { throw "Falta archivo del sitio: $rel" }
    $dst = Join-Path $stage $rel
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $dst) -Force)
    Copy-Item -LiteralPath $src -Destination $dst -Force
}
try {
    # Home, glossary, and branding are deliberately whitelisted, not a vault dump.
    foreach ($rel in @(
        'index.md',
        '03 - Recursos\Glosario culinario chileno.md',
        '03 - Recursos\Identidad visual\El Completo - Logo.png',
        '03 - Recursos\Identidad visual\El Completo - Icono.png'
    )) { Copy-From-Vault $rel }

    $byCategory = @{}
    $tryRecipes = New-Object System.Collections.Generic.List[string]
    $favRecipes = New-Object System.Collections.Generic.List[string]
    $photoRecipes = New-Object System.Collections.Generic.List[string]
    foreach ($note in $recipes) {
        $rel = $note.FullName.Substring($VaultPath.Length).TrimStart([char[]]@('\','/'))
        $category = Split-Path -Leaf (Split-Path -Parent $note.FullName)
        if (-not $byCategory.ContainsKey($category)) {
            $byCategory[$category] = New-Object System.Collections.Generic.List[string]
        }
        $stem = [System.IO.Path]::GetFileNameWithoutExtension($note.Name)
        $link = '- [[' + $stem + ']]'
        $byCategory[$category].Add($link)
        $raw = [System.IO.File]::ReadAllText($note.FullName, [System.Text.Encoding]::UTF8)
        if ($raw -notmatch '(?m)^draft:\s*true\s*$' -and $raw -notmatch '(?m)^draft:\s*false\s*$') {
            throw "No tiene propiedad draft; revisar antes de publicar: $rel"
        }
        # The published copy is visible; the local source remains a marked draft.
        $raw = [regex]::Replace($raw, '(?m)^draft:\s*true\s*$', 'draft: false')
        $raw = [regex]::Replace($raw, '(?m)^foto:.*$', "foto: ''")
        $raw = [regex]::Replace($raw, '(?m)^paprika_uid:.*\r?\n', '')
        # Keep clearly flagged original discrepancies, but remove all imported photos.
        $photoSection = "## Fotografía`n`n> [!info] Foto pendiente`n> La fotografía importada no se publica mientras no se confirme su autoría o licencia. En Obsidian se conserva la imagen original.`n`n"
        $raw = [regex]::Replace($raw, '(?ms)^## Fotografía\r?\n.*?(?=^## Ingredientes\b)', $photoSection)
        $raw = [regex]::Replace($raw, '(?m)^\s*!\[\[[^\]]+\]\]\s*$', '')
        $raw = [regex]::Replace($raw, '(?m)^\s*!\[[^\]]*\]\([^\)]+\)\s*$', '')
        $raw = [regex]::Replace($raw, '(?is)<img\b[^>]*>', '')
        $raw = $raw.Replace('antes de cocinar o publicar', 'antes de cocinar o considerarla revisada')
        $raw = $raw.Replace('[[Plantilla de registro de cocina]]', 'registro de cocina')
        if ($raw -match '!\[\[|<img\b|!\[[^\]]*\]\(') {
            throw "Se encontro una referencia a imagen no aprobada en $rel. Se detuvo la exportacion."
        }
        Save-Text (Join-Path $stage $rel) $raw
        if ($raw -match '(?m)^estado:\s*por-probar\s*$') { $tryRecipes.Add($link) }
        if ($raw -match '(?m)^favorita:\s*true\s*$') { $favRecipes.Add($link) }
        if ($raw -match '(?m)^foto_pendiente:\s*true\s*$') { $photoRecipes.Add($link) }
    }

    # The category pages always list the actual available recipes.
    $categories = [ordered]@{
        'Bebidas' = 'Bebidas para cada ocasión.'
        'Desayunos' = 'Para comenzar el día con ganas.'
        'Ensaladas y acompañamientos' = 'Verduras, ensaladas y cosas para acompañar.'
        'Panes y masas' = 'Pan, masas y preparaciones para hornear.'
        'Platos principales' = 'Recetas para compartir alrededor de la mesa.'
        'Postres y dulces' = 'Un gustito para cerrar la comida.'
        'Salsas y aderezos' = 'Aliños, salsas y acompañamientos sabrosos.'
        'Sopas y guisos' = 'Preparaciones de cuchara para entrar en calor.'
    }
    foreach ($name in $categories.Keys) {
        $lines = @()
        if ($byCategory.ContainsKey($name)) { $lines = @($byCategory[$name] | Sort-Object) }
        if ($lines.Count -eq 0) { $lines = @('_Todavía no hay recetas en esta categoría._') }
        $page = "---`ntitle: `"$name`"`ndraft: false`n---`n`n# $name`n`n$($categories[$name])`n`n## Recetas ($($byCategory[$name].Count))`n`n" + ($lines -join "`n") + "`n`n> [!warning] Revisión pendiente`n> Algunas recetas conservan avisos de importación. Lee los avisos antes de cocinarlas.`n`n[[index|Volver a la portada]]`n"
        Save-Text (Join-Path $stage "00 - Categorías\$name.md") $page
    }

    $lists = @(
        @{ Name='Por probar'; Title='Por probar'; Intro='Recetas que todavía estamos probando y mejorando.'; Values=$tryRecipes.ToArray() },
        @{ Name='Favoritas'; Title='Favoritas'; Intro='Nuestras favoritas de la casa.'; Values=$favRecipes.ToArray() },
        @{ Name='Recetas por fotografiar'; Title='Recetas por fotografiar'; Intro='Recetas que necesitan una fotografía propia.'; Values=$photoRecipes.ToArray() }
    )
    foreach ($item in $lists) {
        $values = @($item.Values | Sort-Object)
        if ($values.Count -eq 0) { $values = @('_Todavía no hay recetas en esta colección._') }
        $page = "---`ntitle: `"$($item.Title)`"`ndraft: false`n---`n`n# $($item.Title)`n`n$($item.Intro)`n`n" + ($values -join "`n") + "`n"
        Save-Text (Join-Path $stage "02 - Colecciones\$($item.Name).md") $page
    }

    # Correct the homepage's previous statement that recipes are not published.
    $homePath = Join-Path $stage 'index.md'
    $homepageContent = [System.IO.File]::ReadAllText($homePath, [System.Text.Encoding]::UTF8)
    $homepageContent = [regex]::Replace($homepageContent, '(?ms)^> \[!note\] Estamos armando la mesa\r?\n.*?(?=\r?\n\r?\n|\z)', '> [!note] Un recetario en evolución' + "`n> Ya puedes consultar las recetas importadas desde Paprika. Algunas siguen **pendientes de revisar**: lee sus avisos antes de cocinar. Las fotografías importadas todavía no están publicadas.")
    Save-Text $homePath $homepageContent

    # Only user-approved own photos, never the Paprika image directory.
    $approvedRel = '03 - Recursos\Fotografías\Propias aprobadas'
    $approvedPath = Join-Path $VaultPath $approvedRel
    if (Test-Path -LiteralPath $approvedPath -PathType Container) {
        $targetDir = Join-Path $stage $approvedRel
        [void](New-Item -ItemType Directory -Path $targetDir -Force)
        Get-ChildItem -LiteralPath $approvedPath -Force | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $targetDir -Recurse -Force
        }
    }

    $outNotes = @(Get-ChildItem -LiteralPath (Join-Path $stage '01 - Recetas') -Filter '*.md' -Recurse -File)
    $outPhotos = @(Get-ChildItem -LiteralPath $stage -Recurse -File | Where-Object {
        $_.FullName -match 'Importadas de Paprika|\.paprikarecipes$|\.obsidian|04 - Sistema|00 - Plantillas'
    })
    if ($outNotes.Count -ne $recipes.Count -or $outPhotos.Count -ne 0) {
        throw 'Fallaron las verificaciones del contenido publico. La carpeta publicada no se modifico.'
    }
    $live = Join-Path $RepoPath 'content'
    $old = Join-Path $RepoPath ('content.anterior.' + [guid]::NewGuid().ToString('N'))
    if (Test-Path -LiteralPath $live) { Move-Item -LiteralPath $live -Destination $old }
    try {
        Move-Item -LiteralPath $stage -Destination $live
    } catch {
        if (-not (Test-Path -LiteralPath $live) -and (Test-Path -LiteralPath $old)) {
            Move-Item -LiteralPath $old -Destination $live
        }
        throw
    }
    if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $old -Recurse -Force }
    Write-Host "Recetas listas para la web: $($outNotes.Count)" -ForegroundColor Green
    Write-Host 'Fotos importadas desde Paprika: excluidas.' -ForegroundColor Yellow
    Write-Host 'Recetas originales de Obsidian: intactas.' -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}
