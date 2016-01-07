<#
.SYNOPSIS
   PowerShell maintenance script for IBM Domino servers
.DESCRIPTION
   Tasks:
	Check if some vital files exists
	Shut down Domino Server
	Remove some databases that have to be build new on regular base
	Compact copy style on all nsf & box databases in data-root only
	Fixup system databases on all databases in data-root only
	Updall system databases on all databases in data-root only
	Remove temp files
	Remove all FTI subdirectories
	Update to latest FP if necessary
	Start Domino Server and make sure its running
	A log file is written and sent by email at the end
	Start any partial maintenance with startup params
	
   ToDo:
	Replace write-host by write-output
	Make logfile more verbos (!)
	Check there are only those NTF really necessary
	Zip all old log files - maybe move them away
	
   Current:
	adapt to new arguments
	
   LAST failed: trying to find the fucking error message for TRY/CATCH at Get-ItemProperty. Giving up temporarily.

   Changelog 07 -> 0.8
	argument order changed
	added argument WAIT
	change argument DOMINO abandoned, domino shutdown is ALWAYS necessary
	added argument UP
	added argument OWNLIST
	copy some system dbs to	BACKUP is true only when backup path is given
	removing temp files is mandatory now
	changed REMOVE to FTDEL what affects FT folders only now
   
.PARAMETER Debug
   Boolean - as it says. debugging gives console out and waits for keystrokes
.EXAMPLE
   Domino_Maintenance.ps1 -debug 1 -wait 1 -up 0 -system 0 -pmail 0 -tmail 0 -global 0 -ownlist 0 -ftdel 0 -logmail 0 -backup "e:\support"
.NOTE
	by C. Ganss, C. Schuette
	V0.8 - 2015 - private property of the authors
#>


param(
	[bool]$debug = $TRUE,			# as it says. debugging gives console out and waits for keystrokes!
	[bool]$wait = $FALSE,			# T => does wait for <enter> in debug mode						F => any debug step do not wait
	[bool]$up = $FALSE,				# T => startup domino after script 								F => do not care about domino
	[bool]$system = $FALSE,			# T => maintenance on system databases and some subfolders, 	F => skip it (data-root)
	[bool]$pmail = $FALSE,			# T => maintenance on folder "mail", 							F => skip it (personal mail)
	[bool]$tmail = $FALSE,			# T => maintenance on folder "mailin", 							F => skip it (team mail)
	[bool]$global = $FALSE,			# T => maintenance on folder "global", 							F => skip it (global applications)
	[bool]$ownlist = $TRUE,			# T => adds a custom list database-ownlist.ind to maintenance	F => skip it (custom list)
	[bool]$ftdel = $FALSE,			# T => delete all FT folder 									F => do not delete FT folder
	[bool]$logmail = $FALSE,		# T => send a mail with logfile at the end, 					F => do not send anything
	[string]$backup = "",			# "" => do not backup/move some system dbs						[string] => move to the given path (if exists)
	[bool]$newlist = $TRUE,
	[bool]$remove = $TRUE

)

<#

		function definition

