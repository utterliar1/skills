param(
  [string]$SourceSkillsPath = "",
  [string]$OutputPath = "",
  [string]$TranslationsPath = "",
  [string]$ManifestPath = "",
  [string]$UpstreamArchiveUrl = "https://github.com/obra/superpowers/archive/refs/heads/main.zip"
)

$ErrorActionPreference = "Stop"

function Read-Utf8File {
  param([Parameter(Mandatory = $true)][string]$Path)

  $encoding = [System.Text.UTF8Encoding]::new($false)
  return [System.IO.File]::ReadAllText($Path, $encoding)
}

function Write-Utf8File {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Content
  )

  $encoding = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function ConvertTo-YamlSingleQuoted {
  param([Parameter(Mandatory = $true)][string]$Value)

  return "'" + ($Value -replace "'", "''") + "'"
}

function Update-SkillDescription {
  param(
    [Parameter(Mandatory = $true)][string]$SkillFile,
    [Parameter(Mandatory = $true)][string]$Description
  )

  $content = Read-Utf8File -Path $SkillFile
  $frontmatterPattern = "(?s)\A---\r?\n(?<frontmatter>.*?)\r?\n---(?<body>.*)\z"
  $match = [regex]::Match($content, $frontmatterPattern)

  if (-not $match.Success) {
    Write-Host "::warning file=$SkillFile,title=Missing skill frontmatter::Cannot localize description because frontmatter was not found."
    return
  }

  $descriptionLine = "description: $(ConvertTo-YamlSingleQuoted -Value $Description)"
  $frontmatter = $match.Groups["frontmatter"].Value

  if ([regex]::IsMatch($frontmatter, "(?m)^description:\s*.*$")) {
    $frontmatter = [regex]::Replace($frontmatter, "(?m)^description:\s*.*$", $descriptionLine, 1)
  }
  else {
    $frontmatter = $frontmatter.TrimEnd() + "`n" + $descriptionLine
  }

  $newContent = "---`n$frontmatter`n---" + $match.Groups["body"].Value
  Write-Utf8File -Path $SkillFile -Content $newContent
}

function Sync-SkillsDirectory {
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Destination,
    [Parameter(Mandatory = $true)][string]$Manifest
  )

  if (-not (Test-Path -LiteralPath $Source)) {
    throw "Source skills directory not found: $Source"
  }

  New-Item -ItemType Directory -Path $Destination -Force | Out-Null

  if (Test-Path -LiteralPath $Manifest) {
    $previous = Read-Utf8File -Path $Manifest | ConvertFrom-Json
    foreach ($skillName in @($previous.skills)) {
      $previousTarget = Join-Path $Destination $skillName
      if ((Test-Path -LiteralPath $previousTarget) -and (Test-Path -LiteralPath (Join-Path $previousTarget "SKILL.md"))) {
        Remove-Item -LiteralPath $previousTarget -Recurse -Force
      }
    }
  }

  $sourceSkillDirs = @(Get-ChildItem -LiteralPath $Source -Directory | Sort-Object Name)
  foreach ($sourceSkillDir in $sourceSkillDirs) {
    $target = Join-Path $Destination $sourceSkillDir.Name

    if (Test-Path -LiteralPath $target) {
      if (-not (Test-Path -LiteralPath (Join-Path $target "SKILL.md"))) {
        throw "Refusing to replace non-skill directory at repository root: $target"
      }

      Remove-Item -LiteralPath $target -Recurse -Force
    }

    Copy-Item -LiteralPath $sourceSkillDir.FullName -Destination $target -Recurse -Force
  }

  $manifestContent = [ordered]@{
    skills = @($sourceSkillDirs | Select-Object -ExpandProperty Name)
  } | ConvertTo-Json
  Write-Utf8File -Path $Manifest -Content ($manifestContent + "`n")

  return @($sourceSkillDirs | Select-Object -ExpandProperty Name)
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = $repoRoot
}

if ([string]::IsNullOrWhiteSpace($TranslationsPath)) {
  $TranslationsPath = Join-Path $scriptDir "translations.json"
}

if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
  $outputFullPath = [System.IO.Path]::GetFullPath($OutputPath).TrimEnd('\', '/')
  $repoFullPath = [System.IO.Path]::GetFullPath($repoRoot).TrimEnd('\', '/')

  if ($outputFullPath -eq $repoFullPath) {
    $ManifestPath = Join-Path $scriptDir "synced-skills.json"
  }
  else {
    $ManifestPath = Join-Path $OutputPath ".synced-skills.json"
  }
}

if (-not (Test-Path -LiteralPath $TranslationsPath)) {
  throw "Translations file not found: $TranslationsPath"
}

$translations = Read-Utf8File -Path $TranslationsPath | ConvertFrom-Json
$tempRoot = $null

try {
  if ([string]::IsNullOrWhiteSpace($SourceSkillsPath)) {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("superpowers-skills-" + [System.Guid]::NewGuid().ToString("N"))
    $archivePath = Join-Path $tempRoot "superpowers.zip"
    $extractPath = Join-Path $tempRoot "extract"

    New-Item -ItemType Directory -Path $tempRoot, $extractPath -Force | Out-Null
    Invoke-WebRequest -Uri $UpstreamArchiveUrl -OutFile $archivePath
    Expand-Archive -LiteralPath $archivePath -DestinationPath $extractPath -Force

    $SourceSkillsPath = Get-ChildItem -LiteralPath $extractPath -Directory |
      Select-Object -First 1 |
      ForEach-Object { Join-Path $_.FullName "skills" }
  }

  $skillNames = @(Sync-SkillsDirectory -Source $SourceSkillsPath -Destination $OutputPath -Manifest $ManifestPath)

  foreach ($skillName in $skillNames) {
    $skillFile = Join-Path $OutputPath "$skillName\SKILL.md"

    if (-not (Test-Path -LiteralPath $skillFile)) {
      Write-Host "::warning file=$skillFile,title=Missing SKILL.md::$skillName has no SKILL.md file."
      continue
    }

    $translation = $translations.PSObject.Properties[$skillName]
    if ($null -eq $translation -or [string]::IsNullOrWhiteSpace($translation.Value.description)) {
      Write-Host "::warning file=$TranslationsPath,title=Missing skill translation::$skillName has no Chinese description."
      continue
    }

    Update-SkillDescription -SkillFile $skillFile -Description $translation.Value.description
  }

  Write-Host "Synced $($skillNames.Count) skills to $OutputPath"
}
finally {
  if ($null -ne $tempRoot -and (Test-Path -LiteralPath $tempRoot)) {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}
