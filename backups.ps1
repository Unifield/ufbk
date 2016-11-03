#    '===============================================================================
#    ' *** MSF Script 
#    ' *** 
#    ' *** --------------------------------------------------------------------------
#    ' *** Filename   : backups.ps1
#    ' *** --------------------------------------------------------------------------
#    ' *** Description:   This script upload a set of files to OwnCloud.
#    ' ***               
#    ' *** --------------------------------------------------------------------------
#    ' *** Version    		: 1.6
#    ' *** Creation Date 	: 23 February 2015
#    ' *** Last Update	    : 22 February 2016
#    ' *** Notes    		: Contact OCG IT Field Support for Information 
#    ' *** Author			: Thierry BRUNI - Damien Heritier
#    ' *** --------------------------------------------------------------------------
#    ' ***   This script is intended to:
#    ' ***   Delete backup files older than $AgeFile days
#    ' ***   Copy backup files to the Cloud (External Backup)
#    ' ***   
#    ' ***  The REAL backup (PostGRES dump) is made by Unifield application.
#    ' ***  
#    ' *** --------------------------------------------------------------------------
#    ' ***
#    '===============================================================================

Add-Type -Assembly System.IO.Compression.FileSystem 

# This method comes from: https://blogs.msdn.microsoft.com/powershell/2007/06/19/get-scriptdirectory-to-the-rescue/
function Get-ScriptDirectory
{
	$Invocation = (Get-Variable MyInvocation -Scope 1).Value
	Split-Path $Invocation.MyCommand.Path
}

# This method comes from: https://gallery.technet.microsoft.com/scriptcenter/ea40c1ef-c856-434b-b8fb-ebd7a76e8d91
function Get-IniContent ($filePath)
{
	$ini = @{}
	switch -regex -file $FilePath
	{
		"^\[(.+)\]" # Section
		{
			$section = $matches[1]
			$ini[$section] = @{}
			$CommentCount = 0
		}
		"^(;.*)$" # Comment
		{
			$value = $matches[1]
			$CommentCount = $CommentCount + 1
			$name = “Comment” + $CommentCount
			$ini[$section][$name] = $value
		} 
		"(.+?)\s*=(.*)" # Key
		{
			$name,$value = $matches[1..2]
			$ini[$section][$name] = $value
		}
	}
	return $ini
}

function Get-Value ($configuration, $group, $name, $type)
{
	$value = $configuration[$group][$name]
	
	if ( $value -eq $null ) {
		Write-Host "No configuration entry in $group / $name"
		Exit 1
	}
	
	$value = $value.Trim()
	
	if( $type -eq [bool] ) {

		if( $value -eq "yes" ){
			$casted_value = $true
		}else{
			if( $value -eq "no" ){
				$casted_value = $false
			}else{
				$casted_value = $null
			}
		}
		
	}else{
		$casted_value = $value -as $type
	}
	
	if ( $casted_value -eq $null ) {
		Write-Host "Bad type for $group / $name ($type expected in $value)"
		Exit 1
	}
	
	return $casted_value
}

