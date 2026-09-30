# Run with Windows PowerShell 5.1. Uses only disposable files; no manager window,
# real library changes, game launches, Steam access, or execution-policy changes.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$root=Split-Path -Parent $PSScriptRoot
$tokens=$null;$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root '@Resources/Scripts/Manager.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count -gt 0){throw ($errors|Out-String)}
$helpers=@('Normalize-Tags','Read-IniSection','New-Game','Assert-LibrarySchema','Read-Library','Write-Library','Frame-Number','Get-ArtFrame','Get-CropRectangle','New-CroppedBitmap','Get-ArtAccent','Save-Bitmap','Store-Art','Usable-Art','Get-CachedArtIssue','Get-TargetIssue','Save-Current')
foreach($name in $helpers) {
    $fn=$ast.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
    if($null -eq $fn){throw ('Missing helper: '+$name)}
    . ([scriptblock]::Create($fn.Extent.Text))
}
function Assert-True([bool]$condition,[string]$message){if(-not $condition){throw $message}}
function Near([double]$a,[double]$b,[double]$epsilon=0.02){return [Math]::Abs($a-$b) -lt $epsilon}
function Files-Snapshot {
    $result=@{}
    foreach($p in Get-ChildItem -LiteralPath $Resources -File -Recurse){$result[$p.FullName]=(Get-FileHash -LiteralPath $p.FullName -Algorithm SHA256).Hash}
    return $result
}
function Assert-SameFiles($before) {
    $after=Files-Snapshot
    Assert-True ($before.Count -eq $after.Count) 'Failed save left new or missing files'
    foreach($key in $before.Keys){Assert-True ($before[$key] -eq $after[$key]) ('Failed save changed '+$key)}
}
function Refresh-List([string]$id){$script:current=@($script:games|Where-Object Id -eq $id)[0]}
function Check-Size([string]$relative,[int]$width,[int]$height) {
    $image=[Drawing.Image]::FromFile((Join-Path $Resources $relative))
    try{Assert-True ($image.Width -eq $width -and $image.Height -eq $height) ('Unexpected cache size: '+$relative)}finally{$image.Dispose()}
}
function Solid-Accent([Drawing.Color]$color) {
    $bmp=New-Object Drawing.Bitmap(96,54,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $gr=[Drawing.Graphics]::FromImage($bmp)
    try{$gr.Clear($color);return (Get-ArtAccent $bmp)}finally{$gr.Dispose();$bmp.Dispose()}
}
$Resources=Join-Path ([IO.Path]::GetTempPath()) ('GameHUBGlass-art-test-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($Resources)|Out-Null
$script:libraryPath=Join-Path $Resources 'Library.ini'
$encoding=New-Object Text.UTF8Encoding($false)
$release=Read-IniSection (Join-Path $root '@Resources/Release.ini') 'Release'
$script:librarySchema=[int]$release.LibrarySchema;$script:releaseLabel='GameHUB Glass '+$release.Version
$culture=[Threading.Thread]::CurrentThread.CurrentCulture
try {
    # Legacy defaults, malformed values, and locale-independent numeric metadata.
    $g=New-Game 'fixture';$frame=Get-ArtFrame $g 'Cover'
    Assert-True ($frame.X -eq 0.5 -and $frame.Y -eq 0.5 -and $frame.Zoom -eq 1) 'Default framing changed'
    foreach($bad in @('NaN','Infinity','-Infinity','bad','')){Assert-True ((Frame-Number $bad 0.5 0 1) -eq 0.5) ('Invalid framing accepted: '+$bad)}
    Assert-True ((Frame-Number '-4' 0.5 0 1) -eq 0 -and (Frame-Number '9' 1 1 3) -eq 3) 'Framing bounds not clamped'
    [Threading.Thread]::CurrentThread.CurrentCulture=[Globalization.CultureInfo]::GetCultureInfo('de-DE')
    Assert-True ((Frame-Number '0.125' 0.5 0 1) -eq 0.125) 'Decimal metadata depends on Windows locale'
    [Threading.Thread]::CurrentThread.CurrentCulture=$culture
    foreach($size in @(@(300,100),@(100,300),@(3840,2160),@(1,1),@(9999,99))) {
        foreach($x in @(0,0.5,1)){foreach($y in @(0,0.5,1)){foreach($zoom in @(1,1.5,3)) {
            $f=[pscustomobject]@{X=$x;Y=$y;Zoom=$zoom}
            $crop=Get-CropRectangle $size[0] $size[1] 960 540 $f
            Assert-True ($crop.X -ge 0 -and $crop.Y -ge 0 -and $crop.Right -le $size[0]+0.02 -and $crop.Bottom -le $size[1]+0.02) 'Crop escaped the source'
            Assert-True ((Near ($crop.Width/$crop.Height) (16.0/9)) -and $crop.Width -gt 0) 'Crop has invalid aspect or size'
            foreach($out in @(@(3840,2160),@(80,45),@(480,270))) {
                $same=Get-CropRectangle $size[0] $size[1] $out[0] $out[1] $f
                Assert-True ((Near $same.X $crop.X) -and (Near $same.Y $crop.Y) -and (Near $same.Width $crop.Width) -and (Near $same.Height $crop.Height)) 'Preview/background/frost use different crops'
            }
        }}}
    }
    # Black, white, gray and transparent art use the existing mint accent.
    foreach($color in @([Drawing.Color]::Black,[Drawing.Color]::White,[Drawing.Color]::Gray,[Drawing.Color]::FromArgb(0,255,0,0))) {
        Assert-True ((Solid-Accent $color) -eq '209,250,239') 'Nonrepresentative art produced an accent'
    }
    foreach($color in @([Drawing.Color]::Red,[Drawing.Color]::Lime,[Drawing.Color]::FromArgb(30,90,210))) {
        $accent=Solid-Accent $color;$parts=@($accent.Split(',')|ForEach-Object {[int]$_})
        Assert-True ($accent -ne '209,250,239' -and $parts.Count -eq 3) 'Useful artwork color was lost'
        $safe=[Drawing.Color]::FromArgb($parts[0],$parts[1],$parts[2])
        Assert-True ($safe.GetSaturation() -le 0.64 -and $safe.GetBrightness() -ge 0.61 -and $safe.GetBrightness() -le 0.71) 'Accent is too dark/bright/saturated'
        Assert-True ((Solid-Accent $color) -eq $accent) 'Accent selection is nondeterministic'
    }
    # Synthetic off-center landmarks: exact left/right and top/bottom framing.
    $wide=Join-Path $Resources 'wide.png';$tall=Join-Path $Resources 'tall.png'
    foreach($vertical in @($false,$true)) {
        $w=if($vertical){100}else{300};$h=if($vertical){300}else{100}
        $bmp=New-Object Drawing.Bitmap($w,$h);$gr=[Drawing.Graphics]::FromImage($bmp)
        try {
            $brushes=@([Drawing.Brushes]::Red,[Drawing.Brushes]::Lime,[Drawing.Brushes]::Blue)
            for($i=0;$i -lt 3;$i++){if($vertical){$gr.FillRectangle($brushes[$i],0,($i*100),100,100)}else{$gr.FillRectangle($brushes[$i],($i*100),0,100,100)}}
            $path=if($vertical){$tall}else{$wide};$bmp.Save($path,[Drawing.Imaging.ImageFormat]::Png)
        } finally {$gr.Dispose();$bmp.Dispose()}
        foreach($position in @(0,1)) {
            $f=[pscustomobject]@{X=$position;Y=$position;Zoom=1}
            $crop=New-CroppedBitmap $path 160 90 $true $f
            try {
                $pixel=$crop.GetPixel(80,45)
                Assert-True (($position -eq 0 -and $pixel.R -gt 240) -or ($position -eq 1 -and $pixel.B -gt 240)) 'Focal position missed the landmark'
                Assert-True ($crop.GetPixel(0,0).A -eq 0) 'Cover rounding lost transparency'
            } finally {$crop.Dispose()}
        }
    }
    $left=[pscustomobject]@{X=0;Y=0;Zoom=1.0};$right=[pscustomobject]@{X=1;Y=1;Zoom=2.0}
    # Both callers (manual save and Steam import) use Store-Art; omitted framing
    # must produce the same defaults as an explicit reset.
    Store-Art $g 'Cover' $wide
    $firstCover=$g.Cover;$firstOriginal=$g.CoverSource;$firstHash=(Get-FileHash (Join-Path $Resources $firstCover)).Hash
    $default=New-Game 'default';Store-Art $default 'Cover' $wide ([pscustomobject]@{X=0.5;Y=0.5;Zoom=1.0})
    Assert-True ((Get-FileHash (Join-Path $Resources $default.Cover)).Hash -eq $firstHash -and $default.Accent -eq $g.Accent) 'Imported/manual default pipelines differ'
    Store-Art $g 'Cover' (Join-Path $Resources $firstOriginal) $left
    Store-Art $g 'Background' $wide $right
    Check-Size $g.Cover 960 540;Check-Size $g.Background 3840 2160;Check-Size $g.Blur 1280 720
    Assert-True ($g.Cover -ne $firstCover -and (Get-FileHash (Join-Path $Resources $firstCover)).Hash -eq $firstHash) 'Reframing overwrote old artwork'
    Assert-True ($g.CoverFocalX -eq '0' -and $g.BackgroundFocalX -eq '1' -and $g.BackgroundZoom -eq '2') 'Framing metadata not stored'
    # A color present in both caches confirms the frost follows the focal crop.
    foreach($relative in @($g.Background,$g.Blur)) {
        $image=New-Object Drawing.Bitmap((Join-Path $Resources $relative))
        try{$p=$image.GetPixel([int]($image.Width/2),[int]($image.Height/2));Assert-True ($p.B -gt 230 -and $p.R -lt 25) 'Background and frost landmarks differ'}finally{$image.Dispose()}
    }
    $invalid=Join-Path $Resources 'broken.jpg';[IO.File]::WriteAllText($invalid,'This is not a JPEG.',$encoding)
    $before=Files-Snapshot;$oldMetadata=$g|ConvertTo-Json -Compress
    $rejected=$false;try{Store-Art $g 'Cover' $invalid}catch{$rejected=$true}
    Assert-True ($rejected -and ($g|ConvertTo-Json -Compress) -eq $oldMetadata) 'Malformed image changed game metadata'
    Assert-SameFiles $before
    # Inject failure after the main background has encoded, while frost is saved.
    $script:realSaveBitmap=${function:Save-Bitmap}
    function Save-Bitmap($bitmap,[string]$destination,[bool]$png=$false) {
        if($destination -match '[\\/]Blur[\\/]'){throw 'Injected frost save failure'}
        & $script:realSaveBitmap $bitmap $destination $png
    }
    try {
        $rejected=$false;try{Store-Art $g 'Background' $wide $left}catch{$rejected=$true}
        Assert-True ($rejected -and ($g|ConvertTo-Json -Compress) -eq $oldMetadata) 'Failed encoding published partial metadata'
        Assert-SameFiles $before
    } finally {Set-Item -Path Function:\Save-Bitmap -Value $script:realSaveBitmap}
    # Save-Current stages both kinds. A bad second image must roll back the first.
    $original="[Library]`nVersion=1`n[Game:fixture]`nName=Old title`nTarget=steam://rungameid/42`nOrder=1`n"
    [IO.File]::WriteAllText($script:libraryPath,$original,$encoding)
    foreach($name in @('State.ini','Settings.ini')){[IO.File]::WriteAllText((Join-Path $Resources $name),'user data',$encoding)}
    $script:games=New-Object 'System.Collections.Generic.List[object]';Read-Library;$script:current=$script:games[0]
    $nameBox=[pscustomobject]@{Text='New title'};$targetBox=[pscustomobject]@{Text='steam://rungameid/42'};$platformBox=[pscustomobject]@{SelectedItem='Steam'}
    $argsBox=[pscustomobject]@{Text=''};$workingBox=[pscustomobject]@{Text=''};$tagsBox=[pscustomobject]@{Text="Co-op, Tester's picks"};$saveButton=[pscustomobject]@{Text=''};$status=[pscustomobject]@{Text=''}
    $script:coverInput=$wide;$script:backgroundInput=$invalid;$script:coverChanged=$true;$script:backgroundChanged=$true
    $script:coverFrame=$left;$script:backgroundFrame=$right;$before=Files-Snapshot
    $rejected=$false;try{Save-Current}catch{$rejected=$true}
    Assert-True ($rejected -and $script:games[0].Name -eq 'Old title' -and $script:games[0].Accent -eq '') 'Failed save mutated the live entry'
    Assert-SameFiles $before
    $script:backgroundInput=$wide;Save-Current
    Assert-True ((Read-IniSection $script:libraryPath 'Library').Version -eq [string]$script:librarySchema) 'Explicit save did not upgrade schema'
    Assert-True ([IO.File]::ReadAllText($script:libraryPath+'.bak') -eq $original) 'Original library backup lost'
    Assert-True ($script:current.Name -eq 'New title' -and $script:current.Accent -ne '' -and $script:current.BackgroundZoom -eq '2') 'Successful save omitted artwork metadata'
    # Locale-independent stored values and no reprocessing on a title-only save.
    $artBefore=@((Get-ChildItem -LiteralPath (Join-Path $Resources 'Art') -Recurse -File).FullName)
    $accentBefore=$script:current.Accent;$coverBefore=$script:current.Cover
    $nameBox.Text='Title only';Save-Current
    Assert-True ($script:current.Accent -eq $accentBefore -and $script:current.Cover -eq $coverBefore) 'Metadata-only save reprocessed artwork'
    Assert-True (@(Get-ChildItem -LiteralPath (Join-Path $Resources 'Art') -Recurse -File).Count -eq $artBefore.Count) 'Metadata-only save created artwork'
    foreach($name in @('State.ini','Settings.ini')){Assert-True ([IO.File]::ReadAllText((Join-Path $Resources $name)) -eq 'user data') 'Artwork save changed user settings/state'}
    Assert-True (@(Get-ChildItem -LiteralPath $Resources -Recurse -File -Filter '*.new').Count -eq 0) 'Artwork temporary files left behind'
    # The control-center scan forces a decode, recognizes the existing repair
    # path, and reports missing/corrupt images without stopping the whole scan.
    foreach($relative in @($script:current.Cover,$script:current.Background,$script:current.Blur)) {
        Assert-True ($null -eq (Get-CachedArtIssue $relative)) 'Diagnostics rejected a valid cache'
    }
    Assert-True ((Get-CachedArtIssue 'missing.jpg').Level -eq 'Error') 'Diagnostics missed an absent cache'
    Assert-True ((Get-CachedArtIssue 'broken.jpg').Level -eq 'Error') 'Diagnostics missed malformed artwork'
    [IO.Directory]::CreateDirectory((Join-Path $Resources 'Art/Repairs'))|Out-Null
    [IO.File]::WriteAllText((Join-Path $Resources 'Art/Covers/game999.png'),'truncated',$encoding)
    [IO.File]::Copy((Join-Path $Resources $script:current.Cover),(Join-Path $Resources 'Art/Repairs/game999.png'))
    Assert-True ((Get-CachedArtIssue 'Art/Covers/game999.png').Level -eq 'Warning') 'Usable repair was treated as an unusable cover'
    Write-Output ($script:releaseLabel+': PASS - crop bounds, focal pixels, accents, malformed images, cache sizes, rollback, schema upgrade, backups, title-only save and cached-art diagnostics')
} finally {
    [Threading.Thread]::CurrentThread.CurrentCulture=$culture
    if(Test-Path -LiteralPath $Resources){Remove-Item -LiteralPath $Resources -Recurse -Force}
}
