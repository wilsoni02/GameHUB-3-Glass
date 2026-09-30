# Windows PowerShell 5.1-compatible. Disposable diagnostics; never launches a video.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$wrapper=Join-Path $root '@Resources/Scripts/MotionHost.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($wrapper,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors|Out-String)}
foreach($name in @('Write-MotionStartupStatus','Get-MotionReferences')) {
 $fn=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
 if(-not $fn){throw ('Missing helper: '+$name)}
 . ([scriptblock]::Create($fn.Extent.Text))
}
function Assert-True([bool]$value,[string]$message){if(-not $value){throw $message}}
function Read-Status {
 $d=@{}
 foreach($line in [IO.File]::ReadAllLines((Join-Path $Resources 'Motion-status.ini'))) {
  if($line -match '^([^=]+)=(.*)$'){$d[$Matches[1]]=$Matches[2]}
 }
 return $d
}
$Resources=Join-Path ([IO.Path]::GetTempPath()) ('GameHUB Motion [test] '+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($Resources)
try {
 [IO.File]::WriteAllText((Join-Path $Resources 'Motion-command.ini'),"[Motion]`nSession=17904096051495119000`nToken=102`nAction=play`n")
 Write-MotionStartupStatus 'error' 'Compiler failed' "Missing WPF`nsecond line"
 $status=Read-Status
 Assert-True ($status.Session -eq '17904096051495119000' -and $status.Token -eq '102') 'Diagnostics lost request identity'
 Assert-True ($status.Phase -eq 'error' -and $status.LastError -eq 'Missing WPF second line' -and $status.Utc) 'Diagnostic payload was not readable INI'
 Write-MotionStartupStatus 'validated' 'New attempt' ''
 $status=Read-Status
 Assert-True ($status.Phase -eq 'validated' -and $status.LastError -eq '') 'New attempt retained a stale error'
 Assert-True (-not(Test-Path -LiteralPath ((Join-Path $Resources 'Motion-status.ini')+'.new'))) 'Temporary status file was left behind'
 'PASS: session/token diagnostics, one-line errors, replacement, stale-error reset and bracketed paths'
 if([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
  $refs=@(Get-MotionReferences)
  Assert-True ($refs.Count -eq 9) 'Wrong reference count'
  foreach($ref in $refs){Assert-True ([IO.Path]::IsPathRooted($ref) -and [IO.File]::Exists($ref)) 'Unresolved compiler reference'}
  $scripts=Join-Path $Resources 'Scripts';[void][IO.Directory]::CreateDirectory($scripts)
  Copy-Item -LiteralPath $wrapper -Destination (Join-Path $scripts 'MotionHost.ps1')
  Copy-Item -LiteralPath (Join-Path $root '@Resources/Scripts/MotionHost.cs') -Destination (Join-Path $scripts 'MotionHost.cs')
  & (Join-Path $scripts 'MotionHost.ps1') -Resources $Resources -ValidateOnly
  $status=Read-Status
  Assert-True ($status.Phase -eq 'validated') ('Native compiler failed: '+$status.LastError)
  'PASS: actual installed Windows assembly resolution and helper compilation; no playback/window started'
 } else {'SKIP: installed WPF assembly resolution and Windows compiler execution require Windows.'}
} finally {if(Test-Path -LiteralPath $Resources){Remove-Item -LiteralPath $Resources -Recurse -Force}}
