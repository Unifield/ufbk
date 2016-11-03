schtasks /create /F /tn UnifieldScheduledTask /RU SYSTEM /SC DAILY /st 21:00 /tr "c:\windows\system32\WindowsPowerShell\v1.0\powershell.exe -executionpolicy ByPass -File '%~dp0\backups.ps1 ' "
pause