#>
Function Abort-WithError ($ErrorMsg, $ProcessStep) {
	If ($debug) { Write-Host "Aborting script with error ::$ErrorMsg:: in step ::$ProcessStep::" }
	"Aborting script with error $ErrorMsg in step $ProcessStep" | Out-File $LOG_FILE -Append
	"..END.."  | Out-File $LOG_FILE -Append
	exit
}
Function Warning-WithError ($ErrorMsg, $ProcessStep) {
	If ($debug) { Write-Host "Warning of error ::$ErrorMsg:: in step ::$ProcessStep::" }
	"Warning of error $ErrorMsg in step $ProcessStep" | Out-File $LOG_FILE -Append
	If ($wait) { Read-Host "<enter>:" }
}
Function Debug ($ProcessStep) {
	$nowdate = Get-Date -Format "hh:mm:ss:ms"
	If ($debug) { 
		If ($ProcessStep.StartsWith("Start")) { Write-Host "`n=================================================================="	}
		$nowdate = Get-Date -Format "hh:mm:ss:ms"
		Write-Host $nowdate $ProcessStep
		If ($ProcessStep.StartsWith("End")) { Write-Host -nonewline "==================================================================" }
		If ($wait) { Read-Host "`r<enter>" }
	}
	"$nowdate $ProcessStep" | Out-File $LOG_FILE -Append
}
Function Get-DatabaseList ($WorkFolder) {
	$DatabaseList = "databaselist-"+$WorkFolder+".ind"
	$Files = ""
	If (Test-Path $Dom_Data\$WorkFolder) { $Files += (get-childitem $Dom_Data\$WorkFolder -File -Filter *.nsf).name }
	If ($debug) { Write-Host "Files in $Dom_Data $WorkFolder are $Files" }
	$OutStream = [System.IO.StreamWriter] "$Dom_Data\$DatabaseList"
	Foreach ($File in $Files) { $OutStream.WriteLine($WorkFolder+"\"+$File) }
	$OutStream.Close()
	If ($debug) { 
		Write-Host "Current content of $DatabaseList"
		Get-Content $Dom_Data\$DatabaseList
	}
	$global:DatabaseList = $DatabaseList
}

<#

=======================================	main

#>


### Log File ###
# before doing anything we have to define a logfile
# and say hello
# log all starting parameters
# be sure we can write the logfile
$ProcessStep = "Start Create Logfile"
$LOG_FILE = Get-WMIObject Win32_ComputerSystem | Select-Object -ExpandProperty name
$DATE = Get-Date -format "yyyy-MM-dd-hh-mm-ss"
$LOG_FILE = $LOG_FILE + "_" + $DATE + ".log"
If ($debug) { Write-Host "Logfile Name is $LOG_FILE" }
If (Test-Path $LOG_FILE) { 
	Write-Host "Logfile with my name is already there. Aborting"
	EXIT
}
Write-Host "Start script Domino_Maintenance..." | Out-File $LOG_FILE -Force
If (-Not(Test-Path $LOG_FILE)) {
 	Write-Host "CANNOT WRITE LOGFILE -" + $LOG_FILE +"- ABORTING."
 	EXIT
}
"DEBUG $debug" | Out-File $LOG_FILE -Append
"NEWLIST $newlist" | Out-File $LOG_FILE -Append
"SYSTEM $system" | Out-File $LOG_FILE -Append
"PMAIL $pmail" | Out-File $LOG_FILE -Append
"TMAIL $tmail" | Out-File $LOG_FILE -Append
"GLOBAL $global" | Out-File $LOG_FILE -Append
"DOMINO $domino" | Out-File $LOG_FILE -Append
"REMOVE $remove" | Out-File $LOG_FILE -Append
"BACKUP $backup" | Out-File $LOG_FILE -Append
# if debug is on, list starting parameters to console
if ($debug) {
	if ($debug) 	{ Write-Host DEBUG ON }		else { Write-Host DEBUG OFF }
	if ($newlist) 	{ Write-Host NEWLIST ON }	else { Write-Host NEWLIST OFF }
	if ($system) 	{ Write-Host SYSTEM ON }	else { Write-Host SYSTEM OFF }
	if ($pmail) 	{ Write-Host PMAIL ON }		else { Write-Host PMAIL OFF }
	if ($tmail) 	{ Write-Host TMAIL ON } 	else { Write-Host TMAIL OFF }
	if ($global) 	{ Write-Host GLOBAL ON }	else { Write-Host GLOBAL OFF }
	if ($domino) 	{ Write-Host DOMINO ON }	else { Write-Host DOMINO OFF }
	if ($remove) 	{ Write-Host REMOVE ON }	else { Write-Host REMOVE OFF }
	Write-Host BACKUP $backup
}
$ProcessStep = "End Create Logfile"
Debug $ProcessStep


### Check Path & Files ###
# read the binary and data path from registry
# abort if the are empty
# abort if the general folder structure is not valid
# debug -> print the values
$ProcessStep = "Start Check path"
Debug $ProcessStep

# We need some Try-Catch statements here not to stop the script when no HKLM keys exist
$ErrorActionPreference = "silentlycontinue"
#$ErrorActionPreference = "stop"
Try {
$Dom_Path = (Get-ItemProperty -Path HKLM:\SOFTWARE\Lotus\Domino).Path
Write-Host $Dom_Path >>$LOG_FILE
#	#Abort-WithError "No Registry Path HKLM:\SOFTWARE\Lotus\Domino" $ProcessStep
} Catch {
	Abort-WithError "Binary Path not found in Registry" $ProcessStep
}
if ($Dom_Path.Length -eq 0) {
	Abort-WithError "Binary Path length is 0." $ProcessStep
}
$Dom_Data= (Get-ItemProperty -Path HKLM:\SOFTWARE\Lotus\Domino).DataPath
Write-Host $Dom_Data >>$LOG_FILE
if ($Dom_Data.Length -eq 0) {
	Abort-WithError "Data Path length is 0." $ProcessStep
}
If ($Dom_Data -eq $backup) { Abort-WithError "backup is same as Dom_Data, cannot work" $ProcessStep }
$ProcessStep = "End Check path"
Debug $ProcessStep
# there some basic files that must be available to ebsure we really have a Domino installed here
$ProcessStep = "Start Check Files"
Debug $ProcessStep
If (-Not(Test-Path $Dom_Path\nserver.exe)) {
	if ($debug) { Write-Host "Important files missing nserver.exe" }
	Abort-WithError "Important files missing nserver.exe" $ProcessStep
}
If (-Not(Test-Path $Dom_Path\notes.ini)) {
	if ($debug) { Write-Host "Important files missing notes.ini" }
	Abort-WithError "Important files missing notes.ini" $ProcessStep
}
If (-Not(Test-Path $Dom_Data\names.nsf)) {
	if ($debug) {	Write-Host "Important files missing names.nsf" }
	Abort-WithError "Important files missing names.nsf" $ProcessStep
}
# Check if we can find some transaction protocols
$Dom_Txlog = "G:\LOGS"
If (Test-Path $Dom_Txog\nlogctrl.lfh) {
  $F_Txlog = 1
} else {
  $F_Txlog = 0
}
$F_TxLog = 1
if ($debug) { Write-Host "TxLog Status is $F_Txlog" }
$ProcessStep = "End Check Files"
Debug $ProcessStep


###  Shutdown server  ###
if ($domino) {
	# Get the process IDs of nserver and child processes
	# Shut down the Domino Server
	# And be sure its really all down
	$ProcessStep = "Start Shutdown server"
	Debug $ProcessStep
	$nserviceid = gwmi win32_process | where {$_.ProcessName -eq "nservice.exe"} | foreach {$_.ProcessId} 
	$nserverid = gwmi win32_process | where {$_.ProcessName -eq "nserver.exe"} | foreach {$_.ProcessId} 
	if ($debug) { Write-Host "ServerID $nserviceid and ServiceID $nserverid" }
	$proc = gwmi win32_process | where {$_.ParentProcessId -eq $nserverid} | foreach {$_.ProcessId} | sort
	if ($debug) { Write-Host "ChildProcs :: $procs" }
	$foo = get-service -name "lotus domino server*" | foreach { $_.status }
	if ($debug) { if ($foo -eq "Running") {write-host "Domino server as service running"} }
	stop-service "Lotus Domino Server*"
	write-host "Domino Server Ended? Waiting 60 seconds."
	Start-Sleep -Seconds 60
	foreach ($p in $proc) { stop-process -id $p }
	Write-Host "Try killing nserver-id : " | Out-File $LOG_FILE -Append
	Try {
		stop-process -id $nserverid
		Write-Host $nserverid | Out-File $LOG_FILE -Append
	} Catch {
		Write-Host " was still gone" | Out-File  $LOG_FILE -Append
	}
	stop-process -id $nserviceid
	$foo = get-service -name "lotus domino server*" | foreach { $_.status }
	if ($debug) { if ($foo -eq "Stopped") {write-host "Domino server as service NOT running"} }
	$ProcessStep = "End Shutdown server"
	Debug $ProcessStep
}


# extend tcp port range
# cmd /c netsh int ipv4 set dynamicport tcp start=49152 num=16384


### Maintain databases in data-root ###
$ProcessStep = "Start System Maintenance"
if ($system) {
	Debug $ProcessStep
	# remove unnecessary files
	if ($remove) {
		$ProcessStep = "Start moving files"
		Debug $ProcessStep
		#$CopyLog = $Dom_Data+"\"+$DATE+"_log.nsx"
		#If (Test-Path $Dom_Data\log.nsf) { Copy-Item $Dom_Data\log.nsf $CopyLog >> $LOG_FILE }
		$backup = $backup+"\"+$DATE
		If (Test-Path $backup) {
			$backup = $backup+"-new"
		}
		New-Item -Path $backup -ItemType Directory
		If (Test-Path $backup) {
			$Files = "catalog.nsf", "dbdirman.nsf", "loadmon.ncf", "cluster.ncf", "cldbdir.nsf", "clubusy.nsf", "log.nsf", "~tmpddm.nsf"
			Foreach ($File in $Files) {
				If (Test-Path $Dom_Data\$File) { Move-Item $Dom_Data\$File -Destination $backup >>$LOG_FILE}
			}
		} Else {
			Warning-WithError "Could not create path $backup - move-items skipped." $ProcessStep
		}
		$ProcessStep = "End moving files"
		Debug $ProcessStep
	}
	
	# get a list of all the nsf files in root directory for basic maintenance
	# and write it to a txt file in the data-root 
	if ($newlist) {
		$ProcessStep = "Start Create Database List"
		Debug $ProcessStep
		$DatabaseList = "databaselist.ind"
		$Files = (get-childitem $Dom_Data -File -Filter *.nsf).name
		$Files += (get-childitem $Dom_Data -File -Filter *.box).name
		# no compact on mc_analyze, just takes tooo long
		#If (Test-Path $Dom_Data\Panagenda) { $Files += (get-childitem $Dom_Data\Panagenda -File -Filter *.nsf).fullname }
		If (Test-Path $Dom_Data\we4it) { $Files += (get-childitem $Dom_Data\we4it -File -Filter *.nsf).fullname }
		$OutStream = [System.IO.StreamWriter] "$Dom_Data\$DatabaseList"
		Foreach ($File in $Files) { $OutStream.WriteLine($File) }
		$OutStream.Close()
		If ($debug) { Get-Content $Dom_Data\$DatabaseList }
		$ProcessStep = "End Create Database List"
		Debug $ProcessStep
	}
	
	# get a list of all FTI data directory and subdirectories for deletion
	# and gently remove them
	# MODIFIED & UNTESTED
	if ($remove) {
		$ProcessStep = "Start Remove FTI"
		Debug $ProcessStep
		(get-childitem $Dom_Data -Recurse -Directory -Filter *.ft).fullname | % { 
			Write-Host $_ >>$LOG_FILE
			Remove-Item -Recurse -Force $_ 
		}
		$ProcessStep = "End Remove FTI"
		Debug $ProcessStep
	}

	# start domino database maintenance operations on data root and some subfolders
	$ProcessStep = "Start Compact"
	Debug $ProcessStep
	$DatabaseList = "databaselist.ind"
	If (-Not(Test-Path $Dom_Data\$Databaselist)) {
		Abort-WithError "No Databaselist to work with" $ProcessStep
	}
	# compact -C:copy style -i:ignore errors
	cmd /c echo $Dom_Path\ncompact.exe -C -i $Dom_Data\$DatabaseList >> $LOG_FILE
	cmd /c $Dom_Path\ncompact.exe -C -i $Dom_Data\$DatabaseList
	cmd /c type $Dom_Data\IBM_TECHNICAL_SUPPORT\console.log >> $LOG_FILE
	$ProcessStep = "End Compact"
	Debug $ProcessStep
	# fixup -f:ignore last fixup time -j:run on transactional logged db -L:log all -O:run on open db
	$ProcessStep = "Start Fixup"
	Debug $ProcessStep
	If ( $F_Txlog -eq 1 ) { $FixupTxLog = "-j" } else { $FixupTxLog = "" }
	cmd /c echo $Dom_Path\nfixup.exe -f $FixupTxLog -L -O $Dom_Data\$DatabaseList >> $LOG_FILE
	cmd /c $Dom_Path\nfixup.exe -f $FixupTxLog -L -O $Dom_Data\$DatabaseList
	cmd /c type $Dom_Data\IBM_TECHNICAL_SUPPORT\console.log >> $LOG_FILE
	$ProcessStep = "End Fixup"
	Debug $ProcessStep
	# updall -r:all used views -c:all unused views
	$ProcessStep = "Start Updall Views"
	Debug $ProcessStep
	cmd /c echo $Dom_Path\nupdall.exe -r -c $Dom_Data\$DatabaseList >> $LOG_FILE
	cmd /c $Dom_Path\nupdall.exe -r -c $Dom_Data\$DatabaseList
	cmd /c type $Dom_Data\IBM_TECHNICAL_SUPPORT\console.log >> $LOG_FILE
	$ProcessStep = "End Updall Views"
	Debug $ProcessStep
	# updall -x:all FTI
	$ProcessStep = "Start Updall FTI"
	Debug $ProcessStep
	cmd /c echo $Dom_Path\nupdall.exe -x $Dom_Data\$DatabaseList >> $LOG_FILE
	cmd /c $Dom_Path\nupdall.exe -x $Dom_Data\$DatabaseList
	cmd /c type $Dom_Data\IBM_TECHNICAL_SUPPORT\console.log >> $LOG_FILE
	$ProcessStep = "End Updall FTI"
	Debug $ProcessStep

	# remove temp files from compact etc
	$ProcessStep = "Remove Tempfiles"
	Debug $ProcessStep
	If (Test-Path $Dom_Data\*.tmp) { Remove-Item -Force $Dom_Data\*.tmp >>$LOG_FILE }
	If (Test-Path $Dom_Data\*.ctl) { Remove-Item -Force $Dom_Data\*.ctl >>$LOG_FILE }
	$ProcessStep = "End System Maintenance"
	Debug $ProcessStep
} Else {
	If ($debug) { Write-Host "$ProcessStep skipped." }
}


### Maintain databases in global ###
$dbfolder = "global\phonebook.nsf"
$ProcessStep = "Start $dbfolder Maintenance"
If ($global) {
	Debug $ProcessStep
	# get a list of all the nsf files in directory data/global for maintenance
	# and write it to a txt file in the data-root 
	#if ($newlist) {
		## what i originally wanted was something like $databaselist = get-databaselist $folder $path
		## but this completely insane piece of bullshit called powershell cannot work with a simple
		## statement like return in a function. it sucks. really.
		## so i change content of the global $DatabaseList in the function itself.
		## my brain hurts
	#	Get-Databaselist $dbfolder
	#	If ($debug) { Write-Host "Databaselist is now $DatabaseList" }
	#}
	#If (-Not(Test-Path $Dom_Data\$Databaselist)) {
	#	Abort-WithError "No Databaselist to work with" $ProcessStep
	#}
	# compact -C:copy style -i:ignore errors
	$ProcessStep = "Start Compact $dbfolder"
	Debug $ProcessStep
	$DatabaseList=$dbfolder
	cmd /c echo $Dom_Path\ncompact.exe -C -i $Dom_Data\$DatabaseList >> $LOG_FILE
	cmd /c $Dom_Path\ncompact.exe -C -i $Dom_Data\$DatabaseList
	cmd /c type $Dom_Data\IBM_TECHNICAL_SUPPORT\console.log >> $LOG_FILE
	$ProcessStep = "End Compact $dbfolder"
	Debug $ProcessStep
	# fixup -f:ignore last fixup time -j:run on transactional logged db -L:log all -O:run on open db
	$ProcessStep = "Start Fixup"
	Debug $ProcessStep
	If ( $F_Txlog -eq 1 ) { $FixupTxLog = "-j" } else { $FixupTxLog = "" }
	cmd /c echo $Dom_Path\nfixup.exe -f $FixupTxLog -L -O $Dom_Data\$DatabaseList >> $LOG_FILE
	cmd /c $Dom_Path\nfixup.exe -f $FixupTxLog -L -O $Dom_Data\$DatabaseList
	cmd /c type $Dom_Data\IBM_TECHNICAL_SUPPORT\console.log >> $LOG_FILE
	$ProcessStep = "End Fixup"
	Debug $ProcessStep
	# updall -r:all used views -c:all unused views
	$ProcessStep = "Start Updall Views"
	Debug $ProcessStep
	cmd /c echo $Dom_Path\nupdall.exe -r -c $Dom_Data\$DatabaseList >> $LOG_FILE
	cmd /c $Dom_Path\nupdall.exe -r -c $Dom_Data\$DatabaseList
	cmd /c type $Dom_Data\IBM_TECHNICAL_SUPPORT\console.log >> $LOG_FILE
	$ProcessStep = "End Updall Views"
	Debug $ProcessStep
	# updall -x:all FTI
	$ProcessStep = "Start Updall FTI"
	Debug $ProcessStep
	cmd /c echo $Dom_Path\nupdall.exe -x $Dom_Data\$DatabaseList >> $LOG_FILE
	cmd /c $Dom_Path\nupdall.exe -x $Dom_Data\$DatabaseList
	cmd /c type $Dom_Data\IBM_TECHNICAL_SUPPORT\console.log >> $LOG_FILE
	$ProcessStep = "End Updall FTI"
	Debug $ProcessStep
	$ProcessStep = "End $dbfolder Maintenance"
	Debug $ProcessStep
} Else {
	If ($debug) { Write-Host "$ProcessStep skipped." }
}



### Maintain databases in mail ###
$dbfolder = "mail"
$ProcessStep = "Start $dbfolder Maintenance"
If ($pmail) {
	Debug $ProcessStep
	# get a list of all the nsf files in directory data/global for maintenance
	# and write it to a txt file in the data-root 
	#if ($newlist) {
	#	Get-Databaselist $dbfolder
	#	If ($debug) { Write-Host "Databaselist is now $DatabaseList" }
	#}
	#If (-Not(Test-Path $Dom_Data\$Databaselist)) {
	#	Abort-WithError "No Databaselist to work with" $ProcessStep
	#}
	# compact -C:copy style -i:ignore errors -n:design compact -v:data compact -ZU:LZ1 -daos on:DAOS
	$ProcessStep = "Start Compact $dbfolder"
	Debug $ProcessStep
	$DatabaseList=$dbfolder
	cmd /c echo $Dom_Path\ncompact.exe -C -i -n -v -ZU -daos on $Dom_Data\$DatabaseList >> $LOG_FILE
	cmd /c $Dom_Path\ncompact.exe -C -i -n -v -ZU -daos on $Dom_Data\$DatabaseList
	cmd /c type $Dom_Data\IBM_TECHNICAL_SUPPORT\console.log >> $LOG_FILE
	$ProcessStep = "End Compact $dbfolder"
	Debug $ProcessStep
	# fixup -f:ignore last fixup time -j:run on transactional logged db -L:log all -O:run on open db
	$ProcessStep = "Start Fixup"
	Debug $ProcessStep
	If ( $F_Txlog -eq 1 ) { $FixupTxLog = "-j" } else { $FixupTxLog = "" }
	cmd /c echo $Dom_Path\nfixup.exe -f $FixupTxLog -L -O $Dom_Data\$DatabaseList >> $LOG_FILE
	cmd /c $Dom_Path\nfixup.exe -f $FixupTxLog -L -O $Dom_Data\$DatabaseList
	cmd /c type $Dom_Data\IBM_TECHNICAL_SUPPORT\console.log >> $LOG_FILE
	$ProcessStep = "End Fixup"
	Debug $ProcessStep
	# updall -r:all used views -c:all unused views
	#$ProcessStep = "Start Updall Views"
	#Debug $ProcessStep
	#cmd /c echo $Dom_Path\nupdall.exe -r -c $Dom_Data\$DatabaseList >> $LOG_FILE
	#cmd /c $Dom_Path\nupdall.exe -r -c $Dom_Data\$DatabaseList
	#cmd /c type $Dom_Data\IBM_TECHNICAL_SUPPORT\console.log >> $LOG_FILE
	#$ProcessStep = "End Updall Views"
	#Debug $ProcessStep
	$ProcessStep = "End $dbfolder Maintenance"
	Debug $ProcessStep
} Else {
	If ($debug) { Write-Host "$ProcessStep skipped." }
}


### Maintain databases in mail-in ###
$dbfolder = "mail-in"
$ProcessStep = "Start $dbfolder Maintenance"
If ($tmail) {
	Debug $ProcessStep
	# get a list of all the nsf files in directory data/global for maintenance
	# and write it to a txt file in the data-root 
	#if ($newlist) {
	#	Get-Databaselist $dbfolder
	#	If ($debug) { Write-Host "Databaselist is now $DatabaseList" }
	#}
	#If (-Not(Test-Path $Dom_Data\$Databaselist)) {
	#	Abort-WithError "No Databaselist to work with" $ProcessStep
	#}
	# compact -C:copy style -i:ignore errors -n:design compact -v:data compact -ZU:LZ1 -daos on:DAOS
	$ProcessStep = "Start Compact $dbfolder"
	Debug $ProcessStep
	$DatabaseList=$dbfolder
	cmd /c echo $Dom_Path\ncompact.exe -C -i -n -v -ZU -daos on $Dom_Data\$DatabaseList >> $LOG_FILE
	cmd /c $Dom_Path\ncompact.exe -C -i -n -v -ZU -daos on $Dom_Data\$DatabaseList
	cmd /c type $Dom_Data\IBM_TECHNICAL_SUPPORT\console.log >> $LOG_FILE
	$ProcessStep = "End Compact $dbfolder"
	Debug $ProcessStep
	# fixup -f:ignore last fixup time -j:run on transactional logged db -L:log all -O:run on open db
	$ProcessStep = "Start Fixup"
	Debug $ProcessStep
	If ( $F_Txlog -eq 1 ) { $FixupTxLog = "-j" } else { $FixupTxLog = "" }
	cmd /c echo $Dom_Path\nfixup.exe -f $FixupTxLog -L -O $Dom_Data\$DatabaseList >> $LOG_FILE
	cmd /c $Dom_Path\nfixup.exe -f $FixupTxLog -L -O $Dom_Data\$DatabaseList
	cmd /c type $Dom_Data\IBM_TECHNICAL_SUPPORT\console.log >> $LOG_FILE
	$ProcessStep = "End Fixup"
	Debug $ProcessStep
	# updall -r:all used views -c:all unused views
	#$ProcessStep = "Start Updall Views"
	#Debug $ProcessStep
	#cmd /c echo $Dom_Path\nupdall.exe -r -c $Dom_Data\$DatabaseList >> $LOG_FILE
	#cmd /c $Dom_Path\nupdall.exe -r -c $Dom_Data\$DatabaseList
	#cmd /c type $Dom_Data\IBM_TECHNICAL_SUPPORT\console.log >> $LOG_FILE
	#$ProcessStep = "End Updall Views"
	#Debug $ProcessStep
	$ProcessStep = "End $dbfolder Maintenance"
	Debug $ProcessStep
} Else {
	If ($debug) { Write-Host "$ProcessStep skipped." }
}


### Check for the recent fixpack and install the latest one if necessary ###
$ProcessStep = "Fixpack"
if ($fixpack) {
	$CheckFixpack = "Build=Release 8.5.3FP6"
	$FixpackSource = "E:\support\lotus_domino853FP6_w64.exe"
	$FixpackArguments = "NOUSER -NoNewWindow -Wait"
	If (select-string -path e:\domino\notes.ini -pattern $CheckFixpack) {
		cmd /c echo Latest Fixpack is installed $CheckFixpack >> $LOG_FILE
	} Else {
		If ( Test-Path $FixpackSource ) {
			cmd /c echo Fixpack install started >> $LOG_FILE
			# start-process $FixpackSource $FixpackArguments
			cmd /c type $Dom_Path\UPGRADE.LOG >> $LOG_FILE
		} Else {
			# no fixpack source available
		}
	}
} Else {
	If ($debug) { Write-Host "$ProcessStep skipped." }
}


###  Startup server  ###
if ($domino) {
	# check if all processes are running
	$ProcessStep = "Start Startup Server"
	Debug $ProcessStep
	start-service "Lotus Domino Server*"
	write-host "Domino Server Started? Waiting 60 seconds."
	Start-Sleep -Seconds 60
	$foo = get-service -name "lotus domino server*" | foreach { $_.status }
	if ($foo -eq "Running") {write-host "Domino server as service running"}
	$nserviceid = gwmi win32_process | where {$_.ProcessName -eq "nservice.exe"} | foreach {$_.ProcessId} 
	$nserviceid
	$nserverid = gwmi win32_process | where {$_.ProcessName -eq "nserver.exe"} | foreach {$_.ProcessId} 
	$nserverid
	write-host "ServerID and ServiceID"
	$proc = gwmi win32_process | where {$_.ParentProcessId -eq $nserverid} | foreach {$_.ProcessId} | sort
	$proc
	write-host "ChildProcs."
	write-host "Server Restart Done"
	$ProcessStep = "End Startup Server"
	Debug $ProcessStep
}


<#
#   Send mail with logfile   ###
If ($logmail) {
	$ProcessStep = "Start Send Logfile"
	Debug $ProcessStep
	$file = $LOG_FILE
	$smtpServer = "172.20.1.48"
	$msg = new-object Net.Mail.MailMessage
	$att = new-object Net.Mail.Attachment($file)
	$smtp = new-object Net.Mail.SmtpClient($smtpServer)
	$msg.From = "$LOG_FILE@hellmann.net"
	$msg.To.Add("cganss@de.hellmann.net")
	$msg.Subject = "Domino Maintenance $DATE $LOG_FILE"
	$msg.Body = "LOGFILE attached"
	$msg.Attachments.Add($att)
	$smtp.Send($msg)
	$att.Dispose()
	$ProcessStep = "End Send Logfile""
	Debug $ProcessStep
}
#>

<#

================================================ end

#>
