# Windows PowerShell 5.1. Uses a disposable directory; never changes installed data.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root '@Resources/Scripts/Manager.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors|Out-String)}
foreach($name in @('New-Game','Save-HeroLogo','Store-HeroMedia','Get-SettingRules','Convert-SettingValue')) {
 $fn=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
 . ([scriptblock]::Create($fn.Extent.Text))
}
function Assert-True([bool]$value,[string]$message){if(-not $value){throw $message}}
$Resources=Join-Path ([IO.Path]::GetTempPath()) ('GameHUB-MediaTest-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($Resources)
function Test-NativeLogo {
  Add-Type -AssemblyName System.Drawing
  $png=Join-Path $Resources 'logo.png';$bitmap=New-Object Drawing.Bitmap(128,32)
  try {$bitmap.SetPixel(16,8,[Drawing.Color]::FromArgb(127,20,190,150));$bitmap.Save($png,[Drawing.Imaging.ImageFormat]::Png)}finally{$bitmap.Dispose()}
  Store-HeroMedia $g 'Logo' $png $created
  $image=[Drawing.Bitmap]::FromFile((Join-Path $Resources $g.Logo))
  try {Assert-True ($image.Width -eq 128 -and $image.Height -eq 32 -and $image.GetPixel(0,0).A -eq 0) 'Logo aspect/alpha changed'}finally{$image.Dispose()}
  $logo=$g.Logo;[IO.File]::WriteAllText($png,'malformed PNG')
  $rejected=$false;try{Store-HeroMedia $g 'Logo' $png $created}catch{$rejected=$true}
  Assert-True ($rejected -and $g.Logo -eq $logo) 'Malformed logo replaced saved metadata'
  Store-HeroMedia $g 'Logo' '' $created;Assert-True ([IO.File]::Exists((Join-Path $Resources $logo))) 'Remove deleted the original logo'
  'PASS: native PNG decode/re-encode, aspect ratio, transparency, malformed image rejection'
}
try {
 $g=New-Game 'test';$created=New-Object 'System.Collections.Generic.List[string]'
 Assert-True ($g.PreviewVideo -eq '' -and $g.Logo -eq '' -and $g.PreviewStart -eq '' -and $g.PreviewEnd -eq '') 'Missing legacy defaults'
 $clip=Join-Path $Resources "Tester's [clip] = local.mp4"
 [IO.File]::WriteAllBytes($clip,[byte[]]@(0,0,0,24,102,116,121,112,109,112,52,50))
 Store-HeroMedia $g 'PreviewVideo' $clip $created
 $saved=Join-Path $Resources $g.PreviewVideo
 Assert-True ($g.PreviewVideo -like 'Art/Previews/test_*.mp4' -and [IO.File]::Exists($saved)) 'Local video copy failed'
 Assert-True ([Convert]::ToBase64String([IO.File]::ReadAllBytes($clip)) -eq [Convert]::ToBase64String([IO.File]::ReadAllBytes($saved))) 'Copy changed video bytes'
 $first=$g.PreviewVideo;Store-HeroMedia $g 'PreviewVideo' $clip $created
 Assert-True ($g.PreviewVideo -ne $first -and [IO.File]::Exists((Join-Path $Resources $first))) 'Replacement destroyed previous cache'
 $g.PreviewStart='1.5';$g.PreviewEnd='6';Store-HeroMedia $g 'PreviewVideo' '' $created
 Assert-True ($g.PreviewVideo -eq '' -and $g.PreviewStart -eq '' -and $g.PreviewEnd -eq '' -and [IO.File]::Exists($saved)) 'Remove deleted media or left trim settings'
 foreach($path in @((Join-Path $Resources 'missing.mp4'),'https://example.invalid/video.mp4',"bad`npath.mp4")) {
  $rejected=$false;try{Store-HeroMedia $g 'PreviewVideo' $path $created}catch{$rejected=$true};Assert-True $rejected 'Invalid source accepted'
 }
 $rules=Get-SettingRules
 Assert-True ($rules.PreviewDelay.Default -eq 900 -and $rules.PreviewAudio.Default -eq 0 -and $rules.PreviewLoop.Default -eq 0 -and $rules.HeroCinematic.Default -eq 0) 'Unsafe media defaults'
 foreach($pair in @(@('PreviewDelay',0),@('PreviewDelay',55),@('PreviewAudio',2),@('HeroVideo',-1),@('CinematicDelay',1000))) {
  $rejected=$false;try{Convert-SettingValue $pair[0] $pair[1]}catch{$rejected=$true};Assert-True $rejected 'Invalid media setting accepted'
 }
 if([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
  Test-NativeLogo
 } else {'SKIP: PNG/GDI processing requires Windows; video bytes are fixtures, not a decoder test.'}
 'PASS: local media copy, punctuation, immutable revisions, non-destructive removal, absent fields and settings validation'
} finally {if(Test-Path -LiteralPath $Resources){Remove-Item -LiteralPath $Resources -Recurse -Force}}