function send_email($content)
{
	$error=""
	
	log $UnifieldTaskLogFile $LogInfoDetail "$CloudDirectory" "Sending email: '$content'."
	
	
	# $LatestBackupFile = gci -Path $BackupFolder $Extension | sort LastWriteTime | select -last 1
	# Send Alert Mail Message
	Send-MailMessage -to $To -Subject "UniField Backup FAILURE - External Backup ($LatestBackupFile) from $ServerName did not success" -From $From `
	   -Body $content -ErrorVariable error -SmtpServer $SmtpServer -Credential $Cred -Attachments $UnifieldTaskLogFile

	if($error -ne ""){
		log $UnifieldTaskLogFile $LogErrorDetail "$CloudDirectory" "Cannot send the email."
	}
}

########################################################################
#  Main function
# 
########################################################################
# Main function
# - Test if $BackupFolder exist, if not create it
# - Test if $LatestBackupFile exist, if not send Alert
# - Test if $LatestBackupFile older than $AgeFile send Alert
# - find latest Backup File
# - Zip it
# - upload it to $url
# - Checksum local file and remote file
# - Delete Zip File if upload OK
# - Delete file older than $Age days
# - Send log file to $To if problem
function upload_backup {
	# Test if $BackupFolder exist, if not create it
	if (!(Test-Path -Path $BackupFolder)) {
		send_email("The backup directory doesn't exist")
		return $false
	}
	
	# Find latest file
	try
	{
		$LatestBackupFile = gci -Path $BackupFolder $Extension | sort LastWriteTime | select -last 1
	}catch {
		send_email("No backup found in the backup directory")
		return $false
	}

	#Test $LatestBackupFile if exist
	if ((!(Test-Path -Path ($BackupFolder + "\" + $LatestBackupFile))) -or ($LatestBackupFile -eq $null)) {
		log $UnifieldTaskLogFile $LogErrorDetail "$CloudDirectory" "No Backup File"	
		# Error = true we need to send email alert
		send_email("No backup dir")
		return $false
	}
	
	# Log Info 
	log $UnifieldTaskLogFile $LogInfoDetail "$CloudDirectory" "Latest Backup File= $LatestBackupFile"
	# String modification on LastestBackupgFileName
	$BackupZipFileName = $LatestBackupFile.BaseName
	# Cut the Variable to have only the data before the "-"
	if($BackupZipFileName.IndexOf('-') -ne -1){
		$BackupZipFileName = $BackupZipFileName.Substring(0, $BackupZipFileName.IndexOf('-'))
	}
	# UniqueID : The abbreviated name of the day of the week.
	$UniqueID = Get-Date -format ddd
	# LatestBackupFile name creation : exemple : "OCG_LB_COO-1.zip" - rotation of Backup Name with abbreviated name of the day of the week.
	$BackupZipFileName =  $BackupZipFileName + "-" + $UniqueID + ".zip"	
	# Log Info 
	log $UnifieldTaskLogFile $LogInfoDetail "$CloudDirectory" "Backup Zip File Name= $BackupZipFileName"		
	# Define ZipFilePath (path + file)
	$BackupZipFilePath = $BackupFolder + "\" + $BackupZipFileName
	# test if zip file exist, if it exit we delete it
	if( test-path ($BackupZipFilePath)) { 
		Remove-Item $BackupZipFilePath -force 
		sleep -Seconds 1
	}
	#Prepare zip file
	if(!( test-path ($BackupZipFilePath))) {
			set-content $BackupZipFilePath ("PK" + [char]5 + [char]6 + ("$([char]0)" * 18))
			(dir $BackupZipFilePath).IsReadOnly = $false  
	}
	# Define ZipPackage from $BackupZipFile
	$shellApplication = new-object -com shell.application
	$zipPackage = $shellApplication.NameSpace($BackupZipFilePath)
	# ZIP $LatestBackupFile to $zipPackage
	$zipPackage.CopyHere($LatestBackupFile.FullName) 
	sleep -Seconds 1
	# Defile $BackupZipFile (contain the Backup File in zip format)
	$BackupZipFile = gci -Path $BackupFolder $BackupZipFileName

	#Check if file is locked before continuing the script
	do {
		sleep -Seconds 1
		# Try to access BackupZipFile, if can not, we catch the error
		try {
			# Try to access $BackupZipeFilePath
			$fileLock = [System.io.File]::Open($BackupZipFilePath,  'append', 'Write', 'None')
			# close $fileLock
			$fileLock.Close()
			# All good, the file is not lock any more
			$fileIsLock = $false }
		catch {  $fileIsLock = $true } # Cath the error, declare $FileIsLock has true (file still in use)
	} 	until ( $fileIsLock -eq $false )

	# Log Info 
	log $UnifieldTaskLogFile $LogInfoDetail "$CloudDirectory" "Zip File= $BackupZipFileName"
	
	# Try to upload the $BackupZipFile File to $UrlDav
	try {
		# Start Time 
		$StartTime = $(get-date)
		# Argument for WinSCP
		$WinSCPArgs =  '/loglevel=0 /log="' + $WinSCPLog + '" /command "open -certificate=""' + $SSLCertificate + '"" https://' + $user + ':' + $Unsecure + '@cloud.msf.org/remote.php/webdav/ "  "put ""' + $BackupZipFilePath + '"" ./' + $CloudDirectory + '/ " "exit"'
		#Log Info
		  
		Start-Process -Wait  -FilePath $WinSCPProg -ArgumentList $WinSCPArgs 
		# Calculate $ElapsedTime
		$ElapsedTime = $(get-date) - $StartTime
		# Give readable time
		$ElapsedTimeResult = [string]::format("{0} h {1} min {2} s",$elapsedTime.Hours,$elapsedTime.Minutes,$elapsedTime.Seconds)
		#Log Info
		log $UnifieldTaskLogFile $LogInfoDetail "$CloudDirectory" "Upload $BackupZipFileName OK in $ElapsedTimeResult"	
	}catch {
		send_email("Invalid checksum")
		# Log Error
		log $UnifieldTaskLogFile $LogErrorDetail "$CloudDirectory"  "Error: $_.Exception.Message"
		return $false
	}

	# Remove Zip File
	try {
		Remove-Item -Path $BackupZipFilePath -Force -ErrorAction Stop }
	catch {
		# Log Info 
		log $UnifieldTaskLogFile $LogErrorDetail "$CloudDirectory" "Remove-Item Error: $_.Exception.Message"
	}

	# Log Info 
	log $UnifieldTaskLogFile $LogInfoDetail "$CloudDirectory" "Remove $BackupZipFileName"	

	return $true;
}

########################################################################
#  log function
# 
#  4 Parameters : 
#	$logfile, $logtype,$jobname,$string
########################################################################
# log info in Log File
# Structure : Log file	[date] LOGTYPE:JOBNAME:DATA
# Exemple: [2014-11-27 11:03:44] INFO:KaspUpdate:Update Kaspersky started
# Local Function to log data
function log {
	param (
			[string]$logfile, 
			[string]$logtype,
			[string]$jobname,
			[string]$string
	)
	
	"[" + [DateTime]::Now.ToString("yyyy-MM-dd HH:mm:ss") + "] " + $logtype + ":" + $jobname + ": " + $string  | out-file -Filepath $logfile -append
}

function Good-Internet-Connection
{
	# Ping test to know if we can access the HOSTMASTER
	if(!(Test-Connection -Cn $HOSTPINGTEST -BufferSize 16 -Count 1 -ea 0 -quiet)) {
		log $UnifieldTaskLogFile $LogErrorDetail $CloudDirectory  "Error: No Internet Access - Test (ping)"
		return $false
	} else {

		try
		{
			$s = Measure-Command -Expression { 
				$wclient = New-Object System.Net.WebClient;
				$wclient.CachePolicy = New-Object System.Net.Cache.HttpRequestCachePolicy([System.Net.Cache.HttpRequestCacheLevel]::NoCacheNoStore);
				$wclient.Headers.Add("Cache-Control", "no-cache");
				$a = $wclient.DownloadString($UrlTest);
			}
			$milliseconds = $s.TotalMilliseconds
			$milliseconds = [Math]::Round($milliseconds, 1)
			if( $milliseconds -cle $MaxResponseTime){
				# Log Info 
				log $UnifieldTaskLogFile $LogInfoDetail $CloudDirectory "Internet Access OK"		
				# Start Main function
				return $true
			}else{
				# Log Error
				log $UnifieldTaskLogFile $LogErrorDetail $CloudDirectory  "Error: Internet Access to Slow - The Response time is $milliseconds for a max of $MaxResponseTime."
				return $false
			}
		}catch{
			log $UnifieldTaskLogFile $LogErrorDetail $CloudDirectory  "Error: No Internet Access - Test (web page)"
			return $false
		}
	}	
}

function clean_backups($age)
{
	Get-ChildItem -Path $BackupFolder $Extension -Recurse | Where-Object {(($CurrentDate-$_.CreationTime).days -gt $age)} | Remove-Item -force
	# Log Info 
	log $UnifieldTaskLogFile $LogInfoDetail $CloudDirectory "Remove files older than $AgeFile days"	
}

$compressionLevel = [System.IO.Compression.CompressionLevel]::Optimal
$CurrentDate = Get-Date
$fileIsLock = $true

$script_dir = Get-ScriptDirectory
$ini_path = $script_dir + '\config.ini'

try
{
	$configuration = Get-IniContent $ini_path
} catch
{
	Write-Host "Invalid configuration file"
	Exit 1
}

# configuration related to backups
$AgeFile = Get-Value $configuration "backup" "backup_age" int
$BackupFolder = Get-Value $configuration "backup" "path" string
$Extension = "*." + (Get-Value $configuration "backup" "extension" string)

# configuration related to connectivity checks
$HOSTPINGTEST = Get-Value $configuration "network" "host" string
$TotalNumberTest = Get-Value $configuration "network" "attempts" int
$ping_critical = Get-Value $configuration "network" "ping_critical" bool
$UrlTest = Get-Value $configuration "network" "website" string
$MaxResponseTime = Get-Value $configuration "network" "timeout" int

# configuration related to logging
$To = Get-Value $configuration "logging" "to" string
$From = Get-Value $configuration "logging" "from" string
$SmtpServer = Get-Value $configuration "logging" "smtp" string
$Email64 = Get-Value $configuration "logging" "password_64" string
try{
	$TEMPEmailString  = [System.Convert]::FromBase64String($Email64)
}catch{
	log $UnifieldTaskLogFile $LogInfoDetail $CloudDirectory "Remove files older than $AgeFile days"	
	Write-Host "Bad email password. Bad format"
	Exit 1
}

$UnsecureEmail = [System.Text.Encoding]::UTF8.GetString($TEMPEmailString)
$SecureEmail = ConvertTo-SecureString $UnsecureEmail -asplaintext -Force
$Cred = New-Object System.Management.Automation.PSCredential($From,$SecureEmail)
$ServerName = get-content env:computername

$MSFLogsFolder = Get-Value $configuration "logging" "log_dir" string
$UnifieldTaskLogFile = $MSFLogsFolder + "\" +  [DateTime]::Now.ToString("yyyyMMdd") + "_UnifieldTask.log" 
$LogInfoDetail = "INFO"
$LogDebugDetail = "DEBUG"
$LogErrorDetail = "ERROR"
$LogWarningDetail = "WARNING"

# configuration related to the cloud where we are going to store the backups

# Web Variable
$CloudDirectory = Get-Value $configuration "cloud" "directory" string
$UrlDav = Get-Value $configuration "cloud" "path" string
$SSLCertificate = "80:1e:01:7d:e6:38:be:64:c5:d9:ff:2f:75:4d:66:f6:9c:67:f7:1d"
$user = Get-Value $configuration "cloud" "user" string
$Base64 = Get-Value $configuration "cloud" "password_64" string
try{
	$TEMPString  = [System.Convert]::FromBase64String($Base64)
}catch{
	Write-Host "Bad email password. Bad format"
	Exit 1
}
$Unsecure = [System.Text.Encoding]::UTF8.GetString($TEMPString)

#WinSCP Variable
$WinSCPProg = Get-Value $configuration "cloud" "winscp" string
$WinSCPLog = $MSFLogsFolder + "\" +  [DateTime]::Now.ToString("yyyyMMdd") + "_UnifieldTaskWinSCP.log" 

# We have to check if the internet connection is good enough
for( $check = 0; $check -lt $TotalNumberTest; $check++ ){

	$connection = Good-Internet-Connection
	
	if ( ($connection) -Or (!($ping_critical))){

		if(upload_backup){
			# Delete files older than $AgeFile days
			if ( $AgeFile -ge 0 ){
				clean_backups($AgeFile)
			}
		}
		break;
	}

	# wait 10 minutes before restesting the Internet Test
	sleep -Seconds 600
}
