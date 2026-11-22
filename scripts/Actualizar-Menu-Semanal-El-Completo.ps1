#requires -Version 5.1
<#
.SYNOPSIS
  Selecciona hasta 5 recetas para "Esta semana en la cocina" y publica el menu.
.DESCRIPTION
  Clona el repo oficial, verifica los nombres exactos de las recetas y publica
  data/menu-semanal.json. No edita notas de recetas ni sus propiedades.
  Por defecto: de lunes a sabado, la semana actual; el domingo, la siguiente.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File "$HOME\Downloads\Actualizar-Menu-Semanal-El-Completo.ps1" -SemanaInicio 2026-11-23 -Recetas "Chana masala sencillo;Burrito de porotos negros y champiñones"
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File "$HOME\Downloads\Actualizar-Menu-Semanal-El-Completo.ps1" -Limpiar
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File "$HOME\Downloads\Actualizar-Menu-Semanal-El-Completo.ps1" -SemanaInicio 2026-11-23 -Recetas "Chana masala sencillo" -Simular
#>
[CmdletBinding()]
param(
  [string[]] $Recetas = @(),
  [string] $SemanaInicio = '',
  [switch] $Limpiar,
  [switch] $Simular,
  [string] $RepoUrl = 'https://github.com/mariopineda/el-completo.git'
)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$repoExpected = 'mariopineda/el-completo'
$work = Join-Path ([IO.Path]::GetTempPath()) ('ElCompletoMenu-' + [guid]::NewGuid().ToString('N'))
try {
  if ($RepoUrl -notmatch '^https://github\.com/mariopineda/el-completo(?:\.git)?$') {
    throw 'Repositorio remoto inesperado.'
  }
  if ($Recetas.Count -eq 1 -and $Recetas[0].Contains(';')) {
    $Recetas = @($Recetas[0].Split(';') | ForEach-Object { $_.Trim() })
  }
  if ($Limpiar -and $Recetas.Count -gt 0) { throw 'Use -Limpiar O -Recetas; no ambos.' }
  if (!$Limpiar -and ($Recetas.Count -lt 1 -or $Recetas.Count -gt 5)) {
    throw 'Indique de 1 a 5 recetas con -Recetas, o use -Limpiar.'
  }
  if (!$SemanaInicio) {
    $today = (Get-Date).Date
    $offset = (([int]$today.DayOfWeek + 6) % 7)
    $start = $today.AddDays(-$offset)
    if ($today.DayOfWeek -eq [DayOfWeek]::Sunday) { $start = $start.AddDays(7) }
    $SemanaInicio = $start.ToString('yyyy-MM-dd')
  }
  try {
    $parsed = [DateTime]::ParseExact($SemanaInicio,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture)
  } catch { throw 'SemanaInicio debe tener formato YYYY-MM-DD.' }
  if ($parsed.DayOfWeek -ne [DayOfWeek]::Monday) { throw 'SemanaInicio debe ser lunes.' }
  if (!(Get-Command git -ErrorAction SilentlyContinue)) { throw 'No se encontro Git en PATH.' }

  $null = New-Item -ItemType Directory -Path $work -Force
  $repo = Join-Path $work 'repo'
  & git clone --depth 1 $RepoUrl $repo
  if ($LASTEXITCODE -ne 0) { throw 'No se pudo clonar GitHub.' }
  $weekFile = Join-Path $repo 'data\menu-semanal.json'
  $recipeRoot = Join-Path $repo 'content\01 - Recetas'
  if (!(Test-Path -LiteralPath $weekFile -PathType Leaf) -or !(Test-Path -LiteralPath $recipeRoot -PathType Container)) {
    throw 'La funcion de menu semanal aun no esta instalada en GitHub.'
  }
  $names = New-Object 'System.Collections.Generic.Dictionary[string,int]' ([StringComparer]::Ordinal)
  $drafts = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
  foreach ($f in @(Get-ChildItem -LiteralPath $recipeRoot -File -Recurse -Filter '*.md' | Where-Object { $_.Name -ne 'index.md' })) {
    $name = [IO.Path]::GetFileNameWithoutExtension($f.Name)
    $body = [IO.File]::ReadAllText($f.FullName,[Text.Encoding]::UTF8)
    if ($body -match '(?m)^draft:\s*true\s*$') { [void]$drafts.Add($name); continue }
    if (!$names.ContainsKey($name)) { $names.Add($name,1) } else { $names[$name]++ }
  }
  $items = New-Object 'System.Collections.Generic.List[string]'
  foreach ($name in $Recetas) {
    $trimmed = ([string]$name).Trim()
    if (!$names.ContainsKey($trimmed)) { throw "Receta no encontrada, o esta en borrador: $trimmed" }
    if ($names[$trimmed] -ne 1) { throw "Nombre de receta ambiguo: $trimmed" }
    if ($items.Contains($trimmed)) { throw "Receta repetida: $trimmed" }
    $items.Add($trimmed)
  }
  $updated = [ordered]@{
    semana_inicio = if ($Limpiar) { $null } else { $SemanaInicio }
    recetas = @($items.ToArray())
  }
  $json = ConvertTo-Json -InputObject $updated -Depth 6
  $old = [IO.File]::ReadAllText($weekFile,[Text.Encoding]::UTF8)
  Write-Host ('Semana: ' + $(if ($Limpiar) { 'sin seleccion' } else { $SemanaInicio })) -ForegroundColor Cyan
  foreach ($item in $items) { Write-Host ('  - ' + $item) }
  if ($Simular) { Write-Host 'SIMULACION: no se envio nada a GitHub.'; return }
  if ($old.Trim() -eq $json.Trim()) { Write-Host 'Menu sin cambios, no hay nada que publicar.'; return }
  [IO.File]::WriteAllText($weekFile,$json + "`n",$utf8)
  & git -C $repo add -- 'data/menu-semanal.json'
  if ($LASTEXITCODE -ne 0) { throw 'git add fallo.' }
  & git -C $repo -c 'user.name=El Completo' -c 'user.email=el-completo@users.noreply.github.com' commit -m ('Actualizar menu semanal de El Completo: ' + $SemanaInicio)
  if ($LASTEXITCODE -ne 0) { throw 'git commit fallo.' }
  & git -C $repo push origin HEAD:main
  if ($LASTEXITCODE -ne 0) { throw 'git push fallo. Es posible que se haya actualizado la rama principal; vuelva a ejecutar.' }
  Write-Host 'Menu semanal enviado a GitHub. GitHub Actions actualizara la portada.' -ForegroundColor Green
} finally {
  if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
