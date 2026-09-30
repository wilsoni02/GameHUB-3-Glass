# Windows PowerShell 5.1 compatible. Tests real data/state helpers with disposable
# files and lightweight control doubles; does not open WinForms or touch your data.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$tokens=$null;$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root '@Resources/Scripts/Manager.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors|Out-String)}
$helpers=@('Normalize-Tags','Read-IniSection','New-Game','Assert-LibrarySchema','Read-Library','Write-Library','Write-Status','Find-LibraryGames','Get-TargetIssue','Get-DisplayAccent','Get-SettingRules','Convert-SettingValue','Get-SettingsDocument','Read-ManagerSettings','Write-ManagerSettings','Read-SavedGameSnapshot','Get-LaunchIssue','Refresh-List','Discard-GameChanges','Invalidate-Diagnostics','Clear-ChangedDiagnostics','Start-Diagnostics','Step-Diagnostics','Update-DiagnosticHealth','Save-Current','Show-ManagerPage')
foreach($name in $helpers) {
    $fn=$ast.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
    if($null -eq $fn){throw ('Missing helper: '+$name)}
    . ([scriptblock]::Create($fn.Extent.Text))
}
function Assert-True([bool]$value,[string]$message){if(-not $value){throw $message}}
function Assert-Throws([scriptblock]$action,[string]$message){$rejected=$false;try{& $action|Out-Null}catch{$rejected=$true};Assert-True $rejected $message}
function Fake-Button {return [pscustomobject]@{Enabled=$false;Text=''}}
$Resources=Join-Path ([IO.Path]::GetTempPath()) ('GameHUBGlass-controls-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($Resources)|Out-Null
$script:libraryPath=Join-Path $Resources 'Library.ini'
$release=Read-IniSection (Join-Path $root '@Resources/Release.ini') 'Release';$script:librarySchema=[int]$release.LibrarySchema;$script:releaseLabel='GameHUB 3 (Liquid Glass) test';$RequestId='current-request'
$utf8=New-Object Text.UTF8Encoding($false)
$culture=[Threading.Thread]::CurrentThread.CurrentCulture
try {
    # Opening settings is read-only, including an absent file and old incomplete files.
    $read=Read-ManagerSettings
    Assert-True (-not $read.Document.Exists -and $read.Values.OpenMs -eq '260') 'Absent settings defaults failed'
    Assert-True (-not(Test-Path -LiteralPath $read.Document.Path)) 'Reading created Settings.ini'
    $original="; personal settings`r`n[Settings]`r`nWidth=3840`r`nHeight=2160`r`nX=-3840`r`nUIScale=1.1`r`nCustomKey=keep=this`r`n; retain comment`r`n[Other]`r`nOpenMs=88`r`nName=User " + [char]0x00E9 + "`r`n"
    [IO.File]::WriteAllText($read.Document.Path,$original,$utf8)
    [IO.File]::WriteAllText((Join-Path $Resources 'State.ini'),"[State]`nFavorites=keep`n",$utf8)
    [IO.File]::WriteAllText($script:libraryPath,"[Library]`nVersion=2`n[Game:one]`nName=Alpha`nPlatform=Steam`nTarget=steam://rungameid/42`nLaunch=steam://rungameid/42`n",$utf8)
    $libraryBefore=[IO.File]::ReadAllText($script:libraryPath);$stateBefore=[IO.File]::ReadAllText((Join-Path $Resources 'State.ini'))
    $read=Read-ManagerSettings
    Assert-True ([IO.File]::ReadAllText($read.Document.Path) -eq $original) 'Opening settings modified them'
    $values=$read.Values;$values.UIScale=1.25;$values.OpenMs=0;$values.CloseMs=2000;$values.FadeMs=75;$values.WheelStep=10;$values.ReduceMotion=1
    [Threading.Thread]::CurrentThread.CurrentCulture=[Globalization.CultureInfo]::GetCultureInfo('de-DE')
    $saved=Write-ManagerSettings $values $read.Document
    [Threading.Thread]::CurrentThread.CurrentCulture=$culture
    $raw=Read-IniSection $saved.Path 'Settings';$other=Read-IniSection $saved.Path 'Other'
    Assert-True ($raw.UIScale -eq '1.25' -and $raw.OpenMs -eq '0' -and $raw.WheelStep -eq '10' -and $raw.ReduceMotion -eq '1') 'Settings round trip or invariant culture failed'
    Assert-True ($raw.Width -eq '3840' -and $raw.X -eq '-3840' -and $raw.CustomKey -eq 'keep=this' -and $other.OpenMs -eq '88') 'Save damaged unexposed settings or other sections'
    Assert-True ($saved.Text.Contains('; retain comment') -and $saved.Text.Contains("`r`n")) 'Comments/newlines lost'
    Assert-True ([IO.File]::ReadAllText($saved.Path+'.bak') -eq $original) 'Settings backup was not the original file'
    Assert-True ([IO.File]::ReadAllText($script:libraryPath) -eq $libraryBefore -and [IO.File]::ReadAllText((Join-Path $Resources 'State.ini')) -eq $stateBefore) 'Settings save changed Library/State'
    $unchanged=Write-ManagerSettings $values $saved
    Assert-True ($unchanged.Fingerprint -eq $saved.Fingerprint -and [IO.File]::ReadAllText($saved.Path+'.bak') -eq $original) 'Unchanged save rewrote the backup'
    foreach($pair in @(@('UIScale','NaN'),@('UIScale','Infinity'),@('UIScale','0.69'),@('UIScale','1.51'),@('WheelStep','1.5'),@('OpenMs','-1'),@('FadeMs','2001'),@('ReduceMotion','2'),@('CloseMs',''),@('UIScale','1,2'))) {
        Assert-Throws {Convert-SettingValue $pair[0] $pair[1]} ('Invalid setting accepted: '+($pair -join '='))
    }
    [IO.File]::AppendAllText($saved.Path,"; external edit`r`n",$utf8)
    $external=[IO.File]::ReadAllText($saved.Path)
    Assert-Throws {Write-ManagerSettings $values $saved} 'External settings change was overwritten'
    Assert-True ([IO.File]::ReadAllText($saved.Path) -eq $external) 'Rejected save modified settings'
    [IO.File]::WriteAllText($saved.Path,"[Settings]`nOpenMs=bad`nUIScale=1.2 ; custom comment`n",$utf8)
    $bad=Read-ManagerSettings;Assert-True ($bad.Problems.Count -eq 2 -and $bad.Values.OpenMs -eq '260') 'Malformed settings not reported'
    $repair=Write-ManagerSettings $bad.Values $bad.Document;Assert-True ($repair.Text.Contains('; custom comment')) 'Inline comment was discarded'
    foreach($encoding in @((New-Object Text.UTF8Encoding($true)),[Text.Encoding]::Unicode,[Text.Encoding]::BigEndianUnicode,[Text.Encoding]::UTF32)) {
        [IO.File]::WriteAllText($saved.Path,$original,$encoding)
        $doc=Read-ManagerSettings;$result=Write-ManagerSettings $values $doc.Document
        $bytes=[IO.File]::ReadAllBytes($saved.Path);$preamble=$encoding.GetPreamble()
        Assert-True ([BitConverter]::ToString($bytes,0,$preamble.Length) -eq [BitConverter]::ToString($preamble)) 'Encoding preamble changed'
        Assert-True ($result.Text.Contains('Name=User '+[char]0x00E9)) 'Unicode settings text changed'
    }
    [IO.File]::WriteAllText($saved.Path,"[Settings]`nOpenMs=1`n[Settings]`nOpenMs=2`n",$utf8)
    $duplicate=Get-SettingsDocument;Assert-Throws {Write-ManagerSettings $values $duplicate} 'Duplicate Settings sections accepted'
    Assert-True ((Get-SettingsDocument).Fingerprint -eq $duplicate.Fingerprint) 'Rejected duplicate sections changed the file'
    [IO.File]::Delete($saved.Path);$absent=Get-SettingsDocument;$createdSettings=Write-ManagerSettings $values $absent
    Assert-True ($createdSettings.Exists -and (Read-ManagerSettings).Values.FadeMs -eq '75') 'Creating absent settings failed'
    Assert-True (@(Get-ChildItem -LiteralPath $Resources -Filter '*.new').Count -eq 0) 'Temporary settings file left behind'

    # Literal/case-insensitive search; validation does not launch anything.
    $a=New-Game 'a';$a.Name='Alpha [test]';$a.Platform='Steam';$a.Target='steam://rungameid/42';$a.Launch=$a.Target
    $b=New-Game 'b';$b.Name='Beta';$b.Platform='Epic';$b.Target='com.epicgames.launcher://apps/example?action=launch'
    Assert-True (@(Find-LibraryGames @($a,$b) 'steam').Count -eq 1) 'Platform search failed'
    Assert-True (@(Find-LibraryGames @($a,$b) 'ALPHA').Count -eq 1) 'Case-insensitive title search failed'
    Assert-True (@(Find-LibraryGames @($a,$b) '[test]').Count -eq 1) 'Search treated punctuation as a regex'
    Assert-True (@(Find-LibraryGames @($a,$b) 'rungameid/42').Count -eq 1) 'Target search failed'
    Assert-True (@(Find-LibraryGames @($a,$b) 'zzz').Count -eq 0) 'Empty results failed'
    foreach($valid in @('42',$a.Target,$b.Target)){Assert-True (-not(Get-TargetIssue $valid)) ('Valid target rejected: '+$valid)}
    foreach($invalid in @('','steam://','steam://bad value','"game.exe"',(Join-Path $Resources 'absent.exe'))){Assert-True ([bool](Get-TargetIssue $invalid)) ('Invalid target accepted: '+$invalid)}
    $exe=Join-Path $Resources 'fixture.exe';[IO.File]::WriteAllText($exe,'not executed',$utf8)
    Assert-True (-not(Get-TargetIssue $exe $Resources)) 'Existing EXE path rejected'
    Assert-True ([bool](Get-TargetIssue $exe (Join-Path $Resources 'absent'))) 'Missing working directory accepted'
    $a.Launch='Shortcuts/missing.lnk';Assert-True ([bool](Get-LaunchIssue $a)) 'Missing generated shortcut was missed';$a.Launch=$a.Target
    Assert-True ((Get-DisplayAccent '') -eq '209,250,239' -and (Get-DisplayAccent '999,0,0') -eq '209,250,239' -and (Get-DisplayAccent '100,150,210') -eq '100,150,210') 'Accent reset/fallback differs'

    # Search keeps the current editor/draft even when hidden by the results.
    $script:games=New-Object 'System.Collections.Generic.List[object]';$script:games.Add($a);$script:games.Add($b);$script:current=$a
    $script:dirty=$true;$script:newGameId='';$script:shownCount=0;$script:presentationCount=0
    $searchBox=[pscustomobject]@{Text='Epic'};$listCount=[pscustomobject]@{Text=''}
    $list=[pscustomobject]@{Items=(New-Object Collections.ArrayList);SelectedIndex=-1}
    $list|Add-Member ScriptMethod BeginUpdate {return};$list|Add-Member ScriptMethod EndUpdate {return}
    $list|Add-Member ScriptProperty SelectedItem {if($this.SelectedIndex -ge 0){$this.Items[$this.SelectedIndex]}else{$null}}
    function Update-GamePresentation {$script:presentationCount++}
    function Show-Game($game){$script:current=$game;$script:shownCount++;$script:dirty=$false}
    Refresh-List 'a' $true
    Assert-True ($script:current.Id -eq 'a' -and $script:dirty -and $list.Items.Count -eq 1 -and $list.SelectedIndex -eq -1 -and $script:shownCount -eq 0) 'Search discarded or switched the dirty editor'
    $searchBox.Text='';Refresh-List 'a' $true;Assert-True ($list.SelectedItem.Id -eq 'a' -and $script:dirty) 'Clearing search lost selection/draft'
    $new=New-Game 'draft';$script:games.Add($new);$script:current=$new;$script:newGameId='draft';$script:dirty=$true
    Discard-GameChanges
    Assert-True ($script:games.Count -eq 2 -and -not $script:newGameId -and -not $script:dirty) 'Discard left a ghost new entry'
    $searchBox.Text='nothing';Refresh-List 'b';Assert-True ($searchBox.Text -eq '' -and $script:current.Id -eq 'b') 'Opening a filtered-out game failed'

    # A metadata-only save can reset Accent without touching the artwork pipeline.
    $script:games.Clear();$a.Accent='100,150,210';$script:games.Add($a);$script:current=$a
    $nameBox=[pscustomobject]@{Text=$a.Name};$targetBox=[pscustomobject]@{Text=$a.Target};$argsBox=[pscustomobject]@{Text=''};$workingBox=[pscustomobject]@{Text=''};$tagsBox=[pscustomobject]@{Text="Co-op, Tester's picks"};$platformBox=[pscustomobject]@{SelectedItem='Steam'}
    $saveButton=Fake-Button;$status=Fake-Button;$script:resetAccent=$true;$script:coverChanged=$false;$script:backgroundChanged=$false
    function Store-Art {throw 'Metadata-only save unexpectedly processed artwork'}
    Save-Current
    Assert-True ($script:games[0].Tags -eq "Co-op, Tester's picks") 'Save game failed to save tags'
    Assert-True ($script:games[0].Accent -eq '' -and $script:games[0].Cover -eq $a.Cover -and (Read-IniSection $script:libraryPath 'Game:a').Accent -eq '') 'Accent reset was not safely saved'
    Assert-True ([IO.File]::ReadAllText($script:libraryPath+'.bak') -eq $libraryBefore) 'Game save lost the existing library backup behavior'

    # Diagnostics read saved disk data, not a new/edited in-memory draft.
    $snapshot=Read-SavedGameSnapshot;$script:games[0].Name='unsaved name';$script:games.Add((New-Game 'unsaved'))
    $savedSnapshot=Read-SavedGameSnapshot
    Assert-True ($savedSnapshot.Games.Count -eq 1 -and $savedSnapshot.Games[0].Name -ne 'unsaved name') 'Diagnostics mixed unsaved drafts into its snapshot'
    $diagTimer=[pscustomobject]@{Running=$false};$diagTimer|Add-Member ScriptMethod Start {$this.Running=$true};$diagTimer|Add-Member ScriptMethod Stop {$this.Running=$false}
    $diagnosticsList=[pscustomobject]@{Items=(New-Object Collections.ArrayList)};$diagnosticState=Fake-Button;$runChecks=Fake-Button;$cancelChecks=Fake-Button;$openIssue=Fake-Button
    $healthLabel=Fake-Button;$logDetails=Fake-Button;$logButton=Fake-Button;$diagnosticButton=Fake-Button;$statusButton=Fake-Button
    $script:windowReady=$true;$created=$true;$script:sessionStarted=Get-Date
    [IO.File]::WriteAllText((Join-Path $Resources 'Manager.log'),'GH_ERROR historical failure',$utf8)
    [IO.File]::SetLastWriteTime((Join-Path $Resources 'Manager.log'),(Get-Date).AddDays(-20))
    Write-Status 'ready';Update-DiagnosticHealth
    Assert-True ($healthLabel.Text.Contains('window is ready') -and $healthLabel.Text.Contains('current request') -and -not $healthLabel.Text.Contains('historical failure') -and $logDetails.Text.Contains('history')) 'Old logs were treated as current health'
    [IO.File]::WriteAllText((Join-Path $Resources 'Manager-status.ini'),"[Manager]`nRequestId=old`nStatus=error`n",$utf8)
    Update-DiagnosticHealth;Assert-True ($healthLabel.Text.Contains('does not match') -and -not $healthLabel.Text.Contains('coordination: error')) 'Mismatched status was shown as current'
    function Add-DiagnosticRow($level,$game,$kind,$message){$diagnosticsList.Items.Add(@{Level=$level;Kind=$kind;Message=$message})|Out-Null}
    $script:artChecks=0
    function Get-CachedArtIssue($relative){$script:artChecks++;return $null}
    Start-Diagnostics
    Assert-True ($diagTimer.Running -and $script:diagnosticQueue.Count -eq 4 -and $script:artChecks -eq 0) 'Diagnostics did work at startup or included drafts'
    Step-Diagnostics;Assert-True ($script:diagnosticIndex -eq 1 -and $script:artChecks -eq 0) 'Scan did more than one job per tick'
    for($i=0;$i -lt 4;$i++){Step-Diagnostics}
    Assert-True (-not $diagTimer.Running -and $script:artChecks -eq 3 -and $diagnosticState.Text.Contains('Completed')) 'On-demand scan did not stop'
    [IO.File]::AppendAllText($script:libraryPath,"`n; external library change",$utf8);Clear-ChangedDiagnostics
    Assert-True ($null -eq $script:diagnosticSnapshot -and $diagnosticsList.Items.Count -eq 0 -and $diagnosticState.Text.Contains('Library changed')) 'Stale scan results survived a library change'
    [IO.File]::AppendAllText($script:libraryPath,"`n[Game:a]`nName=Duplicate`n",$utf8)
    Assert-Throws {Read-SavedGameSnapshot} 'Duplicate game IDs were not reported'
    # WinForms Visible is effectively false before the parent form is shown.
    # Page routing must use the requested name, not that getter's effective value.
    function Hidden-Page {
        $page=[pscustomobject]@{RequestedVisible=$false;FrontCount=0}
        $page|Add-Member ScriptProperty Visible {$false} {$this.RequestedVisible=$args[0]}
        $page|Add-Member ScriptMethod BringToFront {$this.FrontCount++}
        return $page
    }
    $split=Hidden-Page;$libraryPage=Hidden-Page;$appearancePage=Hidden-Page;$settingsPage=Hidden-Page;$diagnosticsPage=Hidden-Page;$navButtons=@{}
    $script:healthReads=0
    function Update-DiagnosticHealth {$script:healthReads++}
    Show-ManagerPage 'Library'
    Assert-True ($split.RequestedVisible -and $libraryPage.RequestedVisible -and -not $appearancePage.RequestedVisible -and $libraryPage.FrontCount -eq 1 -and $script:healthReads -eq 0) 'Initial Library page depended on effective visibility'
    Show-ManagerPage 'Appearance'
    Assert-True ($appearancePage.RequestedVisible -and -not $libraryPage.RequestedVisible -and $appearancePage.FrontCount -eq 1) 'Appearance routing failed'
    Show-ManagerPage 'Settings';Assert-True ($settingsPage.FrontCount -eq 1 -and -not $split.RequestedVisible) 'Settings routing failed'
    Show-ManagerPage 'Diagnostics';Assert-True ($diagnosticsPage.FrontCount -eq 1 -and $script:healthReads -eq 1) 'Diagnostics ran before it was requested'
    Write-Output 'PASS: settings validation/preservation/backups/conflict guard, search/draft retention, discard, accent reset, saved-library diagnostics, current-request health, on-demand scan lifetime, and initial page routing'
} finally {
    [Threading.Thread]::CurrentThread.CurrentCulture=$culture
    if(Test-Path -LiteralPath $Resources){Remove-Item -LiteralPath $Resources -Recurse -Force}
}
