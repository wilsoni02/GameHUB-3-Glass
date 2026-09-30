param([Parameter(Mandatory=$true)][string]$Resources,[string]$SelectId='',[string]$RequestId='standalone')
# GameHUB 3 (Liquid Glass) game manager. Windows PowerShell 5.1 / Windows Forms.
# Local files only. This script never changes PowerShell execution policy.
$ErrorActionPreference='Stop'
$script:stage='Starting manager'
$script:releaseLabel='GameHUB 3 (Liquid Glass) (release metadata unavailable)'
function Read-IniSection([string]$path,[string]$section) {
    $values=@{};$current=''
    if(Test-Path -LiteralPath $path) {
        foreach($line in [IO.File]::ReadAllLines($path,[Text.Encoding]::UTF8)) {
            if($line -match '^\s*\[([^\]]+)\]\s*$') {$current=$Matches[1]}
            elseif($current -eq $section -and $line -notmatch '^\s*[;#]' -and $line -match '^\s*([^=]+)=(.*)$') {
                $values[$Matches[1].Trim()]=$Matches[2].Trim()
            }
        }
    }
    return $values
}
function Write-Status([string]$state) {
    if(-not $Resources -or -not(Test-Path -LiteralPath $Resources)){return}
    $path=Join-Path $Resources 'Manager-status.ini'
    $temp=$path+'.new'
    $body="[Manager]`nRequestId=$RequestId`nStatus=$state`n"
    $encoding=New-Object Text.UTF8Encoding($false)
    try {
        [IO.File]::WriteAllText($temp,$body,$encoding)
        if(Test-Path -LiteralPath $path) {
            # File.Replace(...,$null) is unreliable under Windows PowerShell 5.1 on
            # some systems. Copy-overwrite keeps the tiny status file update simple
            # and, importantly, status reporting can no longer abort the manager.
            [IO.File]::Copy($temp,$path,$true)
            [IO.File]::Delete($temp)
        } else {
            [IO.File]::Move($temp,$path)
        }
    } catch {
        # Status is coordination/diagnostic data, never a reason to kill the editor.
        try {[IO.File]::WriteAllText($path,$body,$encoding)}
        catch {Write-Output ('GH_WARN status write failed: '+$_.Exception.Message)}
        if(Test-Path -LiteralPath $temp){try{[IO.File]::Delete($temp)}catch{}}
    }
}
try {
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
$script:stage='Reading release metadata'
$release=Read-IniSection (Join-Path $Resources 'Release.ini') 'Release'
$script:librarySchema=0
if(-not $release.Version -or -not $release.Build -or -not [int]::TryParse($release.LibrarySchema,[ref]$script:librarySchema) -or $script:librarySchema -lt 1) {
    throw 'Release.ini is missing or invalid. Reapply the complete maintenance update.'
}
if($script:librarySchema -ne 4){throw 'This manager requires schema 4 release metadata. Reapply the complete update before saving.'}
$script:releaseLabel='GameHUB 3 (Liquid Glass) '+$release.Version+' (build '+$release.Build+')'
Write-Output $script:releaseLabel
$script:stage='Loading Windows Forms'
# Request standard system-DPI awareness before creating any manager controls.
# An already-aware PowerShell host keeps its existing mode. No DWM effects.
try {
    if(-not ('GameHUB.ManagerDpi' -as [type])) {
        Add-Type -TypeDefinition 'using System.Runtime.InteropServices; namespace GameHUB { public static class ManagerDpi { [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] public static extern bool SetProcessDPIAware(); } }'
    }
    [GameHUB.ManagerDpi]::SetProcessDPIAware()|Out-Null
} catch {Write-Output ('GH_WARN DPI awareness request: '+$_.Exception.Message)}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$Resources=[IO.Path]::GetFullPath($Resources)
Write-Status 'starting'
$script:libraryPath=Join-Path $Resources 'Library.ini'
$script:games=New-Object 'System.Collections.Generic.List[object]'
$script:current=$null
$script:loading=$false
$script:dirty=$false
$script:coverChanged=$false
$script:backgroundChanged=$false
$script:coverInput=''
$script:backgroundInput=''
$script:coverFrame=$null
$script:backgroundFrame=$null
$script:frameEditor=$null
$script:resetAccent=$false
$script:newGameId=''
$script:settingsDirty=$false
$script:settingsLoading=$true
$script:settingsDocument=$null
$script:sessionStarted=Get-Date
$script:diagnosticSnapshot=$null
$script:diagnosticQueue=$null
$script:mutex=$null
$hash=[BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($Resources))).Replace('-','')
$created=$false
$script:mutex=New-Object System.Threading.Mutex($true,('Local\GameHUBGlass_'+$hash),[ref]$created)
if(-not $created){throw 'A GameHUB 3 (Liquid Glass) manager is already open. Close that window before opening another.'}

