# Quick introduction

This backup tool offers you a new way to save backups in your UniField
instance.  Every day, it chooses a backup file in the specified
directory, zips it, and uploads it to ownCloud. The backups are kept one week.

You can also use this tool to remove old backups stored locally.

If something goes wrong, the backup tool can send an email to a
specified email address. It also includes logging about the
internet connection.

# Requirements

This tool uses PowerSHELL 4, which requires .NET 4 to be installed as well.

Apart from PowerSHELL, we use WinSCP to upload the backups to the 
cloud. This tool is already included in the package.

# Installation

1. Extract the ZIP file to D:\UFbk. Attention, the zipfile has a
directory named ```ufbk-1.1``` in it. This must be extracted, then
moved to d: and then renamed to ```ufbk```.
2. Open the config.ini file and configure every configuration 
variable to match your OC’s requirements in terms of backup. 
There is an explanation for every configuration variable.
3. Click on “run.bat” to upload a backup to the cloud
4. If it works, then open create_task.bat to turn on the scheduled 
task. By default it’s launched at 9pm. You can change that in the 
task scheduler.

