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
    # Home and approved branding are deliberately whitelisted, not a vault dump.
    foreach ($rel in @(
        'index.md',
        '03 - Recursos\Identidad visual\El Completo - Logo.png',
        '03 - Recursos\Identidad visual\El Completo - Icono.png'
    )) { Copy-From-Vault $rel }

    $approvedImages = @{}
    $byCategory = @{}
    $tryRecipes = New-Object System.Collections.Generic.List[string]
    $favRecipes = New-Object System.Collections.Generic.List[string]
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
        $sourceRaw = $raw
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
        # Only a local image explicitly referenced inside the approved folders can be public.
        # Never trust a photo merely because it was imported into Paprika.
        $approvedMatch = [regex]::Match($sourceRaw, '(?m)^foto:\s*["'']?(03 - Recursos[/\\]Fotografías[/\\](?:Ilustraciones IA|Propias aprobadas)[/\\][^"''\r\n]+?\.(?:webp|png|jpe?g))["'']?\s*$')
        if ($approvedMatch.Success) {
            $safeRel = $approvedMatch.Groups[1].Value.Replace('/', '\')
            $safeSource = Join-Path $VaultPath $safeRel
            if (-not (Test-Path -LiteralPath $safeSource -PathType Leaf)) {
                throw "Falta fotografia aprobada: $safeRel"
            }
            $safeName = [System.IO.Path]::GetFileName($safeRel)
            $approvedImages[$safeRel] = $true
            $raw = [regex]::Replace($raw, '(?m)^foto:.*$', "foto: '$($approvedMatch.Groups[1].Value)'")
            $replacement = "## Fotografía`n`n![[$safeName]]`n`n"
            $raw = [regex]::Replace($raw, '(?ms)^## Fotografía\r?\n.*?(?=^## Ingredientes\b)', [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $replacement })
        }

        # After sanitization, allow exactly the new verified embed (if present).
        $testCopy = $raw
        if ($approvedMatch.Success) {
            $expectedEmbed = '![[ ' + $safeName + ' ]]'
            $testCopy = $testCopy.Replace('![[' + $safeName + ']]', '')
        }
        if ($testCopy -match '!\[\[|<img\b|!\[[^\]]*\]\(') {
            throw "Se encontro una referencia a imagen no aprobada en $rel. Se detuvo la exportacion."
        }
        Save-Text (Join-Path $stage $rel) $raw
        if ($raw -match '(?m)^estado:\s*por-probar\s*$') { $tryRecipes.Add($link) }
        if ($raw -match '(?m)^favorita:\s*true\s*$') { $favRecipes.Add($link) }
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
        @{ Name='Favoritas'; Title='Favoritas'; Intro='Nuestras favoritas de la casa.'; Values=$favRecipes.ToArray() },
        @{ Name='Por probar'; Title='Por probar'; Intro='Recetas que todavía estamos probando y mejorando.'; Values=$tryRecipes.ToArray() }
    )
    foreach ($item in $lists) {
        $values = @($item.Values | Sort-Object)
        if ($values.Count -eq 0) { $values = @('_Todavía no hay recetas en esta colección._') }
        $page = "---`ntitle: `"$($item.Title)`"`ndraft: false`n---`n`n# $($item.Title)`n`n$($item.Intro)`n`n" + ($values -join "`n") + "`n"
        Save-Text (Join-Path $stage "$($item.Name).md") $page
    }

    # Correct the homepage's previous statement that recipes are not published.
    $homePath = Join-Path $stage 'index.md'
    $homepageContent = [System.IO.File]::ReadAllText($homePath, [System.Text.Encoding]::UTF8)
    $homepageContent = [regex]::Replace($homepageContent, '(?ms)^> \[!note\] Estamos armando la mesa\r?\n.*?(?=\r?\n\r?\n|\z)', '> [!note] Un recetario en evolución' + "`n> Ya puedes consultar las recetas importadas desde Paprika. Algunas siguen **pendientes de revisar**: lee sus avisos antes de cocinar. Las fotografías importadas todavía no están publicadas.")
    Save-Text $homePath $homepageContent

    # Only explicitly referenced approved illustrations and own photos.
    foreach ($safeRel in $approvedImages.Keys) {
        $source = Join-Path $VaultPath $safeRel
        $destination = Join-Path $stage $safeRel
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force)
        Copy-Item -LiteralPath $source -Destination $destination -Force
    }

    # EL_COMPLETO_GALERIAS_AUTOMATICAS_V1
    # Insertado antes de verificar y activar las copias públicas.
    $galleryScript = Join-Path $RepoPath 'Generar-Galerias-El-Completo.ps1'
    if (-not (Test-Path -LiteralPath $galleryScript -PathType Leaf)) {
        throw 'Falta el generador de galerías automáticas.'
    }
    & $galleryScript -ContentPath $stage
    # EL_COMPLETO_SOLO_RECETAS_V1
    # Las paginas 00 - Categorias son temporales: nunca se publican.
    $temporaryCategories = Join-Path $stage '00 - Categorías'
    $temporaryPages = @(Get-ChildItem -LiteralPath $temporaryCategories -Filter '*.md' -File)
    $publicGalleryPages = @(Get-ChildItem -LiteralPath (Join-Path $stage '01 - Recetas') -Filter 'index.md' -Recurse -File)
    if ($temporaryPages.Count -ne 8 -or $publicGalleryPages.Count -ne 8) {
        throw 'Faltan galerias verificadas. No se elimina ningun archivo publico.'
    }
    Remove-Item -LiteralPath $temporaryCategories -Recurse -Force

    # Vinculos sin ambiguedad a las galerias canonicas de 01 - Recetas.
    $canonicalLinks = [ordered]@{
        'Bebidas'                     = '01 - Recetas/Bebidas/index'
        'Desayunos'                   = '01 - Recetas/Desayunos/index'
        'Ensaladas y acompañamientos' = '01 - Recetas/Ensaladas y acompañamientos/index'
        'Panes y masas'               = '01 - Recetas/Panes y masas/index'
        'Platos principales'          = '01 - Recetas/Platos principales/index'
        'Postres y dulces'            = '01 - Recetas/Postres y dulces/index'
        'Salsas y aderezos'           = '01 - Recetas/Salsas y aderezos/index'
        'Sopas y guisos'              = '01 - Recetas/Sopas y guisos/index'
    }
    $homepagePath = Join-Path $stage 'index.md'
    $homepageText = [System.IO.File]::ReadAllText($homepagePath, [System.Text.Encoding]::UTF8)
    foreach ($categoryName in $canonicalLinks.Keys) {
        $homepageText = $homepageText.Replace(
            '[[' + $categoryName + ']]',
            '[[' + $canonicalLinks[$categoryName] + '|' + $categoryName + ']]'
        )
    }
    $homepageText = $homepageText.Replace('## ¿Qué vamos a cocinar?', '## Recetas')
    Save-Text $homepagePath $homepageText
    # EL_COMPLETO_PORTADAS_MINIMALISTAS_V1
    # Esta portada pública sustituye el index original sin modificar Obsidian.
    $portalScript = Join-Path $RepoPath 'Generar-Portadas-El-Completo.ps1'
    if (-not (Test-Path -LiteralPath $portalScript -PathType Leaf)) {
        throw 'Falta el generador de portadas minimalistas.'
    }
    & $portalScript -ContentPath $stage

    $outNotes = @(Get-ChildItem -LiteralPath (Join-Path $stage '01 - Recetas') -Filter '*.md' -Recurse -File | Where-Object { $_.Name -ne 'index.md' })
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