function New-Game([string]$id='') {
    if(-not $id){$id=[Guid]::NewGuid().ToString('N')}
    return [pscustomobject][ordered]@{Id=$id;Name='New game';Platform='Steam';Tags='';Target='';Launch='';Arguments='';WorkingDirectory='';Cover='UI/Placeholder.png';Background='UI/Backdrop.jpg';Blur='UI/Blur.jpg';CoverSource='';BackgroundSource='';Accent='';CoverFocalX='0.5';CoverFocalY='0.5';CoverZoom='1';BackgroundFocalX='0.5';BackgroundFocalY='0.5';BackgroundZoom='1';PreviewVideo='';PreviewStart='';PreviewEnd='';Logo='';Order=9999}
}
function Assert-LibrarySchema {
    $metadata=Read-IniSection $script:libraryPath 'Library'
    # Existing libraries without a marker use the original schema; no migration.
    $version=1
    if($metadata.ContainsKey('Version') -and -not [int]::TryParse($metadata.Version,[ref]$version)) {
        throw 'Library.ini has an invalid schema version. The library has not been saved.'
    }
    # Read legacy schemas 1, 2 and 3 without rewriting. An explicit save writes schema 4;
    # older managers then refuse to overwrite fields they cannot round-trip.
    if($version -lt 1 -or $version -gt $script:librarySchema) {
        throw ('Library schema '+$version+' is not supported by '+$script:releaseLabel+'. The library has not been saved; use a compatible manager.')
    }
}
function Read-Library {
    Assert-LibrarySchema
    $game=$null
    if(-not(Test-Path -LiteralPath $script:libraryPath)){return}
    foreach($line in [IO.File]::ReadAllLines($script:libraryPath,[Text.Encoding]::UTF8)) {
        if($line -match '^\[Game:([a-zA-Z0-9_-]+)\]$') {
            $game=New-Game $Matches[1];$script:games.Add($game)
        } elseif($line -match '^\[') {$game=$null}
        elseif($null -ne $game -and $line -match '^([^=]+)=(.*)$') {
            $key=$Matches[1].Trim();$value=$Matches[2]
            if($key -ne 'Id' -and $null -ne $game.PSObject.Properties[$key]) {
                if($key -eq 'Order'){$number=9999;if([int]::TryParse($value,[ref]$number)){$game.Order=$number}}
                else{$game.$key=$value}
            }
        }
    }
    $sorted=@($script:games | Sort-Object -Property @('Order','Id'));$script:games.Clear()
    foreach($g in $sorted){$script:games.Add($g)}
}
function Write-Library {
    Assert-LibrarySchema
    $lines=New-Object 'System.Collections.Generic.List[string]'
    $lines.Add('[Library]');$lines.Add('Version='+$script:librarySchema);$lines.Add('')
    for($i=0;$i -lt $script:games.Count;$i++) {
        $g=$script:games[$i]
        if(-not $g.Target){continue}
        $g.Order=$i+1;$lines.Add('[Game:'+$g.Id+']')
        foreach($key in @('Name','Platform','Tags','Target','Launch','Arguments','WorkingDirectory','Cover','Background','Blur','CoverSource','BackgroundSource','Accent','CoverFocalX','CoverFocalY','CoverZoom','BackgroundFocalX','BackgroundFocalY','BackgroundZoom','PreviewVideo','PreviewStart','PreviewEnd','Logo','Order')) {
            $value=[string]$g.$key
            if($value.Contains("`r") -or $value.Contains("`n")){throw 'Fields must contain a single line.'}
            $lines.Add($key+'='+$value)
        }
        $lines.Add('')
    }
    $temp=$script:libraryPath+'.new'
    [IO.File]::WriteAllLines($temp,$lines,(New-Object Text.UTF8Encoding($false)))
    if(Test-Path -LiteralPath $script:libraryPath){[IO.File]::Replace($temp,$script:libraryPath,($script:libraryPath+'.bak'))}
    else{[IO.File]::Move($temp,$script:libraryPath)}
}
function Usable-Art([string]$relative) {
    if(-not $relative){return ''}
    $p=Join-Path $Resources $relative
    if(Test-Path -LiteralPath $p) {
        if([IO.Path]::GetExtension($p) -ne '.png'){return $p}
        $stream=[IO.File]::OpenRead($p)
        try {
            if($stream.Length -ge 12) {
                $stream.Seek(-12,[IO.SeekOrigin]::End)|Out-Null
                $tail=New-Object byte[] 12;$read=$stream.Read($tail,0,12)
                if($read -eq 12 -and [BitConverter]::ToString($tail) -eq '00-00-00-00-49-45-4E-44-AE-42-60-82'){return $p}
            }
        } finally {$stream.Dispose()}
    }
    if($relative -match '^Art[/\\]Covers[/\\](game\d+\.png)$') {
        $repair=Join-Path $Resources ('Art/Repairs/'+$Matches[1])
        if(Test-Path -LiteralPath $repair){return $repair}
    }
    return ''
}
function Resolve-Art([string]$relative,[string]$fallback) {
    $p=Usable-Art $relative;if($p){return $p}
    return (Join-Path $Resources $fallback)
}
function Frame-Number($value,[double]$fallback,[double]$minimum,[double]$maximum) {
    $number=0.0
    $text=[Convert]::ToString($value,[Globalization.CultureInfo]::InvariantCulture)
    if(-not [double]::TryParse($text,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$number) -or [double]::IsNaN($number) -or [double]::IsInfinity($number)){return $fallback}
    return [Math]::Max($minimum,[Math]::Min($maximum,$number))
}
function Get-ArtFrame($game,[string]$kind) {
    return [pscustomobject]@{
        X=(Frame-Number $game.($kind+'FocalX') 0.5 0 1)
        Y=(Frame-Number $game.($kind+'FocalY') 0.5 0 1)
        Zoom=(Frame-Number $game.($kind+'Zoom') 1 1 3)
    }
}
function Get-CropRectangle([int]$sourceWidth,[int]$sourceHeight,[int]$width,[int]$height,$frame) {
    if($sourceWidth -le 0 -or $sourceHeight -le 0 -or $width -le 0 -or $height -le 0){throw 'Artwork dimensions must be positive.'}
    if($null -eq $frame){$frame=[pscustomobject]@{X=0.5;Y=0.5;Zoom=1}}
    $fx=Frame-Number $frame.X 0.5 0 1;$fy=Frame-Number $frame.Y 0.5 0 1;$zoom=Frame-Number $frame.Zoom 1 1 3
    $scale=[Math]::Max($width/[double]$sourceWidth,$height/[double]$sourceHeight)*$zoom
    $cw=[Math]::Min([double]$sourceWidth,[double]$width/$scale);$ch=[Math]::Min([double]$sourceHeight,[double]$height/$scale)
    $x=[Math]::Max([double]0,[Math]::Min([double]$sourceWidth-$cw,$fx*$sourceWidth-$cw/2))
    $y=[Math]::Max([double]0,[Math]::Min([double]$sourceHeight-$ch,$fy*$sourceHeight-$ch/2))
    return [Drawing.RectangleF]::new([single]$x,[single]$y,[single]$cw,[single]$ch)
}
function New-CroppedBitmap([string]$source,[int]$width,[int]$height,[bool]$round=$false,$frame=$null) {
    $image=$null;$bmp=$null;$graphics=$null;$clip=$null;$attributes=$null
    try {
        $image=[Drawing.Image]::FromFile($source)
        $bmp=New-Object Drawing.Bitmap($width,$height,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $graphics=[Drawing.Graphics]::FromImage($bmp)
        $graphics.Clear([Drawing.Color]::Transparent)
        $graphics.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.SmoothingMode=[Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.PixelOffsetMode=[Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        if($round) {
            $r=[single]($width*0.028);$d=$r*2
            $clip=New-Object Drawing.Drawing2D.GraphicsPath
            $clip.AddArc(0,0,$d,$d,180,90);$clip.AddArc(($width-$d),0,$d,$d,270,90)
            $clip.AddArc(($width-$d),($height-$d),$d,$d,0,90);$clip.AddArc(0,($height-$d),$d,$d,90,90)
            $clip.CloseFigure();$graphics.SetClip($clip)
        }
        $crop=Get-CropRectangle $image.Width $image.Height $width $height $frame
        $dest=New-Object Drawing.Rectangle(0,0,$width,$height)
        $attributes=New-Object Drawing.Imaging.ImageAttributes
        $attributes.SetWrapMode([Drawing.Drawing2D.WrapMode]::TileFlipXY)
        $graphics.DrawImage($image,$dest,$crop.X,$crop.Y,$crop.Width,$crop.Height,[Drawing.GraphicsUnit]::Pixel,$attributes)
    } catch {if($null -ne $bmp){$bmp.Dispose()};throw}
    finally {
        if($null -ne $attributes){$attributes.Dispose()};if($null -ne $clip){$clip.Dispose()}
        if($null -ne $graphics){$graphics.Dispose()};if($null -ne $image){$image.Dispose()}
    }
    return $bmp
}
function Get-ArtAccent($bitmap) {
    # A small, one-time sample of the framed image. Never called by Rainmeter.
    $fallback='209,250,239'
    $sample=New-Object Drawing.Bitmap(96,54,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics=$null
    try {
        $graphics=[Drawing.Graphics]::FromImage($sample)
        $graphics.Clear([Drawing.Color]::Transparent)
        $graphics.DrawImage($bitmap,0,0,96,54)
        $bins=@{}
        for($y=0;$y -lt 54;$y++) {for($x=0;$x -lt 96;$x++) {
            $c=$sample.GetPixel($x,$y);if($c.A -lt 200){continue}
            $r=$c.R/255.0;$g=$c.G/255.0;$b=$c.B/255.0
            $hi=[Math]::Max($r,[Math]::Max($g,$b));$lo=[Math]::Min($r,[Math]::Min($g,$b))
            $luma=0.2126*$r+0.7152*$g+0.0722*$b
            if($hi -lt 0.25 -or $luma -lt 0.10 -or $luma -gt 0.90 -or ($hi-$lo) -lt 0.10 -or ($hi-$lo)/$hi -lt 0.20){continue}
            $key=[int][Math]::Floor($c.GetHue()/15)
            $weight=(0.35+0.65*(($hi-$lo)/$hi))*(1-[Math]::Abs($luma-0.5))
            if(-not $bins.ContainsKey($key)){$bins[$key]=@{Weight=0.0;R=0.0;G=0.0;B=0.0}}
            $bin=$bins[$key];$bin.Weight+=$weight;$bin.R+=$c.R*$weight;$bin.G+=$c.G*$weight;$bin.B+=$c.B*$weight
        }}
        $best=$null
        # Stable tie-break by hue, not hashtable enumeration order.
        foreach($key in @($bins.Keys|Sort-Object)) {if($null -eq $best -or $bins[$key].Weight -gt $best.Weight){$best=$bins[$key]}}
        if($null -eq $best -or $best.Weight -lt 12){return $fallback}
        $color=[Drawing.Color]::FromArgb([int]($best.R/$best.Weight),[int]($best.G/$best.Weight),[int]($best.B/$best.Weight))
        $h=$color.GetHue()/30.0
        $s=[Math]::Max(0.30,[Math]::Min(0.62,$color.GetSaturation()))
        $l=[Math]::Max(0.62,[Math]::Min(0.70,$color.GetBrightness()))
        $a=$s*[Math]::Min($l,1-$l);$rgb=@()
        foreach($n in @(0,8,4)) {
            $k=($n+$h)%12
            $v=$l-$a*[Math]::Max(-1,[Math]::Min([Math]::Min($k-3,9-$k),1))
            $rgb+=[int][Math]::Round(255*$v)
        }
        return ($rgb -join ',')
    } finally {if($null -ne $graphics){$graphics.Dispose()};$sample.Dispose()}
}
function Save-Bitmap($bitmap,[string]$destination,[bool]$png=$false) {
    $folder=Split-Path -Parent $destination
    [IO.Directory]::CreateDirectory($folder)|Out-Null
    $temp=$destination+'.'+[Guid]::NewGuid().ToString('N')+'.new'
    try {
      if($png){$bitmap.Save($temp,[Drawing.Imaging.ImageFormat]::Png)}
      else {
        $encoder=[Drawing.Imaging.ImageCodecInfo]::GetImageEncoders()|Where-Object MimeType -eq 'image/jpeg'
        $params=New-Object Drawing.Imaging.EncoderParameters(1)
        $params.Param[0]=New-Object Drawing.Imaging.EncoderParameter([Drawing.Imaging.Encoder]::Quality,[long]88)
        try{$bitmap.Save($temp,$encoder,$params)}finally{$params.Dispose()}
      }
      $check=[Drawing.Image]::FromFile($temp);$check.Dispose()
      if(Test-Path -LiteralPath $destination){
        # Avoid File.Replace with a null backup path for PowerShell 5.1 compatibility.
        [IO.File]::Copy($temp,$destination,$true);[IO.File]::Delete($temp)
      } else {[IO.File]::Move($temp,$destination)}
    } finally {if(Test-Path -LiteralPath $temp){[IO.File]::Delete($temp)}}
}
function Store-Art($game,[string]$kind,[string]$source,$frame=$null,$createdFiles=$null) {
    if($kind -notin @('Cover','Background')){throw 'Unknown artwork kind.'}
    if(-not(Test-Path -LiteralPath $source)){throw 'The selected artwork file is no longer available.'}
    $extension=[IO.Path]::GetExtension($source).ToLowerInvariant()
    if($extension -notin @('.png','.jpg','.jpeg','.bmp')){throw 'Use a PNG, JPG, or BMP image.'}
    try {$check=[Drawing.Image]::FromFile($source);$check.Dispose()}
    catch {throw 'Windows could not decode this image. Export it as a real PNG or JPG; renaming WebP or AVIF to .jpg does not convert it.'}
    if($null -eq $frame){$frame=Get-ArtFrame $game $kind}
    $frame=[pscustomobject]@{X=(Frame-Number $frame.X 0.5 0 1);Y=(Frame-Number $frame.Y 0.5 0 1);Zoom=(Frame-Number $frame.Zoom 1 1 3)}
    # Fresh filenames prevent stale Rainmeter image caches and keep the previous
    # library / .bak references usable. Never overwrite the user's old artwork.
    $stem=$game.Id+'_'+[Guid]::NewGuid().ToString('N')
    $original='Art/Originals/'+$stem+'_'+$kind.ToLower()+$extension
    $originalPath=Join-Path $Resources $original
    $savedSource=$game.($kind+'Source')
    $reuseSource=$savedSource -match '^Art[/\\]Originals[/\\][^/\\]+$' -and [IO.Path]::GetFullPath($source) -eq [IO.Path]::GetFullPath((Join-Path $Resources $savedSource))
    if($reuseSource){$original=$savedSource;$originalPath=$source}
    $created=New-Object 'System.Collections.Generic.List[string]'
    try {
        if(-not $reuseSource) {
            [IO.Directory]::CreateDirectory((Split-Path -Parent $originalPath))|Out-Null
            $created.Add($originalPath);[IO.File]::Copy($source,$originalPath,$false)
        }
        if($kind -eq 'Cover') {
            $relative='Art/Covers/'+$stem+'.png'
            $created.Add((Join-Path $Resources $relative))
            $bmp=New-CroppedBitmap $originalPath 960 540 $true $frame
            try{$accent=Get-ArtAccent $bmp;Save-Bitmap $bmp (Join-Path $Resources $relative) $true}finally{$bmp.Dispose()}
        } else {
            $relative='Art/Backgrounds/'+$stem+'.jpg'
            $created.Add((Join-Path $Resources $relative))
            $bmp=New-CroppedBitmap $originalPath 3840 2160 $false $frame
            try{$accent=Get-ArtAccent $bmp;Save-Bitmap $bmp (Join-Path $Resources $relative)}finally{$bmp.Dispose()}
            $blur='Art/Blur/'+$stem+'.jpg'
            $created.Add((Join-Path $Resources $blur))
            $tiny=$null;$large=$null;$gr=$null
            try {
                # Identical source rectangle for full backdrop and precomputed frost.
                $tiny=New-CroppedBitmap $originalPath 80 45 $false $frame
                $large=New-Object Drawing.Bitmap(1280,720)
                $gr=[Drawing.Graphics]::FromImage($large)
                $gr.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $gr.DrawImage($tiny,0,0,1280,720);Save-Bitmap $large (Join-Path $Resources $blur)
            } finally {if($null -ne $gr){$gr.Dispose()};if($null -ne $tiny){$tiny.Dispose()};if($null -ne $large){$large.Dispose()}}
        }
    } catch {
        foreach($path in $created){if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue}}
        throw
    }
    # Publish metadata only after every cache has been successfully encoded.
    $game.$kind=$relative;$game.($kind+'Source')=$original;$game.Accent=$accent
    if($kind -eq 'Background'){$game.Blur=$blur}
    $game.($kind+'FocalX')=$frame.X.ToString('0.####',[Globalization.CultureInfo]::InvariantCulture)
    $game.($kind+'FocalY')=$frame.Y.ToString('0.####',[Globalization.CultureInfo]::InvariantCulture)
    $game.($kind+'Zoom')=$frame.Zoom.ToString('0.####',[Globalization.CultureInfo]::InvariantCulture)
    if($null -ne $createdFiles){foreach($path in $created){$createdFiles.Add($path)}}
}
function Set-Preview($box,[string]$path,[bool]$cover=$false,$frame=$null) {
    $new=New-CroppedBitmap $path 480 270 $cover $frame
    if($null -ne $selectedThumb -and [object]::ReferenceEquals($box,$coverBox)){$selectedThumb.Image=$null}
    $old=$box.Image;$box.Image=$new;if($null -ne $old){$old.Dispose()}
}
function Set-SafePreview($box,[string]$path,[bool]$cover=$false) {
    try {Set-Preview $box $path $cover}
    catch {
        Set-Preview $box (Join-Path $Resources 'UI/Placeholder.png') $cover
        $status.Text='An image could not be previewed. Choose a PNG or JPG to replace it.'
    }
}
function Show-Error($errorObject) {
    [Windows.Forms.MessageBox]::Show([string]$errorObject,'GameHUB 3 (Liquid Glass)',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error)|Out-Null
}
function Mark-Dirty {if(-not $script:loading){$script:dirty=$true;Update-GamePresentation}}
function Normalize-Tags([string]$value) {
    if($value -match '[\x00-\x1F\x7F]'){throw 'Tags must be on one line without control characters.'}
    $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $tags=New-Object 'System.Collections.Generic.List[string]'
    foreach($part in $value.Split(',')) {
        $tag=($part.Trim() -replace '\s+',' ')
        if($tag -and $seen.Add($tag)){$tags.Add($tag)}
    }
    return ($tags -join ', ')
}
function Save-HeroLogo([string]$source,[string]$destination) {
        $image=$null;$bitmap=$null;$graphics=$null
        try {
            $image=[Drawing.Image]::FromFile($source)
            if($image.RawFormat.Guid -ne [Drawing.Imaging.ImageFormat]::Png.Guid -or $image.Width -gt 8192 -or $image.Height -gt 8192){throw 'Choose a valid PNG logo no larger than 8192 pixels per side.'}
            $ratio=[Math]::Min(1,[Math]::Min(1120.0/$image.Width,352.0/$image.Height))
            $bitmap=New-Object Drawing.Bitmap([int][Math]::Max(1,[Math]::Round($image.Width*$ratio)),[int][Math]::Max(1,[Math]::Round($image.Height*$ratio)),[Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $graphics=[Drawing.Graphics]::FromImage($bitmap);$graphics.Clear([Drawing.Color]::Transparent)
            $graphics.CompositingMode=[Drawing.Drawing2D.CompositingMode]::SourceCopy
            $graphics.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.DrawImage($image,0,0,$bitmap.Width,$bitmap.Height)
            $bitmap.Save($destination,[Drawing.Imaging.ImageFormat]::Png)
        } finally {if($graphics){$graphics.Dispose()};if($bitmap){$bitmap.Dispose()};if($image){$image.Dispose()}}
}
function Store-HeroMedia($game,[string]$kind,[string]$source,$createdFiles) {
    if($kind -notin @('PreviewVideo','Logo')){throw 'Unknown Hero media type.'}
    if(-not $source){$game.$kind='';if($kind -eq 'PreviewVideo'){$game.PreviewStart='';$game.PreviewEnd=''};return}
    if($source -match '[\r\n]' -or $source.StartsWith('\\') -or -not [IO.Path]::IsPathRooted($source) -or -not(Test-Path -LiteralPath $source -PathType Leaf)){throw 'Choose an existing local file on this PC.'}
    $extension=[IO.Path]::GetExtension($source).ToLowerInvariant()
    $folder=if($kind -eq 'Logo'){'Logos'}else{'Previews'}
    if($kind -eq 'Logo' -and $extension -ne '.png'){throw 'Choose a transparent PNG logo.'}
    if($kind -eq 'PreviewVideo' -and $extension -notin @('.mp4','.m4v','.wmv')){throw 'Choose a local MP4, M4V, or WMV video. H.264 MP4 is recommended.'}
    if((Get-Item -LiteralPath $source).Length -eq 0){throw 'The selected media file is empty.'}
    $relative='Art/'+$folder+'/'+$game.Id+'_'+[Guid]::NewGuid().ToString('N')+$extension
    $destination=Join-Path $Resources $relative
    [IO.Directory]::CreateDirectory((Split-Path -Parent $destination))|Out-Null
    $createdFiles.Add($destination)
    if($kind -eq 'Logo') {
        Save-HeroLogo $source $destination
    } else {
        [IO.File]::Copy($source,$destination,$false)
        $game.PreviewStart='';$game.PreviewEnd=''
    }
    $game.$kind=$relative
}
function Choose-HeroMedia([string]$kind) {
    if($null -eq $script:current){return}
    $dialog=New-Object Windows.Forms.OpenFileDialog
    $dialog.Title=if($kind -eq 'Logo'){'Choose Hero logo'}else{'Choose local Hero preview'}
    $dialog.Filter=if($kind -eq 'Logo'){'PNG logo (*.png)|*.png'}else{'Local videos (*.mp4;*.m4v;*.wmv)|*.mp4;*.m4v;*.wmv'}
    try {
        if($dialog.ShowDialog($form) -eq [Windows.Forms.DialogResult]::OK){
            $script:heroMediaDraft[$kind]=$dialog.FileName;$script:heroMediaChanged[$kind]=$true
            $mediaPaths[$kind].Text=$dialog.FileName+' (pending Save game)';Mark-Dirty
        }
    } finally {$dialog.Dispose()}
}
function Remove-HeroMedia([string]$kind) {
    if($null -eq $script:current){return}
    $script:heroMediaDraft[$kind]='';$script:heroMediaChanged[$kind]=$true
    $mediaPaths[$kind].Text='None (pending Save game)';Mark-Dirty
}
function Save-Current {
    if($null -eq $script:current){return}
    $previous=$script:current
    $g=New-Game $previous.Id
    foreach($property in $previous.PSObject.Properties){$g.($property.Name)=$property.Value}
    $name=$nameBox.Text.Trim();$targetText=$targetBox.Text.Trim();$tags=Normalize-Tags $tagsBox.Text
    if(-not $name){throw 'Enter a game title.'}
    if(-not $targetText){throw 'Enter a Steam app ID, launch URL, or local file path.'}
    if($targetText -match '["\r\n]'){throw 'The launch target cannot contain quotes or line breaks.'}
    $issue=Get-TargetIssue $targetText $workingBox.Text;if($issue){throw $issue}
    if($targetText -match '^\d+$'){$targetText='steam://rungameid/'+$targetText}
    $targetText=[Environment]::ExpandEnvironmentVariables($targetText)
    $launch=$targetText
    if($targetText -notmatch '^[a-zA-Z][a-zA-Z0-9+.-]*://') {
        if(-not(Test-Path -LiteralPath $targetText -PathType Leaf)){throw 'The launch file was not found. Browse to its current location.'}
        $extension=[IO.Path]::GetExtension($targetText).ToLowerInvariant()
        if($extension -notin @('.exe','.lnk','.url')){throw 'Choose an EXE, Windows shortcut (.lnk), or Internet shortcut (.url).'}
        if($extension -eq '.exe') {
            $relative='Shortcuts/'+$g.Id+'.lnk';$shortcutPath=Join-Path $Resources $relative
            [IO.Directory]::CreateDirectory((Split-Path -Parent $shortcutPath))|Out-Null
            $shell=New-Object -ComObject WScript.Shell
            $shortcut=$shell.CreateShortcut($shortcutPath)
            try {
                $shortcut.TargetPath=$targetText;$shortcut.Arguments=$argsBox.Text
                $work=$workingBox.Text.Trim();if(-not $work){$work=Split-Path -Parent $targetText}
                if(-not(Test-Path -LiteralPath $work -PathType Container)){throw 'The working folder was not found.'}
                $shortcut.WorkingDirectory=$work;$shortcut.Save();$launch=$relative
            } finally {
                [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut)|Out-Null
                [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)|Out-Null
            }
        }
    }
    $index=$script:games.IndexOf($previous)
    $artFiles=New-Object 'System.Collections.Generic.List[string]'
    try {
        if($script:coverChanged){Store-Art $g 'Cover' $script:coverInput $script:coverFrame $artFiles}
        if($script:backgroundChanged){Store-Art $g 'Background' $script:backgroundInput $script:backgroundFrame $artFiles}
        if($script:resetAccent){$g.Accent=''}
        foreach($kind in @('PreviewVideo','Logo')){if($script:heroMediaChanged -and $script:heroMediaChanged[$kind]){Store-HeroMedia $g $kind $script:heroMediaDraft[$kind] $artFiles}}
        $g.Name=$name;$g.Platform=[string]$platformBox.SelectedItem;$g.Tags=$tags;$g.Target=$targetText;$g.Launch=$launch
        $g.Arguments=$argsBox.Text;$g.WorkingDirectory=$workingBox.Text
        $script:games[$index]=$g;Write-Library
    } catch {
        $script:games[$index]=$previous
        foreach($path in $artFiles){Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue}
        throw
    }
    $script:dirty=$false;$script:coverChanged=$false;$script:backgroundChanged=$false
    $script:resetAccent=$false;if($script:newGameId -eq $g.Id){$script:newGameId=''}
    $saveButton.Text='Saved';$status.Text='Saved. Close this window to return to GameHUB.'
    Refresh-List $g.Id
}
function Confirm-Pending {
    if(-not $script:dirty){return $true}
    $answer=[Windows.Forms.MessageBox]::Show('Save changes to the current game?','GameHUB 3 (Liquid Glass)',[Windows.Forms.MessageBoxButtons]::YesNoCancel,[Windows.Forms.MessageBoxIcon]::Question)
    if($answer -eq [Windows.Forms.DialogResult]::Cancel){return $false}
    if($answer -eq [Windows.Forms.DialogResult]::Yes){try{Save-Current}catch{Show-Error $_;return $false}}
    if($answer -eq [Windows.Forms.DialogResult]::No){Discard-GameChanges}
    $script:dirty=$false;return $true
}

$script:stage='Reading the game library'
Read-Library

function Steam-Root {
    $paths=New-Object 'System.Collections.Generic.List[string]'
    foreach($key in @('HKCU:\Software\Valve\Steam','HKLM:\SOFTWARE\WOW6432Node\Valve\Steam','HKLM:\SOFTWARE\Valve\Steam')) {
        $entry=Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
        if($null -ne $entry){foreach($name in @('SteamPath','InstallPath')){if($entry.$name){$paths.Add([string]$entry.$name)}}}
    }
    $paths.Add((Join-Path ${env:ProgramFiles(x86)} 'Steam'))
    foreach($p in $paths){if(Test-Path -LiteralPath (Join-Path $p 'steamapps')){return $p}}
    throw 'Steam was not found. You can still add a game by its Steam app ID.'
}
function Read-VdfValue([string]$text,[string]$key) {
    $pattern='"'+[regex]::Escape($key)+'"\s*"((?:\\.|[^"\\])*)"'
    $match=[regex]::Match($text,$pattern,[Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if($match.Success){return $match.Groups[1].Value.Replace('\\','\').Replace('\"','"')}
    return ''
}
function Import-Steam {
    if(-not(Confirm-Pending)){return}
    $steam=Steam-Root
    $folders=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $folders.Add($steam)|Out-Null
    $vdf=Join-Path $steam 'steamapps\libraryfolders.vdf'
    if(Test-Path -LiteralPath $vdf) {
        $raw=[IO.File]::ReadAllText($vdf)
        foreach($m in [regex]::Matches($raw,'"path"\s*"((?:\\.|[^"\\])*)"')){$folders.Add($m.Groups[1].Value.Replace('\\','\'))|Out-Null}
    }
    $existing=New-Object 'System.Collections.Generic.HashSet[string]'
    foreach($g in $script:games){if($g.Target -match '^steam://(?:rungameid|run)/(\d+)'){$existing.Add($Matches[1])|Out-Null}}
    $candidates=New-Object 'System.Collections.Generic.List[object]'
    foreach($folder in $folders) {
        $apps=Join-Path $folder 'steamapps'
        if(-not(Test-Path -LiteralPath $apps)){continue}
        foreach($manifest in Get-ChildItem -LiteralPath $apps -Filter 'appmanifest_*.acf' -File -ErrorAction SilentlyContinue) {
            $raw=[IO.File]::ReadAllText($manifest.FullName)
            $id=Read-VdfValue $raw 'appid';$name=Read-VdfValue $raw 'name';$dir=Read-VdfValue $raw 'installdir'
            if(-not $id -or -not $name -or $existing.Contains($id)){continue}
            if(-not(Test-Path -LiteralPath (Join-Path $apps ('common\'+$dir)))){continue}
            if($name -match '^(Steamworks Common Redistributables|Steam Linux Runtime|Proton)'){continue}
            $candidates.Add([pscustomobject]@{Name=$name;AppId=$id});$existing.Add($id)|Out-Null
        }
    }
    if($candidates.Count -eq 0){$status.Text='No additional installed Steam games were found.';return}
    $dialog=New-Object Windows.Forms.Form
    $dialog.Text='Import installed Steam games';$dialog.Size=New-Object Drawing.Size(600,550)
    $dialog.AutoScaleMode=[Windows.Forms.AutoScaleMode]::Dpi;$dialog.AutoScaleDimensions=New-Object Drawing.SizeF(96,96)
    $dialog.StartPosition='CenterParent';$dialog.BackColor=$surface;$dialog.ForeColor=$ink
    $dialog.Font=New-Object Drawing.Font('Segoe UI',10);$dialog.MinimizeBox=$false;$dialog.MaximizeBox=$false
    $choose=New-Object Windows.Forms.CheckedListBox
    $choose.Dock='Fill';$choose.BackColor=$field;$choose.ForeColor=$ink;$choose.CheckOnClick=$true;$choose.DisplayMember='Name';$choose.BorderStyle='None'
    foreach($item in @($candidates|Sort-Object Name)){$choose.Items.Add($item,$true)|Out-Null}
    $import=New-Object Windows.Forms.Button;$import.Text='Import selected';$import.Dock='Bottom';$import.Height=48
    $import.DialogResult=[Windows.Forms.DialogResult]::OK;$dialog.AcceptButton=$import
    $dialog.Controls.Add($choose);$dialog.Controls.Add($import)
    if($dialog.ShowDialog($form) -ne [Windows.Forms.DialogResult]::OK){$dialog.Dispose();return}
    $picked=@($choose.CheckedItems);$dialog.Dispose()
    if($picked.Count -eq 0){return}
    $cache=Join-Path $steam 'appcache\librarycache'
    $art=@();if(Test-Path -LiteralPath $cache){$art=@(Get-ChildItem -LiteralPath $cache -Recurse -File -ErrorAction SilentlyContinue|Where-Object Extension -match '^\.(jpg|jpeg|png)$')}
    $count=0;$artCount=0
    foreach($entry in $picked) {
        $g=New-Game;$g.Name=$entry.Name;$g.Platform='Steam';$g.Target='steam://rungameid/'+$entry.AppId;$g.Launch=$g.Target
        $files=@($art|Where-Object { $_.Name -match ('^'+[regex]::Escape($entry.AppId)+'_') -or $_.DirectoryName -match ('[\\/]'+[regex]::Escape($entry.AppId)+'$') })
        $cover=$files|Where-Object Name -match 'header|capsule_616x353'|Select-Object -First 1
        if($null -eq $cover){$cover=$files|Where-Object Name -match 'library_600x900'|Select-Object -First 1}
        $background=$files|Where-Object Name -match 'library_hero|hero'|Select-Object -First 1
        try{if($null -ne $cover){Store-Art $g 'Cover' $cover.FullName;$artCount++};if($null -ne $background){Store-Art $g 'Background' $background.FullName}}catch{$status.Text='Some cached artwork could not be read; you can add it manually.'}
        $script:games.Add($g);$count++
    }
    Write-Library;Refresh-List $script:games[$script:games.Count-1].Id
    $status.Text="Imported $count games; found cached covers for $artCount. Other artwork can be added manually."
}

# Control-center data helpers. No GUI, image processing, or writes on read.
function Find-LibraryGames($entries,[string]$query) {
    $query=$query.Trim()
    foreach($g in $entries) {
        if(-not $query -or ($g.Name+' '+$g.Platform+' '+$g.Target).IndexOf($query,[StringComparison]::OrdinalIgnoreCase) -ge 0){$g}
    }
}
function Get-TargetIssue([string]$target,[string]$working='') {
    $target=$target.Trim()
    if(-not $target){return 'Enter a Steam app ID, launch URL, or local game/shortcut path.'}
    if($target -match '["\r\n]'){return 'Remove quotes and line breaks from the launch target.'}
    if($target -match '^\d+$'){return ''}
    if($target -match '^[a-zA-Z][a-zA-Z0-9+.-]*://') {
        $uri=$null
        if($target -match '\s|://$' -or -not [Uri]::TryCreate($target,[UriKind]::Absolute,[ref]$uri)){return 'The launch URL is incomplete or invalid.'}
        return ''
    }
    try {
        $target=[Environment]::ExpandEnvironmentVariables($target)
        if(-not(Test-Path -LiteralPath $target -PathType Leaf)){return 'The launch file is missing. Browse to its current location.'}
        $extension=[IO.Path]::GetExtension($target).ToLowerInvariant()
        if($extension -notin @('.exe','.lnk','.url')){return 'Choose an EXE, Windows shortcut (.lnk), or Internet shortcut (.url).'}
        if($extension -eq '.exe' -and $working.Trim() -and -not(Test-Path -LiteralPath $working.Trim() -PathType Container)){return 'The working directory is missing.'}
    } catch {return 'The launch path or working directory is invalid or cannot be read.'}
    return ''
}
function Get-DisplayAccent([string]$value) {
    if($value -match '^\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*$') {
        $rgb=@([int]$Matches[1],[int]$Matches[2],[int]$Matches[3]);$range=$rgb|Measure-Object -Minimum -Maximum
        if($range.Maximum -le 255 -and $range.Maximum -ge 75 -and $range.Minimum -le 240 -and ($range.Maximum-$range.Minimum) -ge 10 -and ($range.Maximum-$range.Minimum) -le 230){return ($rgb -join ',')}
    }
    return '209,250,239'
}
function Get-SettingRules {
    return [ordered]@{
        UIScale=@{Label='UI scale';Min=0.7;Max=1.5;Default=1;Digits=2;Step=0.05;Hint='0.70 - 1.50; relative to automatic monitor sizing.'}
        OpenMs=@{Label='Opening duration (ms)';Min=0;Max=2000;Default=260;Digits=0;Step=10;Hint='0 - 2000 ms; lower values open faster.'}
        CloseMs=@{Label='Closing duration (ms)';Min=0;Max=2000;Default=190;Digits=0;Step=10;Hint='0 - 2000 ms; lower values close faster.'}
        FadeMs=@{Label='Background fade (ms)';Min=0;Max=2000;Default=190;Digits=0;Step=10;Hint='0 - 2000 ms; applies to the artwork crossfade.'}
        WheelStep=@{Label='Wheel step';Min=1;Max=10;Default=1;Digits=0;Step=1;Hint='1 - 10 games per carousel wheel step; paging is unchanged.'}
        ReduceMotion=@{Label='Reduce motion';Min=0;Max=1;Default=0;Digits=0;Step=1;Hint='Use the existing reduced-motion transitions.'}
        HeroVideo=@{Label='Hero video previews';Min=0;Max=1;Default=1;Digits=0;Step=1;Hint='Optional local clips. Reduce motion always disables playback.'}
        PreviewDelay=@{Label='Preview delay (ms)';Min=500;Max=5000;Default=900;Digits=0;Step=100;Hint='Hold the pointer over the focused card or Hero artwork.'}
        PreviewAudio=@{Label='Preview audio';Min=0;Max=1;Default=0;Digits=0;Step=1;Hint='Off by default. Enable only if you want preview sound.'}
        PreviewLoop=@{Label='Loop preview';Min=0;Max=1;Default=0;Digits=0;Step=1;Hint='Off: return to static artwork at the end of the clip.'}
        HeroCinematic=@{Label='Cinematic idle mode';Min=0;Max=1;Default=0;Digits=0;Step=1;Hint='Subdue secondary controls while idle. Disabled by Reduce motion.'}
        CinematicDelay=@{Label='Idle delay (ms)';Min=5000;Max=60000;Default=10000;Digits=0;Step=1000;Hint='Mouse, keyboard or wheel activity restores normal emphasis.'}
    }
}
function Convert-SettingValue([string]$key,$value) {
    $rule=(Get-SettingRules)[$key]
    if($null -eq $rule){throw ('Unknown setting: '+$key)}
    $number=0.0;$text=[Convert]::ToString($value,[Globalization.CultureInfo]::InvariantCulture)
    if(-not [double]::TryParse($text,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$number) -or [double]::IsNaN($number) -or [double]::IsInfinity($number) -or $number -lt $rule.Min -or $number -gt $rule.Max -or ($rule.Digits -eq 0 -and $number -ne [Math]::Floor($number))) {
        throw ($rule.Label+' must be between '+$rule.Min+' and '+$rule.Max+$(if($rule.Digits -eq 0){' (whole numbers).'}else{'.'}))
    }
    return $number.ToString('0.##',[Globalization.CultureInfo]::InvariantCulture)
}
function Get-SettingsDocument {
    $path=Join-Path $Resources 'Settings.ini';$exists=Test-Path -LiteralPath $path
    $bytes=[byte[]]@();if($exists){$bytes=[IO.File]::ReadAllBytes($path)}
    $encoding=New-Object Text.UTF8Encoding($false,$true);$skip=0
    if($bytes.Length -ge 4 -and [BitConverter]::ToString($bytes,0,4) -eq 'FF-FE-00-00'){$encoding=New-Object Text.UTF32Encoding($false,$true,$true);$skip=4}
    elseif($bytes.Length -ge 4 -and [BitConverter]::ToString($bytes,0,4) -eq '00-00-FE-FF'){$encoding=New-Object Text.UTF32Encoding($true,$true,$true);$skip=4}
    elseif($bytes.Length -ge 3 -and [BitConverter]::ToString($bytes,0,3) -eq 'EF-BB-BF'){$encoding=New-Object Text.UTF8Encoding($true,$true);$skip=3}
    elseif($bytes.Length -ge 2 -and [BitConverter]::ToString($bytes,0,2) -eq 'FF-FE'){$encoding=New-Object Text.UnicodeEncoding($false,$true,$true);$skip=2}
    elseif($bytes.Length -ge 2 -and [BitConverter]::ToString($bytes,0,2) -eq 'FE-FF'){$encoding=New-Object Text.UnicodeEncoding($true,$true,$true);$skip=2}
    $text=if($bytes.Length -gt 0){$encoding.GetString($bytes,$skip,($bytes.Length-$skip))}else{''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$fingerprint=[Convert]::ToBase64String($sha.ComputeHash([byte[]]$bytes))}finally{$sha.Dispose()}
    return [pscustomobject]@{Path=$path;Text=$text;Encoding=$encoding;Exists=$exists;Fingerprint=$fingerprint}
}
function Read-ManagerSettings {
    $doc=Get-SettingsDocument;$raw=@{};$section='';$values=@{};$problems=New-Object 'System.Collections.Generic.List[string]'
    foreach($line in [regex]::Split($doc.Text,'\r\n|\n|\r')) {
        if($line -match '^\s*\[([^\]]+)\]\s*$'){$section=$Matches[1]}
        elseif($section -eq 'Settings' -and $line -notmatch '^\s*[;#]' -and $line -match '^\s*([^=]+)=(.*)$'){$raw[$Matches[1].Trim()]=$Matches[2].Trim()}
    }
    $rules=Get-SettingRules
    foreach($key in $rules.Keys) {
        $values[$key]=Convert-SettingValue $key $rules[$key].Default
        if($raw.ContainsKey($key)){try{$values[$key]=Convert-SettingValue $key $raw[$key]}catch{$problems.Add($rules[$key].Label)}}
    }
    return [pscustomobject]@{Document=$doc;Values=$values;Problems=$problems}
}
function Write-ManagerSettings($values,$expected) {
    $normal=@{};foreach($key in (Get-SettingRules).Keys){$normal[$key]=Convert-SettingValue $key $values[$key]}
    $doc=Get-SettingsDocument
    if($null -eq $expected -or $expected.Exists -ne $doc.Exists -or $expected.Fingerprint -ne $doc.Fingerprint){throw 'Settings.ini changed outside this window. Reload settings before saving.'}
    $newline=if($doc.Text.Contains("`r`n")){"`r`n"}elseif($doc.Text.Contains("`n")){"`n"}else{"`r`n"}
    $lines=New-Object 'System.Collections.Generic.List[string]';$section='';$seen=@{};$sections=0
    foreach($line in [regex]::Split($doc.Text,'\r\n|\n|\r')) {
        if($line -match '^\s*\[([^\]]+)\]\s*$') {
            $next=$Matches[1]
            if($section -eq 'Settings'){foreach($key in (Get-SettingRules).Keys){if(-not $seen.ContainsKey($key)){$lines.Add($key+'='+$normal[$key]);$seen[$key]=$true}}}
            $section=$next
            if($section -eq 'Settings'){$sections++;if($sections -gt 1){throw 'Settings.ini contains duplicate Settings sections. Resolve them before saving.'}}
        } elseif($section -eq 'Settings' -and $line -match '^(\s*)([^;#=][^=]*?)\s*=(.*)$') {
            $prefix=$Matches[1];$key=$Matches[2].Trim();$old=$Matches[3]
            if($normal.ContainsKey($key)) {
                # Keep a hand-written inline comment, but on its own valid INI line.
                if($old -match '\s+([;#].*)$'){$lines.Add($prefix+$Matches[1])}
                $lines.Add($prefix+$key+'='+$normal[$key]);$seen[$key]=$true;continue
            }
        }
        $lines.Add($line)
    }
    if($sections -eq 0){$lines.Add('[Settings]')}
    foreach($key in (Get-SettingRules).Keys){if(-not $seen.ContainsKey($key)){$lines.Add($key+'='+$normal[$key])}}
    $text=($lines -join $newline)
    if($doc.Exists -and $text -eq $doc.Text){return $doc}
    $temp=$doc.Path+'.'+[Guid]::NewGuid().ToString('N')+'.new'
    try {
        [IO.File]::WriteAllText($temp,$text,$doc.Encoding)
        $check=Get-SettingsDocument
        if($doc.Exists -ne $check.Exists -or $doc.Fingerprint -ne $check.Fingerprint){throw 'Settings.ini changed during saving. Reload settings and try again.'}
        if($doc.Exists){[IO.File]::Replace($temp,$doc.Path,($doc.Path+'.bak'))}else{[IO.File]::Move($temp,$doc.Path)}
    } finally {if(Test-Path -LiteralPath $temp){[IO.File]::Delete($temp)}}
    return (Get-SettingsDocument)
}
function Read-SavedGameSnapshot {
    Assert-LibrarySchema
    if(-not(Test-Path -LiteralPath $script:libraryPath -PathType Leaf)){throw 'Library.ini is missing.'}
    $text=[IO.File]::ReadAllText($script:libraryPath,[Text.Encoding]::UTF8)
    $entries=New-Object 'System.Collections.Generic.List[object]';$ids=@{};$game=$null
    foreach($line in [regex]::Split($text,'\r\n|\n|\r')) {
        if($line -match '^\[Game:([a-zA-Z0-9_-]+)\]$') {
            $id=$Matches[1];if($ids.ContainsKey($id)){throw ('Duplicate game ID: '+$id)}
            $ids[$id]=$true;$game=New-Game $id;$entries.Add($game)
        } elseif($line -match '^\['){$game=$null}
        elseif($null -ne $game -and $line -match '^([^=]+)=(.*)$') {
            $key=$Matches[1].Trim();if($key -ne 'Id' -and $null -ne $game.PSObject.Properties[$key]){$game.$key=$Matches[2]}
        }
    }
    return [pscustomobject]@{Text=$text;Games=$entries}
}
function Get-LaunchIssue($game) {
    $issue=Get-TargetIssue $game.Target $game.WorkingDirectory;if($issue){return $issue}
    $launch=if($game.Launch){$game.Launch}else{$game.Target}
    if($launch -match '["\r\n]'){return 'The saved launch command contains quotes or line breaks. Save the entry to rebuild it.'}
    if($launch -match '^[a-zA-Z][a-zA-Z0-9+.-]*://'){return (Get-TargetIssue $launch)}
    try {
        if($launch -match '^Shortcuts[/\\]'){$launch=Join-Path $Resources $launch}
        if(-not(Test-Path -LiteralPath ([Environment]::ExpandEnvironmentVariables($launch)) -PathType Leaf)){return 'The saved launch shortcut is missing. Save the entry to rebuild it.'}
    } catch {return 'The saved launch path is invalid or cannot be read. Edit and save the entry.'}
    return ''
}
function Get-CachedArtIssue([string]$relative) {
    if(-not $relative){return @{Level='Warning';Message='No cached image is assigned; the launcher uses its fallback.'}}
    try {
        $usable=Usable-Art $relative
        if(-not $usable){return @{Level='Error';Message='Cached image is missing or incomplete: '+$relative}}
        $probe=New-CroppedBitmap $usable 64 36;try{}finally{$probe.Dispose()}
        if([IO.Path]::GetFullPath($usable) -ne [IO.Path]::GetFullPath((Join-Path $Resources $relative))){return @{Level='Warning';Message='Using the existing repaired cover: '+$relative}}
    } catch {return @{Level='Error';Message='Cached image cannot be decoded: '+$relative}}
    return $null
}
function Open-ManagerFile([string]$relative) {
    $path=Join-Path $Resources $relative
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw ($relative+' has not been created yet.')}
    $start=New-Object Diagnostics.ProcessStartInfo('notepad.exe',('"'+$path+'"'));$start.UseShellExecute=$true
    [Diagnostics.Process]::Start($start)|Out-Null
}

$surface=[Drawing.Color]::FromArgb(17,30,39)
$script:stage='Creating the control center'
$field=[Drawing.Color]::FromArgb(9,21,29)
$ink=[Drawing.Color]::FromArgb(233,242,246)
$muted=[Drawing.Color]::FromArgb(174,197,207)
$mint=[Drawing.Color]::FromArgb(209,250,239)
$warning=[Drawing.Color]::FromArgb(246,207,135)
$errorColor=[Drawing.Color]::FromArgb(255,169,163)
function New-Button([string]$text,[int]$width=120) {
    $b=New-Object Windows.Forms.Button;$b.Text=$text;$b.Size=New-Object Drawing.Size($width,36)
    $b.FlatStyle='Flat';$b.FlatAppearance.BorderColor=[Drawing.Color]::FromArgb(66,88,100)
    $b.FlatAppearance.MouseOverBackColor=[Drawing.Color]::FromArgb(44,65,76)
    $b.FlatAppearance.MouseDownBackColor=[Drawing.Color]::FromArgb(62,86,96)
    $b.BackColor=[Drawing.Color]::FromArgb(29,47,58);$b.ForeColor=$ink;$b.Cursor=[Windows.Forms.Cursors]::Hand
    # Flat buttons use a system disabled-text color unreadable on a dark surface.
    # Redraw only disabled content; keep native Enabled/accessibility and border.
    $b.Add_Paint({
        param($sender,$event)
        if($sender.Enabled){return}
        $inset=[Math]::Max(1,$sender.FlatAppearance.BorderSize)
        $inside=$sender.ClientRectangle;$inside.Inflate(-$inset,-$inset)
        if($inside.Width -le 0 -or $inside.Height -le 0){return}
        $brush=New-Object Drawing.SolidBrush($sender.BackColor)
        try{$event.Graphics.FillRectangle($brush,$inside)}finally{$brush.Dispose()}
        $bounds=$inside
        $bounds.X+=$sender.Padding.Left;$bounds.Y+=$sender.Padding.Top
        $bounds.Width-=$sender.Padding.Horizontal;$bounds.Height-=$sender.Padding.Vertical
        if($bounds.Width -le 0 -or $bounds.Height -le 0){return}
        $flags=[Windows.Forms.TextFormatFlags]::SingleLine -bor [Windows.Forms.TextFormatFlags]::VerticalCenter -bor [Windows.Forms.TextFormatFlags]::EndEllipsis -bor [Windows.Forms.TextFormatFlags]::PreserveGraphicsClipping
        if($sender.TextAlign.ToString().EndsWith('Left')){$flags=$flags -bor [Windows.Forms.TextFormatFlags]::Left}
        elseif($sender.TextAlign.ToString().EndsWith('Right')){$flags=$flags -bor [Windows.Forms.TextFormatFlags]::Right}
        else{$flags=$flags -bor [Windows.Forms.TextFormatFlags]::HorizontalCenter}
        if(-not $sender.UseMnemonic){$flags=$flags -bor [Windows.Forms.TextFormatFlags]::NoPrefix}
        [Windows.Forms.TextRenderer]::DrawText($event.Graphics,$sender.Text,$sender.Font,$bounds,[Drawing.Color]::FromArgb(157,177,189),$flags)
    })
    return $b
}
function New-Label([string]$text,[single]$size=10) {
    $label=New-Object Windows.Forms.Label;$label.Text=$text;$label.Dock='Fill';$label.ForeColor=$muted
    $label.Font=New-Object Drawing.Font('Segoe UI',$size);$label.TextAlign='MiddleLeft';$label.UseMnemonic=$false;return $label
}
function New-Table([int[]]$heights) {
    $table=New-Object Windows.Forms.TableLayoutPanel;$table.Dock='Fill';$table.ColumnCount=1;$table.RowCount=$heights.Count
    $table.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))|Out-Null
    foreach($height in $heights) {
        $style=if($height -eq 0){New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)}else{New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,$height)}
        $table.RowStyles.Add($style)|Out-Null
    }
    return $table
}
function New-PageTable($parent,[int[]]$heights) {
    $table=New-Table $heights;$table.Dock='Top';$table.Height=($heights|Measure-Object -Sum).Sum
    $parent.Controls.Add($table);return $table
}
function Field-Panel([string]$label,$control) {
    $panel=New-Object Windows.Forms.TableLayoutPanel;$panel.Dock='Fill';$panel.ColumnCount=2;$panel.RowCount=1
    $panel.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))|Out-Null
    $panel.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,170)))|Out-Null
    $panel.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))|Out-Null
    $title=New-Label $label;$control.Dock='Fill';$panel.Controls.Add($title,0,0);$panel.Controls.Add($control,1,0);return $panel
}
function New-Textbox {
    $t=New-Object Windows.Forms.TextBox;$t.BackColor=$field;$t.ForeColor=$ink;$t.BorderStyle='FixedSingle'
    $t.Margin=New-Object Windows.Forms.Padding(3,10,3,8);$t.Add_TextChanged({Mark-Dirty});return $t
}
$form=New-Object Windows.Forms.Form;$form.SuspendLayout()
$form.Text='GameHUB 3 (Liquid Glass) - Control center';$form.Size=New-Object Drawing.Size(1340,900)
$form.MinimumSize=New-Object Drawing.Size(1120,780);$form.StartPosition='CenterScreen'
$form.Font=New-Object Drawing.Font('Segoe UI',10);$form.AutoScaleMode=[Windows.Forms.AutoScaleMode]::Dpi
$form.AutoScaleDimensions=New-Object Drawing.SizeF(96,96);$form.BackColor=$surface;$form.ForeColor=$ink
$shell=New-Table @(76,0,38);$shell.Padding=New-Object Windows.Forms.Padding(14,8,14,4);$form.Controls.Add($shell)
$header=New-Object Windows.Forms.TableLayoutPanel;$header.Dock='Fill';$header.ColumnCount=2;$header.RowCount=2
$header.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))|Out-Null
$header.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,112)))|Out-Null
$header.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,38)))|Out-Null
$header.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))|Out-Null
$brand=New-Label 'GameHUB 3 / Control center' 19;$brand.ForeColor=$ink;$header.Controls.Add($brand,0,0)
$buildLabel=New-Label $script:releaseLabel 9;$header.Controls.Add($buildLabel,0,1)
$doneButton=New-Button 'Done' 102;$doneButton.Dock='Fill';$header.Controls.Add($doneButton,1,0);$shell.Controls.Add($header,0,0)
$status=New-Label 'Changes apply when you close the manager.' 9;$shell.Controls.Add($status,0,2)
$body=New-Object Windows.Forms.TableLayoutPanel;$body.Dock='Fill';$body.ColumnCount=2;$body.RowCount=1
$body.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))|Out-Null
$body.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,160)))|Out-Null
$body.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))|Out-Null
$shell.Controls.Add($body,0,1)
$nav=New-Object Windows.Forms.FlowLayoutPanel;$nav.Dock='Fill';$nav.FlowDirection='TopDown';$nav.WrapContents=$false
$nav.Padding=New-Object Windows.Forms.Padding(0,4,8,0);$body.Controls.Add($nav,0,0)
$navButtons=@{}
foreach($name in @('Library','Appearance','Settings','Diagnostics')) {
    $b=New-Button $name 144;$b.Height=46;$b.TextAlign='MiddleLeft';$b.Padding=New-Object Windows.Forms.Padding(10,0,0,0)
    $b.Tag=$name;$b.Add_Click({param($sender,$event);Show-ManagerPage ([string]$sender.Tag)})
    $navButtons[$name]=$b;$nav.Controls.Add($b)
}
$pageHost=New-Object Windows.Forms.Panel;$pageHost.Dock='Fill';$body.Controls.Add($pageHost,1,0)
$split=New-Object Windows.Forms.SplitContainer;$split.Size=New-Object Drawing.Size(1100,700);$split.Dock='Fill'
$split.SplitterDistance=292;$split.Panel1MinSize=0;$split.Panel2MinSize=0
# Fix the sidebar width after the form has completed its initial DPI scaling.
$split.Panel1.Padding=New-Object Windows.Forms.Padding(4,0,8,0);$split.Panel2.Padding=New-Object Windows.Forms.Padding(14,0,0,0)
$pageHost.Controls.Add($split)
$sidebar=New-Table @(34,42,38,0,146);$split.Panel1.Controls.Add($sidebar)
$sidebar.Controls.Add((New-Label 'YOUR GAMES' 10),0,0)
$searchRow=New-Object Windows.Forms.TableLayoutPanel;$searchRow.Dock='Fill';$searchRow.ColumnCount=2;$searchRow.RowCount=1
$searchRow.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))|Out-Null
$searchRow.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))|Out-Null
$searchRow.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,64)))|Out-Null
$searchBox=New-Object Windows.Forms.TextBox;$searchBox.Dock='Fill';$searchBox.BackColor=$field;$searchBox.ForeColor=$ink
$searchBox.Margin=New-Object Windows.Forms.Padding(3,8,3,3);$searchBox.AccessibleName='Search games by title, platform, or target'
$clearSearch=New-Button 'Clear' 58;$clearSearch.Dock='Fill';$searchRow.Controls.Add($searchBox,0,0);$searchRow.Controls.Add($clearSearch,1,0);$sidebar.Controls.Add($searchRow,0,1)
$listCount=New-Label 'Search title, platform, or target' 9;$sidebar.Controls.Add($listCount,0,2)
$list=New-Object Windows.Forms.ListBox;$list.Dock='Fill';$list.DisplayMember='Name';$list.BackColor=$field;$list.ForeColor=$ink
$list.BorderStyle='None';$list.IntegralHeight=$false;$list.HorizontalScrollbar=$true;$sidebar.Controls.Add($list,0,3)
# Reserve three rows so Import Steam and ordering never wrap out of the footer.
$actions=New-Table @(44,44,44);$actions.ColumnCount=2;$actions.ColumnStyles.Clear();$actions.GrowStyle='FixedSize'
for($i=0;$i -lt 2;$i++){$actions.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,50)))|Out-Null}
$actions.Padding=New-Object Windows.Forms.Padding(0,6,0,0)
$newButton=New-Button '+ Add game' 126;$deleteButton=New-Button 'Remove' 126
$upButton=New-Button 'Move up' 126;$downButton=New-Button 'Move down' 126;$steamButton=New-Button 'Import Steam' 258
foreach($b in @($newButton,$deleteButton,$upButton,$downButton,$steamButton)){$b.Dock='Fill'}
$actions.Controls.Add($newButton,0,0);$actions.Controls.Add($deleteButton,1,0)
$actions.Controls.Add($upButton,0,1);$actions.Controls.Add($downButton,1,1)
$actions.Controls.Add($steamButton,0,2);$actions.SetColumnSpan($steamButton,2)
$sidebar.Controls.Add($actions,0,4)
$editorShell=New-Table @(100,0,76);$split.Panel2.Controls.Add($editorShell)
$selection=New-Object Windows.Forms.TableLayoutPanel;$selection.Dock='Fill';$selection.ColumnCount=2;$selection.RowCount=1
$selection.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))|Out-Null
$selection.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,142)))|Out-Null
$selection.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))|Out-Null
$selectedThumb=New-Object Windows.Forms.PictureBox;$selectedThumb.Dock='Fill';$selectedThumb.SizeMode='Zoom';$selectedThumb.BackColor=$field;$selection.Controls.Add($selectedThumb,0,0)
$selectionText=New-Table @(54,0);$selectedTitle=New-Label 'Select a game' 16;$selectedTitle.ForeColor=$ink;$selectedTitle.AutoEllipsis=$true
$selectedSubtitle=New-Label '' 9;$selectionText.Controls.Add($selectedTitle,0,0);$selectionText.Controls.Add($selectedSubtitle,0,1)
$selection.Controls.Add($selectionText,1,0);$editorShell.Controls.Add($selection,0,0)
$editorHost=New-Object Windows.Forms.Panel;$editorHost.Dock='Fill';$editorShell.Controls.Add($editorHost,0,1)
$libraryPage=New-Object Windows.Forms.Panel;$appearancePage=New-Object Windows.Forms.Panel
foreach($page in @($libraryPage,$appearancePage)){$page.Dock='Fill';$page.AutoScroll=$true;$editorHost.Controls.Add($page)}
$layout=New-PageTable $libraryPage @(38,54,54,66,54,54,54,34,62,64)
$layout.Controls.Add((New-Label 'Game details' 13),0,0)
$nameBox=New-Textbox;$layout.Controls.Add((Field-Panel 'Title' $nameBox),0,1)
$platformBox=New-Object Windows.Forms.ComboBox;$platformBox.DropDownStyle='DropDownList';$platformBox.BackColor=$field;$platformBox.ForeColor=$ink
$platformBox.Margin=New-Object Windows.Forms.Padding(3,10,3,8)
foreach($p in @('Steam','Epic','Local','Other')){$platformBox.Items.Add($p)|Out-Null};$platformBox.Add_SelectedIndexChanged({Mark-Dirty})
$layout.Controls.Add((Field-Panel 'Platform' $platformBox),0,2)
function Browse-Row($control,$button) {
    $row=New-Object Windows.Forms.TableLayoutPanel;$row.Dock='Fill';$row.ColumnCount=2;$row.RowCount=1
    $row.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))|Out-Null
    $row.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))|Out-Null
    $row.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,92)))|Out-Null
    $control.Dock='Fill';$button.Anchor='Left,Right';$row.Controls.Add($control,0,0);$row.Controls.Add($button,1,0);return $row
}
$targetBox=New-Textbox;$browseTarget=New-Button 'Browse' 82;$layout.Controls.Add((Field-Panel 'Launch target' (Browse-Row $targetBox $browseTarget)),0,3)
$argsBox=New-Textbox;$layout.Controls.Add((Field-Panel 'EXE arguments' $argsBox),0,4)
$workingBox=New-Textbox;$browseWorking=New-Button 'Browse' 82;$layout.Controls.Add((Field-Panel 'Working directory' (Browse-Row $workingBox $browseWorking)),0,5)
$tagsBox=New-Textbox;$layout.Controls.Add((Field-Panel 'Collections / tags' $tagsBox),0,6)
$tagsHint=New-Label 'Separate tags with commas, for example: Co-op, Favorites to finish. Leave blank for none.' 9;$layout.Controls.Add($tagsHint,0,7)
$targetHint=New-Label '' 9;$layout.Controls.Add($targetHint,0,8)
$help=New-Label 'Use a Steam ID, launch URL, EXE, .lnk, or .url. Local EXEs use a shortcut with the arguments and working directory above. Artwork and framing are on Appearance.' 9;$layout.Controls.Add($help,0,9)
$artLayout=New-PageTable $appearancePage @(38,44,230,54,62,54,90,90,66)
$artLayout.Controls.Add((New-Label 'Artwork & accent' 13),0,0)
$artLayout.Controls.Add((New-Label 'Choose or drop an image. Frame adjusts the focal point and zoom; Save game commits the previews.' 9),0,1)
$artPanel=New-Object Windows.Forms.TableLayoutPanel;$artPanel.Dock='Fill';$artPanel.ColumnCount=2;$artPanel.RowCount=1
$artPanel.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))|Out-Null
for($i=0;$i -lt 2;$i++){$artPanel.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,50)))|Out-Null}
$coverBox=New-Object Windows.Forms.PictureBox;$backgroundBox=New-Object Windows.Forms.PictureBox
$coverBrowse=New-Button 'Choose cover' 160;$backgroundBrowse=New-Button 'Choose background' 160
$coverFraming=New-Button 'Frame...' 80;$backgroundFraming=New-Button 'Frame...' 80
$boxes=@($coverBox,$backgroundBox);$artButtons=@($coverBrowse,$backgroundBrowse);$frameButtons=@($coverFraming,$backgroundFraming);$titles=@('Cover - 16:9','Background - fullscreen')
for($i=0;$i -lt 2;$i++) {
    $group=New-Object Windows.Forms.GroupBox;$group.Text=$titles[$i];$group.ForeColor=$muted;$group.Dock='Fill';$group.Padding=New-Object Windows.Forms.Padding(8)
    $box=$boxes[$i];$box.Dock='Fill';$box.SizeMode='Zoom';$box.BackColor=$field;$box.AllowDrop=$true
    $artActions=New-Object Windows.Forms.TableLayoutPanel;$artActions.Dock='Bottom';$artActions.Height=42;$artActions.ColumnCount=2;$artActions.RowCount=1
    $artActions.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))|Out-Null
    $artActions.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))|Out-Null
    $artActions.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,84)))|Out-Null
    $artButtons[$i].Dock='Fill';$frameButtons[$i].Dock='Fill';$artActions.Controls.Add($artButtons[$i],0,0);$artActions.Controls.Add($frameButtons[$i],1,0)
    $group.Controls.Add($box);$group.Controls.Add($artActions);$artPanel.Controls.Add($group,$i,0)
}
$artLayout.Controls.Add($artPanel,0,2)
$frameSummary=New-Label '' 9;$artLayout.Controls.Add($frameSummary,0,3)
$accentRow=New-Object Windows.Forms.TableLayoutPanel;$accentRow.Dock='Fill';$accentRow.ColumnCount=3;$accentRow.RowCount=1
$accentRow.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))|Out-Null
foreach($width in @(52,0,146)){$style=if($width){New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,$width)}else{New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)};$accentRow.ColumnStyles.Add($style)|Out-Null}
$accentSwatch=New-Object Windows.Forms.Panel;$accentSwatch.Dock='Fill';$accentSwatch.Margin=New-Object Windows.Forms.Padding(4,10,10,10)
$accentLabel=New-Label '' 9;$accentReset=New-Button 'Use default accent' 140;$accentReset.Anchor='Left,Right'
$accentRow.Controls.Add($accentSwatch,0,0);$accentRow.Controls.Add($accentLabel,1,0);$accentRow.Controls.Add($accentReset,2,0);$artLayout.Controls.Add($accentRow,0,4)
$artLayout.Controls.Add((New-Label 'Accent is calculated when artwork is saved. Framing uses the stored original when available. No live blur or continuous image analysis.' 9),0,5)
# Reuse the scrollable Appearance page and the existing Save/Discard transaction.
$mediaPaths=@{};$script:heroMediaDraft=@{};$script:heroMediaChanged=@{};$mediaRow=6
foreach($kind in @('PreviewVideo','Logo')) {
    $group=New-Object Windows.Forms.GroupBox;$group.Dock='Fill';$group.ForeColor=$muted
    $group.Text=if($kind -eq 'Logo'){'Optional Hero logo - PNG'}else{'Optional Hero video - local file'}
    $table=New-Object Windows.Forms.TableLayoutPanel;$table.Dock='Fill';$table.ColumnCount=3;$table.RowCount=2
    $table.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,28)))|Out-Null
    $table.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))|Out-Null
    foreach($width in @(0,170,100)){$style=if($width){New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,$width)}else{New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)};$table.ColumnStyles.Add($style)|Out-Null}
    $path=New-Object Windows.Forms.TextBox;$path.BackColor=$field;$path.ForeColor=$ink;$path.BorderStyle='FixedSingle';$path.Margin=New-Object Windows.Forms.Padding(3,10,3,8);$path.ReadOnly=$true;$path.Text='None';$path.Dock='Fill';$path.AccessibleName=$group.Text+' path';$mediaPaths[$kind]=$path
    $table.Controls.Add($path,0,0);$table.SetColumnSpan($path,3)
    $choose=New-Button $(if($kind -eq 'Logo'){'Choose logo'}else{'Choose preview video'}) 166;$choose.Tag=$kind;$choose.Dock='Fill'
    $remove=New-Button 'Remove' 96;$remove.Tag=$kind;$remove.Dock='Fill'
    $choose.Add_Click({try{Choose-HeroMedia ([string]$this.Tag)}catch{Show-Error $_}})
    $remove.Add_Click({Remove-HeroMedia ([string]$this.Tag)})
    $table.Controls.Add($choose,1,1);$table.Controls.Add($remove,2,1);$group.Controls.Add($table);$artLayout.Controls.Add($group,0,$mediaRow);$mediaRow++
}
$artLayout.Controls.Add((New-Label 'Save copies chosen media into this library. Try H.264 MP4, 1080p / 30 FPS, 5-10 seconds. Close Manager, then hover the focused card to test. Missing or unsupported media uses static artwork/title.' 9),0,8)
$saveArea=New-Table @(28,0);$saveState=New-Label 'Select or add a game.' 9;$saveArea.Controls.Add($saveState,0,0)
$savePanel=New-Object Windows.Forms.FlowLayoutPanel;$savePanel.Dock='Fill';$savePanel.WrapContents=$false
$saveButton=New-Button 'Save game' 140;$discardButton=New-Button 'Discard changes' 160
$savePanel.Controls.Add($saveButton);$savePanel.Controls.Add($discardButton);$saveArea.Controls.Add($savePanel,0,1);$editorShell.Controls.Add($saveArea,0,2)
$settingsPage=New-Object Windows.Forms.Panel;$settingsPage.Dock='Fill';$settingsPage.AutoScroll=$true;$settingsPage.Padding=New-Object Windows.Forms.Padding(16,0,8,0);$pageHost.Controls.Add($settingsPage)
$settingRules=Get-SettingRules
$settingsLayout=New-PageTable $settingsPage (@(44,56)+@(62)*$settingRules.Count+@(56,48))
$settingsLayout.Controls.Add((New-Label 'Settings' 18),0,0)
$settingsLayout.Controls.Add((New-Label 'Adjust launcher scale and motion. Save settings, then close the manager to apply. Monitor placement and other custom settings are preserved.' 10),0,1)
$settingControls=@{};$settingRules=Get-SettingRules;$rowIndex=2
foreach($key in $settingRules.Keys) {
    $rule=$settingRules[$key];$row=New-Object Windows.Forms.TableLayoutPanel;$row.Dock='Fill';$row.ColumnCount=3;$row.RowCount=1
    $row.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))|Out-Null
    foreach($width in @(210,124,0)){$style=if($width){New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,$width)}else{New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)};$row.ColumnStyles.Add($style)|Out-Null}
    if($key -in @('ReduceMotion','HeroVideo','PreviewAudio','PreviewLoop','HeroCinematic')){$control=New-Object Windows.Forms.CheckBox;$control.Text='Enabled';$control.Add_CheckedChanged({Mark-SettingsDirty})}
    else {
        $control=New-Object Windows.Forms.NumericUpDown;$control.Minimum=[decimal]$rule.Min;$control.Maximum=[decimal]$rule.Max
        $control.DecimalPlaces=$rule.Digits;$control.Increment=[decimal]$rule.Step;$control.BackColor=$field;$control.ForeColor=$ink
        $control.Add_ValueChanged({Mark-SettingsDirty});$control.Add_TextChanged({Mark-SettingsDirty})
    }
    $control.Anchor='Left,Right';$control.Margin=New-Object Windows.Forms.Padding(3,10,10,8);$control.AccessibleName=$rule.Label
    $settingControls[$key]=$control;$row.Controls.Add((New-Label $rule.Label),0,0);$row.Controls.Add($control,1,0);$row.Controls.Add((New-Label $rule.Hint 9),2,0)
    $settingsLayout.Controls.Add($row,0,$rowIndex);$rowIndex++
}
$settingsState=New-Label '' 9;$settingsLayout.Controls.Add($settingsState,0,$rowIndex)
$settingsActions=New-Object Windows.Forms.FlowLayoutPanel;$settingsActions.Dock='Fill';$settingsActions.WrapContents=$false
$saveSettings=New-Button 'Save settings' 142;$reloadSettings=New-Button 'Reload settings' 146;$defaultSettings=New-Button 'Restore defaults' 152
foreach($b in @($saveSettings,$reloadSettings,$defaultSettings)){$settingsActions.Controls.Add($b)};$settingsLayout.Controls.Add($settingsActions,0,($rowIndex+1))
$diagnosticsPage=New-Table @(44,144,74,0,100);$diagnosticsPage.Padding=New-Object Windows.Forms.Padding(16,0,8,0);$pageHost.Controls.Add($diagnosticsPage)
$diagnosticsPage.Controls.Add((New-Label 'Diagnostics' 18),0,0)
$healthLabel=New-Label '' 10;$diagnosticsPage.Controls.Add($healthLabel,0,1)
$logDetails=New-Label '' 9;$diagnosticsPage.Controls.Add($logDetails,0,2)
$diagnosticsList=New-Object Windows.Forms.ListView;$diagnosticsList.Dock='Fill';$diagnosticsList.View='Details';$diagnosticsList.FullRowSelect=$true;$diagnosticsList.MultiSelect=$false
$diagnosticsList.HideSelection=$false;$diagnosticsList.BackColor=$field;$diagnosticsList.ForeColor=$ink;$diagnosticsList.BorderStyle='FixedSingle'
foreach($column in @(@('Result',86),@('Game',180),@('Check',100),@('Details',580))){$diagnosticsList.Columns.Add($column[0],[int]$column[1])|Out-Null}
$diagnosticsPage.Controls.Add($diagnosticsList,0,3)
$diagFooter=New-Table @(32,0);$diagnosticState=New-Label 'Run checks to inspect saved launch targets and cached artwork.' 9;$diagFooter.Controls.Add($diagnosticState,0,0)
$diagActions=New-Object Windows.Forms.FlowLayoutPanel;$diagActions.Dock='Fill';$diagActions.WrapContents=$true
$runChecks=New-Button 'Run checks' 115;$cancelChecks=New-Button 'Cancel' 80;$cancelChecks.Enabled=$false;$openIssue=New-Button 'Open selected game' 168;$openIssue.Enabled=$false
$logButton=New-Button 'Manager log' 120;$diagnosticButton=New-Button 'Startup details' 130;$statusButton=New-Button 'Status file' 110
foreach($b in @($runChecks,$cancelChecks,$openIssue,$logButton,$diagnosticButton,$statusButton)){$diagActions.Controls.Add($b)}
$diagFooter.Controls.Add($diagActions,0,1);$diagnosticsPage.Controls.Add($diagFooter,0,4)
# This timer runs only during a requested scan, doing one game/artwork check per tick.
$diagTimer=New-Object Windows.Forms.Timer;$diagTimer.Interval=30;$diagTimer.Add_Tick({Step-Diagnostics})


