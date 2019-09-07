param (
	[Parameter(Mandatory)]
    [string]$uri,
	[Parameter(Mandatory)]
    [string]$destination
)

function DownloadISO {

	# Local file storage location
    $localPath = "$env:SystemDrive"

    # Log file
    $logFileName = "CSDownload.log"
    $logFilePath = "$localPath\$logFileName"
	
	if(Test-Path $destination) {
		"Destination path exists. Skipping ISO download" | Tee-Object -FilePath $logFilePath -Append
		return
	}
	
	$destination = Join-Path $env:SystemDrive $destination
	New-Item -Path $destination -ItemType Directory

	$destinationFile = $null
    $result = $false
	# Download ISO
	$retries = 3
	# Stop retrying after download succeeds or all retries attempted
	while(($retries -gt 0) -and ($result -eq $false)) {
		try
		{
			"Downloading ISO from URI: $uri to destination: $destination" | Tee-Object -FilePath $logFilePath -Append
			$isoFileName = [System.IO.Path]::GetFileName($uri)
			$webClient = New-Object System.Net.WebClient
			$_date = Get-Date -Format hh:mmtt
			$destinationFile = "$destination\$isoFileName"
			$webClient.DownloadFile($uri, $destinationFile)
			$_date = Get-Date -Format hh:mmtt
			if((Test-Path $destinationFile) -eq $true) {
				"Downloading ISO file succeeded at $_date" | Tee-Object -FilePath $logFilePath -Append
				$result = $true
			}
			else {
				"Downloading ISO file failed at $_date" | Tee-Object -FilePath $logFilePath -Append
				$result = $false
			}
		} catch [Exception] {
			"Failed to download ISO. Exception: $_" | Tee-Object -FilePath $logFilePath -Append
			$retries--
			if($retries -eq 0) {
				Remove-Item $destination -Force -Confirm:0 -ErrorAction SilentlyContinue
			}
		}
	}
	
	# Extract ISO
	if($result)
    {
        "Mount the image from $destinationFile" | Tee-Object -FilePath $logFilePath -Append
        $image = Mount-DiskImage -ImagePath $destinationFile -PassThru
        $driveLetter = ($image | Get-Volume).DriveLetter

        "Copy files to destination directory: $destination" | Tee-Object -FilePath $logFilePath -Append
		Robocopy.exe ("{0}:" -f $driveLetter) $destination /E | Out-Null
		$ExchangeSetupPath = "C:\PreReq"
		New-Item -Path $ExchangeSetupPath -ItemType Directory -Force
		$UMCAPath = $ExchangeSetupPath + "\UcmaRuntimeSetup.exe"
		$VCRedistPath = $ExchangeSetupPath + "\vcredist_x64.exe"
		(New-Object Net.WebClient).DownloadFile('https://downloadscfa.blob.core.windows.net/downloads/Exchange/UcmaRuntimeSetup.exe', $UMCAPath)
		(New-Object Net.WebClient).DownloadFile('https://downloadscfa.blob.core.windows.net/downloads/Exchange/vcredist_x64.exe', $VCRedistPath)
		
		##Install VCRedist
		[string]$VisC2013Args = "/install /quiet /norestart /log C:\PreReq\VisualC_RedistributablePackages2013-install.txt"
		Start-Process -FilePath $VCRedistPath -ArgumentList $VisC2013Args -Wait
		
		##Install UMCA
		[string]$UMCAArgs = "/install /quiet /norestart /log C:\PreReq\UMCA.txt"
		Start-Process -FilePath $UMCAPath -ArgumentList $UMCAArgs -Wait
		
        "Dismount the image from $destinationFile" | Tee-Object -FilePath $logFilePath -Append
        Dismount-DiskImage -ImagePath $destinationFile
    
        "Delete the temp file: $destinationFile" | Tee-Object -FilePath $logFilePath -Append
		Remove-Item -Path $destinationFile -Force
		<#
		$disk = Get-Disk | where { $_.PartitionStyle -eq "RAW" }
		$diskNumber = $disk.Number
		Initialize-Disk -Number $diskNumber
		New-Partition -DiskNumber $diskNumber -UseMaximumSize -IsActive | Format-Volume -FileSystem NTFS -NewFileSystemLabel "DC" -confirm:$False
		Set-Partition -DiskNumber $diskNumber -PartitionNumber 1 -NewDriveLetter F

		Install-WindowsFeature Server-Media-Foundation, NET-Framework-45-Features, RPC-over-HTTP-proxy, RSAT-Clustering, RSAT-Clustering-CmdInterface, RSAT-Clustering-PowerShell, WAS-Process-Model, Web-Asp-Net45, Web-Basic-Auth, Web-Client-Auth, Web-Digest-Auth, Web-Dir-Browsing, Web-Dyn-Compression, Web-Http-Errors, Web-Http-Logging, Web-Http-Redirect, Web-Http-Tracing, Web-ISAPI-Ext, Web-ISAPI-Filter, Web-Metabase, Web-Mgmt-Service, Web-Net-Ext45, Web-Request-Monitor, Web-Server, Web-Stat-Compression, Web-Static-Content, Web-Windows-Auth, Web-WMI, RSAT-ADDS, BitLocker, snmp-Service, snmp-wmi-provider, Web-Scripting-Tools, Web-Server -IncludeManagementTools

		Install-WindowsFeature AD-Domain-Services -IncludeManagementTools
		Import-Module ADDSDeployment
		$Pass = '!96En0va$Azure' | ConvertTo-SecureString -asPlainText -Force
		Install-ADDSForest -DomainName "EXGAppriverDEV.test" -DatabasePath "F:\NTDS" -SysvolPath "F:\SYSVOL" -LogPath "F:\Logs" -SafeModeAdministratorPassword $Pass -Force -confirm:$False
	#>
	}
    else
    {
		"Failed to download the file after exhaust retry limit" | Tee-Object -FilePath $logFilePath -Append
		Remove-Item $destination -Force -Confirm:0 -ErrorAction SilentlyContinue
        Throw "Failed to download the file after exhaust retry limit"
    }
}

DownloadISO

