$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$syncScript = Join-Path $scriptDir "sync-superpowers-skills.ps1"

if (-not (Test-Path -LiteralPath $syncScript)) {
  throw "Sync script not found: $syncScript"
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-skills-test-" + [System.Guid]::NewGuid().ToString("N"))

try {
  $repoRoot = Join-Path $tempRoot "repo"
  $sourceRoot = Join-Path $tempRoot "source-skills"
  $outputRoot = Join-Path $repoRoot "codex-skills\skills"
  $translationsPath = Join-Path $repoRoot "codex-skills\translations.json"
  $chineseDescription = -join ([char[]](0x4E2D, 0x6587, 0x5934, 0x8111, 0x98CE, 0x66B4, 0x63D0, 0x793A, 0x3002))

  New-Item -ItemType Directory -Path $repoRoot, $sourceRoot, (Split-Path -Parent $translationsPath) -Force | Out-Null

  $translatedSkill = Join-Path $sourceRoot "brainstorming"
  $untranslatedSkill = Join-Path $sourceRoot "new-skill"
  New-Item -ItemType Directory -Path $translatedSkill, $untranslatedSkill -Force | Out-Null

  @"
---
name: brainstorming
description: English brainstorming prompt.
---

# Brainstorming
"@ | Set-Content -LiteralPath (Join-Path $translatedSkill "SKILL.md") -Encoding UTF8

  @"
---
name: new-skill
description: English new skill prompt.
---

# New Skill
"@ | Set-Content -LiteralPath (Join-Path $untranslatedSkill "SKILL.md") -Encoding UTF8

  @"
{
  "brainstorming": {
    "description": "\u4e2d\u6587\u5934\u8111\u98ce\u66b4\u63d0\u793a\u3002"
  }
}
"@ | Set-Content -LiteralPath $translationsPath -Encoding UTF8

  & $syncScript -SourceSkillsPath $sourceRoot -OutputPath $outputRoot -TranslationsPath $translationsPath

  $utf8 = [System.Text.UTF8Encoding]::new($false)
  $translatedContent = [System.IO.File]::ReadAllText((Join-Path $outputRoot "brainstorming\SKILL.md"), $utf8)
  if ($translatedContent -notmatch [regex]::Escape("description: '$chineseDescription'")) {
    throw "Translated skill description was not localized."
  }

  $untranslatedContent = [System.IO.File]::ReadAllText((Join-Path $outputRoot "new-skill\SKILL.md"), $utf8)
  if ($untranslatedContent -notmatch "description: English new skill prompt\.") {
    throw "Untranslated skill description should remain unchanged."
  }

  Write-Host "sync-superpowers-skills tests passed"
}
finally {
  Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