function Update-GamePresentation {
    $hasGame=$null -ne $script:current;$libraryPage.Enabled=$hasGame;$appearancePage.Enabled=$hasGame
    $saveButton.Enabled=$hasGame -and $script:dirty;$discardButton.Enabled=$saveButton.Enabled;$deleteButton.Enabled=$hasGame
    $index=if($hasGame){$script:games.IndexOf($script:current)}else{-1}
    $canOrder=$hasGame -and -not $searchBox.Text.Trim() -and $script:current.Id -ne $script:newGameId
    $upButton.Enabled=$canOrder -and $index -gt 0;$downButton.Enabled=$canOrder -and $index -lt ($script:games.Count-1)
    $saveButton.Text='Save game'
    if(-not $hasGame){$selectedTitle.Text='Select or add a game';$selectedSubtitle.Text='';$selectedThumb.Image=$null;$saveState.Text='No game selected.';return}
    $selectedTitle.Text=$nameBox.Text;$selectedSubtitle.Text=[string]$platformBox.SelectedItem
    if($script:current.Id -eq $script:newGameId){$selectedSubtitle.Text+=' / New entry'}
    if($list.SelectedIndex -lt 0){$selectedSubtitle.Text+=' / Outside current search'}
    # Reuse the single selected cover preview; no decoding per list row or keypress.
    $selectedThumb.Image=$coverBox.Image
    $saveState.Text=if($script:dirty){'Unsaved game changes'}else{'All game changes saved'}
    $saveState.ForeColor=if($script:dirty){$warning}else{$mint}
    $value=if($script:resetAccent){''}else{$script:current.Accent};$accent=Get-DisplayAccent $value
    $parts=@($accent.Split(',')|ForEach-Object {[int]$_});$accentSwatch.BackColor=[Drawing.Color]::FromArgb($parts[0],$parts[1],$parts[2])
    $accentLabel.Text='Accent / RGB '+$accent
    if($script:resetAccent){$accentLabel.Text+=' / default on Save'}
    elseif($script:coverChanged -or $script:backgroundChanged){$accentLabel.Text+=' / recalculated on Save'}
    elseif(-not $value){$accentLabel.Text+=' / default'}
    $accentReset.Enabled=-not $script:resetAccent -and [bool]($value -or $script:coverChanged -or $script:backgroundChanged)
    $c=$script:coverFrame;$b=$script:backgroundFrame
    $frameSummary.Text=('Cover focus {0:0.#}% / {1:0.#}%, zoom {2:0.#}%   |   Background focus {3:0.#}% / {4:0.#}%, zoom {5:0.#}%' -f ($c.X*100),($c.Y*100),($c.Zoom*100),($b.X*100),($b.Y*100),($b.Zoom*100))
}
function Update-GameValidation {
    if($null -eq $script:current){$targetHint.Text='';return}
    try{$issue=if(-not $nameBox.Text.Trim()){'Enter a game title.'}else{Get-TargetIssue $targetBox.Text $workingBox.Text}}
    catch{$issue=$_.Exception.Message}
    $targetHint.ForeColor=if($issue){$errorColor}else{$muted}
    $targetHint.Text=if($issue){$issue}else{'Target format is valid. URLs and shortcut destinations are not launched or verified here.'}
}
function Show-Game($game) {
    $script:loading=$true;$script:current=$game;$script:dirty=$false;$script:coverChanged=$false;$script:backgroundChanged=$false;$script:resetAccent=$false
    try {
        $selectedThumb.Image=$null
        $script:heroMediaDraft=@{};$script:heroMediaChanged=@{}
        foreach($kind in @('PreviewVideo','Logo')){
            $value=if($null -ne $game){[string]$game.$kind}else{''}
            $script:heroMediaDraft[$kind]=$value;$script:heroMediaChanged[$kind]=$false
            $mediaPaths[$kind].Text=if($value){$value}else{'None - static artwork/title'}
        }
        if($null -eq $game){return}
        $nameBox.Text=$game.Name;$targetBox.Text=$game.Target;$argsBox.Text=$game.Arguments;$workingBox.Text=$game.WorkingDirectory;$tagsBox.Text=$game.Tags
        if(-not $platformBox.Items.Contains($game.Platform)){$platformBox.Items.Add($game.Platform)|Out-Null}
        $platformBox.SelectedItem=$game.Platform
        $script:coverInput=Resolve-Art $game.CoverSource $game.Cover;$script:backgroundInput=Resolve-Art $game.BackgroundSource $game.Background
        $script:coverFrame=Get-ArtFrame $game 'Cover';$script:backgroundFrame=Get-ArtFrame $game 'Background'
        if(-not(Test-Path -LiteralPath $script:coverInput)){$script:coverInput=Join-Path $Resources 'UI/Placeholder.png'}
        if(-not(Test-Path -LiteralPath $script:backgroundInput)){$script:backgroundInput=Join-Path $Resources 'UI/Backdrop.jpg'}
        Set-SafePreview $coverBox (Resolve-Art $game.Cover 'UI/Placeholder.png') $true
        Set-SafePreview $backgroundBox (Resolve-Art $game.Background 'UI/Backdrop.jpg')
    } finally {$script:loading=$false;Update-GamePresentation;Update-GameValidation}
}
function Refresh-List([string]$id='',[bool]$keepEditor=$false) {
    $script:loading=$true;$list.BeginUpdate()
    try {
        $entries=@(Find-LibraryGames $script:games $searchBox.Text)
        if($id -and -not $keepEditor -and @($script:games|Where-Object Id -eq $id).Count -gt 0 -and @($entries|Where-Object Id -eq $id).Count -eq 0){$searchBox.Text='';$entries=$script:games.ToArray()}
        $list.Items.Clear();foreach($g in $entries){$list.Items.Add($g)|Out-Null}
        $index=-1;for($i=0;$i -lt $entries.Count;$i++){if($entries[$i].Id -eq $id){$index=$i;break}}
        if($index -lt 0 -and -not $keepEditor -and $entries.Count -gt 0){$index=0}
        $list.SelectedIndex=$index
        $listCount.Text=([string]$entries.Count+' of '+$script:games.Count+' games')+$(if($searchBox.Text.Trim()){' / Clear search to reorder'}else{' / Custom order'})
    } finally {$list.EndUpdate();$script:loading=$false}
    if($keepEditor){Update-GamePresentation}else{Show-Game $list.SelectedItem}
    if(-not $keepEditor){Clear-ChangedDiagnostics}
}
function Discard-GameChanges {
    $id=if($null -ne $script:current){$script:current.Id}else{''}
    if($id -and $id -eq $script:newGameId){$script:games.Remove($script:current)|Out-Null;$script:newGameId='';$id=''}
    $script:dirty=$false;Refresh-List $id
}
function Show-ManagerPage([string]$name) {
    $split.Visible=$name -in @('Library','Appearance');$settingsPage.Visible=$name -eq 'Settings';$diagnosticsPage.Visible=$name -eq 'Diagnostics'
    # Visible getters are false while the parent form is not yet shown.
    # Branch on the requested page so initial selection is deterministic too.
    if($name -in @('Library','Appearance')){$split.BringToFront();$libraryPage.Visible=$name -eq 'Library';$appearancePage.Visible=$name -eq 'Appearance';if($name -eq 'Library'){$libraryPage.BringToFront()}else{$appearancePage.BringToFront()}}
    elseif($name -eq 'Settings'){$settingsPage.BringToFront()}
    else{$diagnosticsPage.BringToFront();Update-DiagnosticHealth;Clear-ChangedDiagnostics}
    foreach($key in $navButtons.Keys){$navButtons[$key].ForeColor=if($key -eq $name){$mint}else{$ink};$navButtons[$key].FlatAppearance.BorderColor=if($key -eq $name){$mint}else{[Drawing.Color]::FromArgb(66,88,100)}}
}
function Load-SettingsControls {
    $script:settingsLoading=$true
    try {
        $read=Read-ManagerSettings;$script:settingsDocument=$read.Document
        foreach($key in $settingControls.Keys){if($key -in @('ReduceMotion','HeroVideo','PreviewAudio','PreviewLoop','HeroCinematic')){$settingControls[$key].Checked=$read.Values[$key] -eq '1'}else{$settingControls[$key].Value=[decimal]::Parse($read.Values[$key],[Globalization.CultureInfo]::InvariantCulture)}}
        $script:settingsDirty=$false;$saveSettings.Enabled=$read.Problems.Count -gt 0
        $settingsState.ForeColor=if($read.Problems.Count){$warning}else{$muted}
        $settingsState.Text=if($read.Problems.Count){'Invalid stored values: '+($read.Problems -join ', ')+'. Defaults shown; save to repair.'}else{'Settings loaded. Nothing is written until you save.'}
    } catch {$script:settingsDocument=$null;$saveSettings.Enabled=$false;$settingsState.ForeColor=$errorColor;$settingsState.Text='Could not read settings: '+$_.Exception.Message}
    finally{$script:settingsLoading=$false}
}
function Mark-SettingsDirty {
    if($script:settingsLoading){return}
    $script:settingsDirty=$true;$saveSettings.Enabled=$null -ne $script:settingsDocument;$settingsState.ForeColor=$warning;$settingsState.Text='Unsaved settings changes'
}
function Save-SettingsControls {
    # NumericUpDown commits typed text when it loses focus; ValidateChildren also
    # covers a save reached through the window-close confirmation.
    $form.ValidateChildren()|Out-Null
    $values=@{}
    foreach($key in $settingControls.Keys){$values[$key]=if($key -in @('ReduceMotion','HeroVideo','PreviewAudio','PreviewLoop','HeroCinematic')){[int]$settingControls[$key].Checked}else{$settingControls[$key].Value}}
    $script:settingsDocument=Write-ManagerSettings $values $script:settingsDocument
    $script:settingsDirty=$false;$saveSettings.Enabled=$false;$settingsState.ForeColor=$mint;$settingsState.Text='Settings saved. Close the manager to apply them.'
}
function Confirm-SettingsPending {
    if(-not $script:settingsDirty){return $true}
    $answer=[Windows.Forms.MessageBox]::Show('Save your settings changes before closing?','GameHUB 3 (Liquid Glass)',[Windows.Forms.MessageBoxButtons]::YesNoCancel,[Windows.Forms.MessageBoxIcon]::Question)
    if($answer -eq [Windows.Forms.DialogResult]::Cancel){return $false}
    if($answer -eq [Windows.Forms.DialogResult]::Yes){try{Save-SettingsControls}catch{Show-ManagerPage 'Settings';Show-Error $_;return $false}}
    return $true
}
function Invalidate-Diagnostics([string]$message='Run checks to inspect saved launch targets and cached artwork.') {
    $diagTimer.Stop();$script:diagnosticQueue=$null;$script:diagnosticSnapshot=$null;$diagnosticsList.Items.Clear()
    $runChecks.Enabled=$true;$cancelChecks.Enabled=$false;$openIssue.Enabled=$false;$diagnosticState.Text=$message
}
function Clear-ChangedDiagnostics {
    if($null -eq $script:diagnosticSnapshot){return}
    try{if([IO.File]::ReadAllText($script:libraryPath,[Text.Encoding]::UTF8) -ne $script:diagnosticSnapshot){Invalidate-Diagnostics 'Library changed. Run checks again for current results.'}}
    catch{Invalidate-Diagnostics 'Library is unavailable. Run checks again after resolving it.'}
}
function Update-DiagnosticHealth {
    $lines=New-Object 'System.Collections.Generic.List[string]'
    $lines.Add($(if($script:windowReady){'This manager window is ready.'}else{'This manager window is starting.'})+' Opened '+$script:sessionStarted.ToString('HH:mm:ss')+'.')
    try {
        $coord=Read-IniSection (Join-Path $Resources 'Manager-status.ini') 'Manager'
        if($coord.RequestId -eq $RequestId){$lines.Add('Startup coordination: '+$coord.Status+' / current request.')}
        else{$lines.Add('Startup coordination does not match this request; the file may be from another attempt.')}
    } catch {$lines.Add('Startup coordination cannot be read.')}
    $lines.Add('Single-instance lock: '+$(if($created){'owned by this manager.'}else{'not owned.'}))
    try {
        $snapshot=Read-SavedGameSnapshot;$metadata=Read-IniSection $script:libraryPath 'Library';$schema=if($metadata.Version){$metadata.Version}else{'1 (legacy)'}
        $lines.Add('Library.ini: readable / schema '+$schema+' / '+$snapshot.Games.Count+' saved games.')
    } catch {$lines.Add('Library.ini: '+$_.Exception.Message)}
    $lines.Add('Checks use saved entries. URL handlers, installed games, and shortcut destinations are not executed.')
    $healthLabel.Text=$lines -join "`r`n"
    $history=New-Object 'System.Collections.Generic.List[string]'
    $history.Add('Log files are history, not current health. The manager log for this session is finalized on close.')
    foreach($item in @(@('Manager.log',$logButton),@('Manager-diagnostics.txt',$diagnosticButton),@('Manager-status.ini',$statusButton))) {
        $path=Join-Path $Resources $item[0];$item[1].Enabled=Test-Path -LiteralPath $path -PathType Leaf
        if($item[1].Enabled -and $item[0] -ne 'Manager-status.ini'){$history.Add($item[0]+': '+[IO.File]::GetLastWriteTime($path).ToString('yyyy-MM-dd HH:mm:ss'))}
    }
    $logDetails.Text=$history -join "`r`n"
}
function Add-DiagnosticRow([string]$level,$game,[string]$kind,[string]$message) {
    $row=New-Object Windows.Forms.ListViewItem($level)
    $row.SubItems.Add($(if($null -ne $game){$game.Name}else{'Library'}))|Out-Null;$row.SubItems.Add($kind)|Out-Null;$row.SubItems.Add($message)|Out-Null
    if($null -ne $game){$row.Tag=@{Id=$game.Id;Kind=$kind}}
    $row.ForeColor=if($level -eq 'Error'){$errorColor}elseif($level -eq 'Warning'){$warning}else{$mint}
    $diagnosticsList.Items.Add($row)|Out-Null
}
function Start-Diagnostics {
    Invalidate-Diagnostics;Update-DiagnosticHealth
    try {
        $snapshot=Read-SavedGameSnapshot;$script:diagnosticSnapshot=$snapshot.Text
        $script:diagnosticQueue=New-Object 'System.Collections.Generic.List[object]'
        foreach($game in $snapshot.Games){foreach($kind in @('Target','Cover','Background','Blur')){$script:diagnosticQueue.Add(@{Game=$game;Kind=$kind})}}
        $script:diagnosticIndex=0;$script:diagnosticIssues=0;$runChecks.Enabled=$false;$cancelChecks.Enabled=$true
        $diagnosticState.Text='Checking saved library...';$diagTimer.Start()
    } catch {Add-DiagnosticRow 'Error' $null 'Library' $_.Exception.Message;$diagnosticState.Text='Checks could not start.'}
}
function Step-Diagnostics {
    if($null -eq $script:diagnosticQueue){$diagTimer.Stop();return}
    try {
        if($script:diagnosticIndex -ge $script:diagnosticQueue.Count) {
            $diagTimer.Stop();$runChecks.Enabled=$true;$cancelChecks.Enabled=$false
            if($script:diagnosticIssues -eq 0){Add-DiagnosticRow 'OK' $null 'Snapshot' 'No missing launch files or unreadable cached artwork found.'}
            $diagnosticState.Text='Completed '+(Get-Date).ToString('HH:mm:ss')+' / '+$script:diagnosticIssues+' issue(s). Run again after external file changes.'
            $script:diagnosticQueue=$null;Clear-ChangedDiagnostics;return
        }
        $job=$script:diagnosticQueue[$script:diagnosticIndex];$script:diagnosticIndex++
        $issue=if($job.Kind -eq 'Target'){$message=Get-LaunchIssue $job.Game;if($message){@{Level='Error';Message=$message}}}else{Get-CachedArtIssue $job.Game.($job.Kind)}
        if($null -ne $issue){Add-DiagnosticRow $issue.Level $job.Game $job.Kind $issue.Message;$script:diagnosticIssues++}
        $diagnosticState.Text='Checking '+$script:diagnosticIndex+' / '+$script:diagnosticQueue.Count+'...'
    } catch {$diagTimer.Stop();$script:diagnosticQueue=$null;$runChecks.Enabled=$true;$cancelChecks.Enabled=$false;Add-DiagnosticRow 'Error' $null 'Scan' $_.Exception.Message;$diagnosticState.Text='Checks stopped; results are incomplete.'}
}


