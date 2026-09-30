# Run in Windows PowerShell 5.1. No policy changes; no real library writes or GUI.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$path=Join-Path $root '@Resources/Scripts/Manager.ps1'
$tokens=$null;$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if($errors.Count -gt 0){throw ($errors | Out-String)}
$helpers=@('Normalize-Tags','Read-IniSection','Assert-LibrarySchema','New-Game','Read-Library','Write-Library','Write-Status')
foreach($name in $helpers) {
    $fn=$ast.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
    if($null -eq $fn){throw ('Missing helper: '+$name)}
    . ([scriptblock]::Create($fn.Extent.Text))
}
function Assert-True([bool]$test,[string]$message){if(-not $test){throw $message}}
$release=Read-IniSection (Join-Path $root '@Resources/Release.ini') 'Release'
$script:librarySchema=[int]$release.LibrarySchema
$script:releaseLabel='GameHUB 3 (Liquid Glass) '+$release.Version+' (build '+$release.Build+')'
$Resources=Join-Path ([IO.Path]::GetTempPath()) ('GameHUBGlass-schema-test-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($Resources)|Out-Null
$script:libraryPath=Join-Path $Resources 'Library.ini'
$encoding=New-Object Text.UTF8Encoding($false)
try {
    $RequestId='schema-test-request'
    Write-Status 'starting';Write-Status 'ready'
    $status=Read-IniSection (Join-Path $Resources 'Manager-status.ini') 'Manager'
    Assert-True ($status.RequestId -eq $RequestId -and $status.Status -eq 'ready') 'Startup status payload changed'
    Assert-True (-not(Test-Path -LiteralPath ((Join-Path $Resources 'Manager-status.ini')+'.new'))) 'Status temporary file left behind'

    # Unicode, embedded equals/quotes, favorite-independent IDs, and ordering.
    $title='Game '+[char]0x00E9+' = "test"'
    $original="[Library]`nVersion=1`n`n[Game:test_game]`nName=$title`nTarget=steam://rungameid/42`nOrder=1`n"
    [IO.File]::WriteAllText($script:libraryPath,$original,$encoding)
    $script:games=New-Object 'System.Collections.Generic.List[object]'
    Read-Library
    Assert-True ($script:games.Count -eq 1 -and $script:games[0].Name -eq $title) 'Library read failed'
    Assert-True ($script:games[0].Accent -eq '' -and $script:games[0].CoverFocalX -eq '0.5' -and $script:games[0].BackgroundZoom -eq '1') 'Legacy artwork defaults changed'
    Assert-True ([IO.File]::ReadAllText($script:libraryPath) -eq $original) 'Reading a legacy library rewrote it'
    Assert-True ($script:games[0].Tags -eq '') 'Legacy Tags should be empty'
    $script:games[0].Tags=Normalize-Tags " Co-op, RPG, co-op, Tester's picks, , RPG "
    Assert-True ($script:games[0].Tags -eq "Co-op, RPG, Tester's picks") 'Tag normalization changed order/text'
    $rejected=$false;try{Normalize-Tags "bad`nline"}catch{$rejected=$true}
    Assert-True $rejected 'Multiline tag accepted'
    Write-Library
    Assert-True ([IO.File]::ReadAllText($script:libraryPath+'.bak') -eq $original) 'Previous library backup was not preserved'
    $script:games.Clear();Read-Library
    Assert-True ($script:games[0].Id -eq 'test_game' -and $script:games[0].Name -eq $title) 'Library round trip changed identity or text'
    Assert-True ($script:games[0].Tags -eq "Co-op, RPG, Tester's picks") 'Tags failed to round trip'
    $schema=$script:librarySchema;$script:librarySchema=2
    $before=[IO.File]::ReadAllText($script:libraryPath);$backupBefore=[IO.File]::ReadAllText($script:libraryPath+'.bak')
    $rejected=$false;try{Write-Library}catch{$rejected=$true}
    Assert-True ($rejected -and [IO.File]::ReadAllText($script:libraryPath) -eq $before -and [IO.File]::ReadAllText($script:libraryPath+'.bak') -eq $backupBefore) 'Older writer did not protect tags'
    $script:librarySchema=$schema
    $metadata=Read-IniSection $script:libraryPath 'Library'
    Assert-True ($metadata.Version -eq [string]$script:librarySchema) 'Schema stamp differs from supported schema'
    $g=$script:games[0];$g.Accent='112,168,222';$g.CoverFocalX='0.125';$g.CoverFocalY='0.85';$g.CoverZoom='2.1'
    $g.BackgroundFocalX='0.95';$g.BackgroundFocalY='0';$g.BackgroundZoom='3'
    Write-Library;$script:games.Clear();Read-Library;$g=$script:games[0]
    Assert-True ($g.Accent -eq '112,168,222' -and $g.CoverFocalX -eq '0.125' -and $g.CoverFocalY -eq '0.85' -and $g.CoverZoom -eq '2.1') 'Cover/accent fields did not round-trip'
    Assert-True ($g.BackgroundFocalX -eq '0.95' -and $g.BackgroundFocalY -eq '0' -and $g.BackgroundZoom -eq '3') 'Background framing did not round-trip'

    $g.PreviewVideo="Art/Previews/Tester's [clip] = test.mp4";$g.PreviewStart='1.5';$g.PreviewEnd='8';$g.Logo='Art/Logos/test.png'
    Write-Library;$script:games.Clear();Read-Library;$g=$script:games[0]
    Assert-True ($g.PreviewVideo -eq "Art/Previews/Tester's [clip] = test.mp4" -and $g.PreviewStart -eq '1.5' -and $g.PreviewEnd -eq '8' -and $g.Logo -eq 'Art/Logos/test.png') 'Motion fields failed to round-trip'
    $schema=$script:librarySchema;$script:librarySchema=3
    $before=[IO.File]::ReadAllText($script:libraryPath);$rejected=$false
    try{Write-Library}catch{$rejected=$true}
    Assert-True ($rejected -and [IO.File]::ReadAllText($script:libraryPath) -eq $before) 'Legacy writer dropped motion fields'
    $script:librarySchema=$schema
    $legacy3=$original.Replace('Version=1','Version=3')
    [IO.File]::WriteAllText($script:libraryPath,$legacy3,$encoding);$script:games.Clear();Read-Library
    Assert-True ($script:games[0].PreviewVideo -eq '' -and $script:games[0].Logo -eq '' -and [IO.File]::ReadAllText($script:libraryPath) -eq $legacy3) 'Schema 3 did not load unchanged'

    # Legacy schema omission must still open without an automatic rewrite.
    $legacy=$original.Replace("Version=1`n",'')
    [IO.File]::WriteAllText($script:libraryPath,$legacy,$encoding)
    $script:games.Clear();Read-Library
    Assert-True ([IO.File]::ReadAllText($script:libraryPath) -eq $legacy) 'Read migrated a legacy file'

    $legacy2=$original.Replace('Version=1','Version=2')
    [IO.File]::WriteAllText($script:libraryPath,$legacy2,$encoding);$script:games.Clear();Read-Library
    Assert-True ($script:games[0].Tags -eq '' -and [IO.File]::ReadAllText($script:libraryPath) -eq $legacy2) 'Schema 2 mutated on read'
    foreach($badVersion in @('5','0','-1','2.5','invalid','')) {
        $unsupported=$original.Replace('Version=1',('Version='+$badVersion))
        [IO.File]::WriteAllText($script:libraryPath,$unsupported,$encoding)
        $backupBefore=[IO.File]::ReadAllText($script:libraryPath+'.bak')
        $readRejected=$false;$writeRejected=$false
        try{Read-Library}catch{$readRejected=$true}
        try{Write-Library}catch{$writeRejected=$true}
        Assert-True ($readRejected -and $writeRejected) ('Unsupported schema accepted: '+$badVersion)
        Assert-True ([IO.File]::ReadAllText($script:libraryPath) -eq $unsupported) 'Rejected save modified the library'
        Assert-True ([IO.File]::ReadAllText($script:libraryPath+'.bak') -eq $backupBefore) 'Rejected save modified the backup'
        Assert-True (-not(Test-Path -LiteralPath ($script:libraryPath+'.new'))) 'Rejected save created a temporary library'
    }
    Write-Output ($script:releaseLabel+': PASS - parser, library schema/round trip, backup, and startup status helpers')
} finally {
    if(Test-Path -LiteralPath $Resources){Remove-Item -LiteralPath $Resources -Recurse -Force}
}
