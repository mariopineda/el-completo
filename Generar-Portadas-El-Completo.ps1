#requires -Version 5.1
param(
    [Parameter(Mandatory=$true)][string]$ContentPath
)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$ContentPath = (Resolve-Path -LiteralPath $ContentPath).Path
$recipesRoot = Join-Path $ContentPath '01 - Recetas'
$collectionRoot = $ContentPath
$resourcesRoot = Join-Path $ContentPath '03 - Recursos'
$logo = Join-Path $resourcesRoot 'Identidad visual\El Completo - Logo.png'

$categories = @(
    'Bebidas',
    'Desayunos',
    'Ensaladas y acompañamientos',
    'Panes y masas',
    'Platos principales',
    'Postres y dulces',
    'Salsas y aderezos',
    'Sopas y guisos'
)
foreach ($name in $categories) {
    $page = Join-Path (Join-Path $recipesRoot $name) 'index.md'
    if (-not (Test-Path -LiteralPath $page -PathType Leaf)) {
        throw "No existe la galería de la categoría: $name"
    }
    $md = [System.IO.File]::ReadAllText($page, [System.Text.Encoding]::UTF8)
    if ($md -notmatch '(?m)^## Recetas ilustradas \(\d+\)' -or $md -notmatch 'el-completo-galeria') {
        throw "Galería incompleta o incompatible: $name"
    }
}
foreach ($name in @('Favoritas', 'Por probar')) {
    if (-not (Test-Path -LiteralPath (Join-Path $collectionRoot ($name + '.md')) -PathType Leaf)) {
        throw "Falta colección publicada: $name"
    }
}
if (-not (Test-Path -LiteralPath $logo -PathType Leaf)) {
    throw 'Falta el logo aprobado.'
}
$recipeNotes = @(Get-ChildItem -LiteralPath $recipesRoot -Recurse -File -Filter '*.md' | Where-Object { $_.Name -ne 'index.md' })
if ($recipeNotes.Count -lt 50) {
    throw "Faltan recetas. Se encontraron $($recipeNotes.Count), mínimo esperado: 50."
}

function Save-Markdown([string]$destination, [string]$markdown) {
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force)
    [System.IO.File]::WriteAllText($destination, $markdown.Trim() + "`n", $utf8)
}

$homepageMarkdown = @'
---
title: "El Completo"
description: "No le pongái color, ponle palta. Recetario de casa."
tags: []
draft: false
---

![[El Completo - Logo.png]]

- [[01 - Recetas/index|🍲 Recetas]]
- [[Favoritas|❤️ Favoritas]]
- [[Por probar|🍽️ Por probar]]

<!-- EL_COMPLETO_MENU_SEMANAL_START -->

## Esta semana en la cocina

_Todavía no hay recetas seleccionadas para esta semana._

<!-- EL_COMPLETO_MENU_SEMANAL_END -->
<!-- EL_COMPLETO_RECIENTES_START -->

## Recetas recientes

_Las cinco recetas agregadas más recientemente aparecerán aquí al publicarse el sitio._

<!-- EL_COMPLETO_RECIENTES_END -->
'@
Save-Markdown (Join-Path $ContentPath 'index.md') $homepageMarkdown

$recipesIntro = @'
---
title: "Recetas"
draft: false
cssclasses:
  - el-completo-portal
---

# Recetas

Elige una categoría.

- [[01 - Recetas/Bebidas/index|🥤 Bebidas]]
- [[01 - Recetas/Desayunos/index|🍳 Desayunos]]
- [[01 - Recetas/Ensaladas y acompañamientos/index|🥗 Ensaladas y acompañamientos]]
- [[01 - Recetas/Panes y masas/index|🍞 Panes y masas]]
- [[01 - Recetas/Platos principales/index|🍽️ Platos principales]]
- [[01 - Recetas/Postres y dulces/index|🍰 Postres y dulces]]
- [[01 - Recetas/Salsas y aderezos/index|🫙 Salsas y aderezos]]
- [[01 - Recetas/Sopas y guisos/index|🍲 Sopas y guisos]]

[Volver al inicio](/el-completo/)
'@
Save-Markdown (Join-Path $recipesRoot 'index.md') $recipesIntro





Write-Host 'Portada minimalista: 3 accesos, 8 categorías y 2 listas.' -ForegroundColor Green