function Choose-Art([string]$kind,[string]$path='') {
    if($null -eq $script:current){return}
    if(-not $path) {
        $dialog=New-Object Windows.Forms.OpenFileDialog;$dialog.Filter='Images|*.jpg;*.jpeg;*.png;*.bmp';$dialog.Title='Choose '+$kind.ToLower()+' art'
        if($dialog.ShowDialog($form) -ne [Windows.Forms.DialogResult]::OK){$dialog.Dispose();return}
        $path=$dialog.FileName;$dialog.Dispose()
    }
    $frame=[pscustomobject]@{X=0.5;Y=0.5;Zoom=1.0}
    if($kind -eq 'Cover'){Set-Preview $coverBox $path $true $frame;$script:coverInput=$path;$script:coverFrame=$frame;$script:coverChanged=$true}
    else{Set-Preview $backgroundBox $path $false $frame;$script:backgroundInput=$path;$script:backgroundFrame=$frame;$script:backgroundChanged=$true}
    $script:resetAccent=$false;Mark-Dirty
}
function Update-FramePreview {
    $editor=$script:frameEditor
    if($null -eq $editor -or $editor.Loading){return}
    try {
        $frame=[pscustomobject]@{X=[double]$editor.X.Value/100;Y=[double]$editor.Y.Value/100;Zoom=[double]$editor.Zoom.Value/100}
        Set-Preview $editor.Preview $editor.Source ($editor.Kind -eq 'Cover') $frame
        $editor.Frame=$frame;$editor.Apply.Enabled=$true;$editor.Error.Text='Apply stages this framing. Save game commits it to your library.'
    } catch {$editor.Apply.Enabled=$false;$editor.Error.Text='Unable to preview this image. Cancel and choose another image.'}
}
function Edit-ArtFrame([string]$kind) {
    if($null -eq $script:current){return}
    $isCover=$kind -eq 'Cover'
    $path=if($isCover){$script:coverInput}else{$script:backgroundInput}
    $frame=if($isCover){$script:coverFrame}else{$script:backgroundFrame}
    $changed=if($isCover){$script:coverChanged}else{$script:backgroundChanged}
    $hint='Focus: 0% = left / top, 100% = right / bottom. Zoom in to move within a matching 16:9 image.'
    # Old originals may be absent or encoded as WebP under a JPG filename. Start
    # from the usable cache at default framing; never apply an old crop twice.
    $original=Usable-Art $script:current.($kind+'Source')
    $fallback=-not $changed -and (-not $original -or $path -ne $original)
    try {$probe=New-CroppedBitmap $path 160 90 $isCover $frame;$probe.Dispose()}
    catch {if($changed){throw 'The chosen image is no longer readable. Choose it again before framing.'};$fallback=$true}
    if($fallback) {
        $path=Resolve-Art $script:current.$kind $(if($isCover){'UI/Placeholder.png'}else{'UI/Backdrop.jpg'})
        $frame=[pscustomobject]@{X=0.5;Y=0.5;Zoom=1.0}
        $hint='Original unavailable: framing starts from the saved image. Choose the original artwork to recover cropped-out details.'
    }
    $dialog=New-Object Windows.Forms.Form
    $dialog.Text='Frame '+$kind.ToLower();$dialog.ClientSize=New-Object Drawing.Size(780,610);$dialog.MinimumSize=New-Object Drawing.Size(680,570)
    $dialog.StartPosition='CenterParent';$dialog.AutoScaleMode=[Windows.Forms.AutoScaleMode]::Dpi;$dialog.AutoScaleDimensions=New-Object Drawing.SizeF(96,96)
    $dialog.Font=New-Object Drawing.Font('Segoe UI',10);$dialog.BackColor=$surface;$dialog.ForeColor=$ink;$dialog.MinimizeBox=$false;$dialog.MaximizeBox=$false
    $frameLayout=New-Object Windows.Forms.TableLayoutPanel;$frameLayout.Dock='Fill';$frameLayout.Padding=New-Object Windows.Forms.Padding(12);$frameLayout.ColumnCount=1;$frameLayout.RowCount=7
    $frameLayout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))|Out-Null
    foreach($height in @(60,0,42,42,42,44,44)) {
        $style=if($height -eq 0){New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)}else{New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,$height)}
        $frameLayout.RowStyles.Add($style)|Out-Null
    }
    $hintLabel=New-Object Windows.Forms.Label;$hintLabel.Text=$hint;$hintLabel.ForeColor=$muted;$hintLabel.Dock='Fill';$frameLayout.Controls.Add($hintLabel,0,0)
    $preview=New-Object Windows.Forms.PictureBox;$preview.Dock='Fill';$preview.SizeMode='Zoom';$preview.BackColor=$field;$frameLayout.Controls.Add($preview,0,1)
    $numbers=@();$captions=@('Horizontal focus (%)','Vertical focus (%)','Zoom (%)');$values=@(($frame.X*100),($frame.Y*100),($frame.Zoom*100))
    for($i=0;$i -lt 3;$i++) {
        $row=New-Object Windows.Forms.TableLayoutPanel;$row.Dock='Fill';$row.ColumnCount=2;$row.RowCount=1
        $row.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))|Out-Null
        $row.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,220)))|Out-Null
        $row.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))|Out-Null
        $label=New-Object Windows.Forms.Label;$label.Text=$captions[$i];$label.Dock='Fill';$label.TextAlign='MiddleLeft';$label.ForeColor=$muted
        $number=New-Object Windows.Forms.NumericUpDown;$number.Minimum=0;$number.Maximum=100;$number.DecimalPlaces=1;$number.Increment=1
        if($i -eq 2){$number.Minimum=100;$number.Maximum=300;$number.Increment=5}
        $number.Value=[decimal]$values[$i];$number.Dock='Fill';$number.Margin=New-Object Windows.Forms.Padding(3,8,3,3);$number.BackColor=$field;$number.ForeColor=$ink
        $row.Controls.Add($label,0,0);$row.Controls.Add($number,1,0);$frameLayout.Controls.Add($row,0,($i+2));$numbers+=$number
    }
    $message=New-Object Windows.Forms.Label;$message.Dock='Fill';$message.ForeColor=$muted;$frameLayout.Controls.Add($message,0,5)
    $buttons=New-Object Windows.Forms.FlowLayoutPanel;$buttons.Dock='Fill';$buttons.FlowDirection='RightToLeft';$buttons.WrapContents=$false
    $apply=New-Button 'Apply' 95;$cancel=New-Button 'Cancel' 95;$reset=New-Button 'Reset to center' 155
    $apply.DialogResult=[Windows.Forms.DialogResult]::OK;$cancel.DialogResult=[Windows.Forms.DialogResult]::Cancel
    foreach($button in @($apply,$cancel,$reset)){$buttons.Controls.Add($button)}
    $frameLayout.Controls.Add($buttons,0,6);$dialog.Controls.Add($frameLayout);$dialog.AcceptButton=$apply;$dialog.CancelButton=$cancel
    $script:frameEditor=@{Source=$path;Kind=$kind;Preview=$preview;X=$numbers[0];Y=$numbers[1];Zoom=$numbers[2];Frame=$frame;Loading=$false;Apply=$apply;Error=$message;Dialog=$dialog}
    foreach($number in $numbers){$number.Add_ValueChanged({Update-FramePreview})}
    $apply.Add_Click({Update-FramePreview;if(-not $script:frameEditor.Apply.Enabled){$script:frameEditor.Dialog.DialogResult=[Windows.Forms.DialogResult]::None}})
    $reset.Add_Click({
        $script:frameEditor.Loading=$true
        try{$script:frameEditor.X.Value=50;$script:frameEditor.Y.Value=50;$script:frameEditor.Zoom.Value=100}finally{$script:frameEditor.Loading=$false}
        Update-FramePreview
    })
    try {
        Update-FramePreview
        if($dialog.ShowDialog($form) -eq [Windows.Forms.DialogResult]::OK -and $apply.Enabled) {
            $frame=$script:frameEditor.Frame
            if($isCover){Set-Preview $coverBox $path $true $frame;$script:coverInput=$path;$script:coverFrame=$frame;$script:coverChanged=$true}
            else{Set-Preview $backgroundBox $path $false $frame;$script:backgroundInput=$path;$script:backgroundFrame=$frame;$script:backgroundChanged=$true}
            $script:resetAccent=$false;Mark-Dirty
        }
    } finally {if($null -ne $preview.Image){$preview.Image.Dispose()};$dialog.Dispose();$script:frameEditor=$null}
}
$searchBox.Add_TextChanged({if(-not $script:loading){$id=if($null -ne $script:current){$script:current.Id}else{''};Refresh-List $id $true}})
$clearSearch.Add_Click({$searchBox.Text='';$searchBox.Focus()|Out-Null})
$list.Add_SelectedIndexChanged({
    if($script:loading -or $null -eq $list.SelectedItem){return}
    $next=$list.SelectedItem.Id;$old=if($null -ne $script:current){$script:current.Id}else{''}
    if($next -eq $old){return}
    if(-not(Confirm-Pending)){Refresh-List $old $true;return}
    Refresh-List $next
})
$newButton.Add_Click({
    if(-not(Confirm-Pending)){return}
    $g=New-Game;$script:games.Add($g);$script:newGameId=$g.Id;Refresh-List $g.Id
    Show-ManagerPage 'Library';Mark-Dirty;$nameBox.Focus()|Out-Null;$nameBox.SelectAll()
})
$deleteButton.Add_Click({
    if($null -eq $script:current){return}
    if([Windows.Forms.MessageBox]::Show(('Remove "'+$script:current.Name+'" from GameHUB? The installed game and artwork files will not be deleted.'),'Remove entry',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Question) -ne [Windows.Forms.DialogResult]::Yes){return}
    $g=$script:current;$index=$script:games.IndexOf($g);$script:games.RemoveAt($index)
    try {
        if($g.Id -ne $script:newGameId){Write-Library}else{$script:newGameId=''}
        $script:dirty=$false;Refresh-List;$status.Text='Entry removed. Installed game and artwork retained.'
    } catch {$script:games.Insert($index,$g);Show-Error $_}
})
function Move-Entry([int]$direction) {
    if($searchBox.Text.Trim() -or $null -eq $script:current -or $script:current.Id -eq $script:newGameId){return}
    if(-not(Confirm-Pending) -or $null -eq $script:current){return}
    $i=$script:games.IndexOf($script:current);$j=$i+$direction
    if($j -lt 0 -or $j -ge $script:games.Count){return}
    $g=$script:games[$i];$script:games.RemoveAt($i);$script:games.Insert($j,$g)
    try{Write-Library}catch{$script:games.RemoveAt($j);$script:games.Insert($i,$g);throw}
    Refresh-List $g.Id
}
$upButton.Add_Click({try{Move-Entry -1}catch{Show-Error $_}});$downButton.Add_Click({try{Move-Entry 1}catch{Show-Error $_}})
$steamButton.Add_Click({try{$form.UseWaitCursor=$true;Import-Steam}catch{Show-Error $_}finally{$form.UseWaitCursor=$false}})
$browseTarget.Add_Click({
    $dialog=New-Object Windows.Forms.OpenFileDialog;$dialog.Filter='Games and shortcuts|*.exe;*.lnk;*.url';$dialog.DereferenceLinks=$false
    try{if($dialog.ShowDialog($form) -eq [Windows.Forms.DialogResult]::OK){$targetBox.Text=$dialog.FileName;if([IO.Path]::GetExtension($dialog.FileName) -eq '.exe'){$workingBox.Text=Split-Path -Parent $dialog.FileName};$platformBox.SelectedItem='Local';Update-GameValidation}}
    finally{$dialog.Dispose()}
})
$browseWorking.Add_Click({
    $dialog=New-Object Windows.Forms.FolderBrowserDialog;$dialog.Description='Choose the working directory for this EXE'
    try {
        if($workingBox.Text.Trim() -and (Test-Path -LiteralPath $workingBox.Text -PathType Container)){$dialog.SelectedPath=$workingBox.Text}
        if($dialog.ShowDialog($form) -eq [Windows.Forms.DialogResult]::OK){$workingBox.Text=$dialog.SelectedPath;Update-GameValidation}
    } catch {Show-Error $_}finally{$dialog.Dispose()}
})
foreach($box in @($nameBox,$targetBox,$workingBox)){$box.Add_Leave({Update-GameValidation})}
$coverBrowse.Add_Click({try{Choose-Art 'Cover'}catch{Show-Error $_}});$backgroundBrowse.Add_Click({try{Choose-Art 'Background'}catch{Show-Error $_}})
$coverFraming.Add_Click({try{Edit-ArtFrame 'Cover'}catch{Show-Error $_}});$backgroundFraming.Add_Click({try{Edit-ArtFrame 'Background'}catch{Show-Error $_}})
foreach($box in @($coverBox,$backgroundBox)){$box.Add_DragEnter({param($sender,$event);if($event.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)){$event.Effect=[Windows.Forms.DragDropEffects]::Copy}})}
$coverBox.Add_DragDrop({param($sender,$event);try{$files=$event.Data.GetData([Windows.Forms.DataFormats]::FileDrop);if($files.Count -gt 0){Choose-Art 'Cover' $files[0]}}catch{Show-Error $_}})
$backgroundBox.Add_DragDrop({param($sender,$event);try{$files=$event.Data.GetData([Windows.Forms.DataFormats]::FileDrop);if($files.Count -gt 0){Choose-Art 'Background' $files[0]}}catch{Show-Error $_}})
$accentReset.Add_Click({$script:resetAccent=$true;Mark-Dirty})
$saveButton.Add_Click({try{$form.UseWaitCursor=$true;Update-GameValidation;Save-Current}catch{Show-ManagerPage 'Library';Show-Error $_}finally{$form.UseWaitCursor=$false}})
$discardButton.Add_Click({if([Windows.Forms.MessageBox]::Show('Discard unsaved changes to this game?','GameHUB 3 (Liquid Glass)',[Windows.Forms.MessageBoxButtons]::YesNo) -eq [Windows.Forms.DialogResult]::Yes){Discard-GameChanges}})
$saveSettings.Add_Click({try{Save-SettingsControls}catch{Show-Error $_}})
$reloadSettings.Add_Click({
    if($script:settingsDirty -and [Windows.Forms.MessageBox]::Show('Discard unsaved settings and reload the file?','GameHUB 3 (Liquid Glass)',[Windows.Forms.MessageBoxButtons]::YesNo) -ne [Windows.Forms.DialogResult]::Yes){return}
    Load-SettingsControls
})
$defaultSettings.Add_Click({
    $script:settingsLoading=$true
    try{foreach($key in $settingRules.Keys){if($key -in @('ReduceMotion','HeroVideo','PreviewAudio','PreviewLoop','HeroCinematic')){$settingControls[$key].Checked=$settingRules[$key].Default -eq 1}else{$settingControls[$key].Value=[decimal]$settingRules[$key].Default}}}
    finally{$script:settingsLoading=$false}
    Mark-SettingsDirty
})
$runChecks.Add_Click({Start-Diagnostics})
$cancelChecks.Add_Click({$diagTimer.Stop();$script:diagnosticQueue=$null;$runChecks.Enabled=$true;$cancelChecks.Enabled=$false;$diagnosticState.Text='Cancelled '+(Get-Date).ToString('HH:mm:ss')+' / results are incomplete.'})
$diagnosticsList.Add_SelectedIndexChanged({$openIssue.Enabled=$diagnosticsList.SelectedItems.Count -eq 1 -and $null -ne $diagnosticsList.SelectedItems[0].Tag})
$openIssue.Add_Click({
    if($diagnosticsList.SelectedItems.Count -ne 1){return};$entry=$diagnosticsList.SelectedItems[0].Tag
    if($null -eq $entry -or @($script:games|Where-Object Id -eq $entry.Id).Count -eq 0){return}
    if(-not(Confirm-Pending)){return};Refresh-List $entry.Id
    Show-ManagerPage $(if($entry.Kind -eq 'Target'){'Library'}else{'Appearance'})
})
$logButton.Add_Click({try{Open-ManagerFile 'Manager.log'}catch{Show-Error $_}})
$diagnosticButton.Add_Click({try{Open-ManagerFile 'Manager-diagnostics.txt'}catch{Show-Error $_}})
$statusButton.Add_Click({try{Open-ManagerFile 'Manager-status.ini'}catch{Show-Error $_}})
$doneButton.Add_Click({$form.Close()})
$form.Add_FormClosing({param($sender,$event)
    if(-not(Confirm-Pending) -or -not(Confirm-SettingsPending)){$event.Cancel=$true;return}
    $diagTimer.Stop()
})
$form.ResumeLayout($true)
Load-SettingsControls
Show-ManagerPage 'Library'


