# Optional local-only media helper. Silent UI fallback; current failures go to diagnostics.
param([Parameter(Mandatory=$true)][string]$Resources,
      [string]$RainmeterExe='',
      [string]$SkinIni='',
      [string]$Config='',
      [switch]$ValidateOnly)
$ErrorActionPreference='Stop'
$mutex=$null;$owned=$false;$stage='startup'
function Write-MotionStartupStatus([string]$phase,[string]$detail,[string]$failure='') {
    try {
        $session='';$token='';$command=Join-Path $Resources 'Motion-command.ini'
        if(Test-Path -LiteralPath $command) {
            foreach($line in [IO.File]::ReadAllLines($command,[Text.Encoding]::UTF8)) {
                if($line -match '^Session=(\d{1,40})$'){$session=$Matches[1]}
                if($line -match '^Token=(\d{1,20})$'){$token=$Matches[1]}
            }
        }
        $lines=@('[Motion]',('Utc='+[DateTime]::UtcNow.ToString('o')),('Session='+$session),('Token='+$token),
            ('Phase='+$phase),('Detail='+($detail -replace '[\r\n]+',' ')),('LastError='+($failure -replace '[\r\n]+',' ')))
        $path=Join-Path $Resources 'Motion-status.ini';$temp=$path+'.new'
        [IO.File]::WriteAllLines($temp,[string[]]$lines,(New-Object Text.UTF8Encoding($false)))
        if([IO.File]::Exists($path)){[IO.File]::Replace($temp,$path,[NullString]::Value)}else{[IO.File]::Move($temp,$path)}
    } catch { } # Diagnostics never prevent the static launcher from working.
}
function Get-MotionReferences {
    $names=@('System','System.Core','System.Drawing','System.Windows.Forms','WindowsBase','PresentationCore','PresentationFramework','WindowsFormsIntegration','System.Xaml')
    foreach($name in $names){Add-Type -AssemblyName $name}
    $loaded=[AppDomain]::CurrentDomain.GetAssemblies()
    foreach($name in $names) {
        $assembly=@($loaded | Where-Object {-not $_.IsDynamic -and $_.GetName().Name -eq $name}) | Select-Object -First 1
        if(-not $assembly -or -not [IO.Path]::IsPathRooted($assembly.Location) -or -not [IO.File]::Exists($assembly.Location)) {
            throw ('Cannot locate the installed Windows assembly: '+$name)
        }
        # Windows PowerShell passes *.dll basenames directly to csc, which does not
        # search the WPF/GAC directories. Runtime loading alone is not a compiler reference.
        $assembly.Location
    }
}
try {
    $Resources=[IO.Path]::GetFullPath($Resources)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$key=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Resources.ToLowerInvariant())))).Replace('-','')}finally{$sha.Dispose()}
    $mutex=New-Object Threading.Mutex($true,('Local\GameHUBMotion_'+$key),[ref]$owned)
    if(-not $owned){[Console]::Error.WriteLine('The media helper is already running. Unload Main before retrying.');return}
    Write-MotionStartupStatus 'starting' 'Loading installed Windows media components.'
    $stage='loading Windows assemblies';$references=@(Get-MotionReferences)
    $stage='compiling media helper'
    Write-MotionStartupStatus 'compiling' 'Compiling against the resolved Windows assembly paths.'
    Add-Type -LiteralPath (Join-Path $Resources 'Scripts/MotionHost.cs') -ReferencedAssemblies $references
    if($ValidateOnly){Write-MotionStartupStatus 'validated' 'Windows helper compilation passed; playback has not been tested.';Write-Output 'PASS: Windows media helper compiled.';return}
    $stage='attaching to Rainmeter'
    [GameHUBMotion.Host]::Run($Resources,$RainmeterExe,$SkinIni,$Config)
} catch {
    $failure=$_.Exception.ToString()
    Write-MotionStartupStatus 'error' ('Failed while '+$stage+'. Static Hero remains available.') $failure
    [Console]::Error.WriteLine(('Motion helper failed while '+$stage+': '+($_|Out-String)))
} finally {
    if($owned -and $mutex){$mutex.ReleaseMutex()}
    if($mutex){$mutex.Dispose()}
}
