param([string]$dir, [int]$w, [int]$h, [string]$udname)
$edge = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
Get-ChildItem -Path $dir -Filter *.html | ForEach-Object {
  $png = [System.IO.Path]::ChangeExtension($_.FullName, ".png")
  $url = "file:///" + ($_.FullName -replace "\\", "/")
  $ud = Join-Path $dir ("edge-ud-" + $udname)
  Start-Process $edge -ArgumentList @("--headless=new","--user-data-dir=$ud","--hide-scrollbars","--force-device-scale-factor=1","--window-size=$w,$h","--virtual-time-budget=3000","--screenshot=$png",$url) -Wait -NoNewWindow 2>$null
  Write-Output $png
}