$script:stage='Loading the selected game'
Refresh-List $SelectId
$script:windowReady=$false
$form.Add_Shown({
    try {
        $script:stage='Game editor open'
        $form.WindowState=[Windows.Forms.FormWindowState]::Normal
        # FixedPanel preserves device pixels, so apply the design width once
        # after autoscaling instead of freezing an unscaled 292-pixel sidebar.
        $layoutScale=$form.CurrentAutoScaleDimensions.Width/96.0
        $splitRoom=[Math]::Max(0,$split.ClientSize.Width-$split.SplitterWidth)
        $rightMinimum=[Math]::Min([int][Math]::Round(490*$layoutScale),$splitRoom)
        $leftMinimum=[Math]::Min([int][Math]::Round(286*$layoutScale),($splitRoom-$rightMinimum))
        $split.SplitterDistance=[Math]::Max($leftMinimum,[Math]::Min([int][Math]::Round(292*$layoutScale),($splitRoom-$rightMinimum)))
        $split.Panel1MinSize=$leftMinimum;$split.Panel2MinSize=$rightMinimum;$split.FixedPanel='Panel1'
        $form.Activate()
        Write-Status 'ready'
        $script:windowReady=$true
    } catch {Write-Output ('GH_ERROR: window startup: '+$_);$form.Close()}
})
$script:stage='Showing the game editor'
$form.ShowDialog()|Out-Null
$diagTimer.Stop();$diagTimer.Dispose();$selectedThumb.Image=$null
foreach($box in @($coverBox,$backgroundBox)){if($null -ne $box.Image){$box.Image.Dispose()}}
$form.Dispose()
Write-Status 'closed'
if($script:windowReady){Write-Output 'GH_OK'}else{Write-Output 'GH_ERROR: editor window did not become ready'}
} catch {
    $problem=$_
    try {Write-Status 'error'}catch{}
    Write-Output $script:releaseLabel
    Write-Output ('GH_ERROR at '+$script:stage+': '+$problem)
    Write-Output $problem.InvocationInfo.PositionMessage
    Write-Output $problem.ScriptStackTrace
    # Rainmeter shows a persistent error banner and links to the full log.
    # An unowned modal MessageBox could otherwise be hidden by the fullscreen skin.
} finally {
    if($null -ne $script:mutex){if($created){$script:mutex.ReleaseMutex()};$script:mutex.Dispose()}
}
