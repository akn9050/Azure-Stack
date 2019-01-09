Param (
    [Parameter(Mandatory=$true)]
    [string]
    $Username,

    [switch]
    $EnableDownloadASDK,

    [string]
    $AutoDownloadASDK,

    [string]
    $aadTenantFQDN,

    [string]
    $aadUserName,

    [string]
    $aadUserPassword,
    
    [string]
    $adminPassword,
    
    [string]
    $azureSubscriptionID,
    
    [string]
    $azureTenantID
    )
function cloudlabsprereq
{
$size = Get-PartitionSupportedSize -DriveLetter C
Resize-Partition -DriveLetter C -Size $size.SizeMax
$AdminKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
$UserKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}"
Set-ItemProperty -Path $AdminKey -Name "IsInstalled" -Value 0 -Force
Set-ItemProperty -Path $UserKey -Name "IsInstalled" -Value 0 -Force
Stop-Process -Name Explorer -Force
Write-Host "IE Enhanced Security Configuration (ESC) has been disabled." -ForegroundColor Green
$HKLM = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Zones\3"
$HKCU = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Zones\3"
Set-ItemProperty -Path $HKLM -Name "1803" -Value 0
Set-ItemProperty -Path $HKCU -Name "1803" -Value 0
Enable-PSRemoting -Force
}

cloudlabsprereq

Install-WindowsFeature DNS -IncludeManagementTools

function DownloadWithRetry([string] $Uri, [string] $DownloadLocation, [int] $Retries = 5, [int]$RetryInterval = 10)
{
    while($true)
    {
        try
        {
            Start-BitsTransfer -Source $Uri -Destination $DownloadLocation -DisplayName $Uri
            break
        }
        catch
        {
            $exceptionMessage = $_.Exception.Message
            Write-Host "Failed to download '$Uri': $exceptionMessage"
            if ($retries -gt 0) {
                $retries--
                Write-Host "Waiting $RetryInterval seconds before retrying. Retries left: $Retries"
                Clear-DnsClientCache
                Start-Sleep -Seconds $RetryInterval
 
            }
            else
            {
                $exception = $_.Exception
                throw $exception
            }
        }
    }
}

$defaultLocalPath = "C:\AzureStackOnAzureVM"
$cloudLabsPath = "C:\CloudLabs"
$cloudLabsBlobPath = "https://experienceazure.blob.core.windows.net/templates/azurestack-apptrack"
New-Item -Path $defaultLocalPath -ItemType Directory -Force
New-Item -Path $cloudLabsPath -ItemType Directory -Force


$logFileFullPath = "$defaultLocalPath\postconfig.log"
$writeLogParams = @{
    LogFilePath = $logFileFullPath
}

DownloadWithRetry -Uri "https://raw.githubusercontent.com/SpektraSystems/AzureStack-VM-PoC/master/config.ind" -DownloadLocation "$defaultLocalPath\config.ind"
#Invoke-WebRequest -Uri "https://raw.githubusercontent.com/yagmurs/AzureStack-VM-PoC/development/config.ind" -OutFile "$defaultLocalPath\config.ind"
$gitbranchconfig = Import-Csv -Path $defaultLocalPath\config.ind -Delimiter ","
$gitbranchcode = $gitbranchconfig.branch.Trim()
$gitbranch = "https://raw.githubusercontent.com/SpektraSystems/AzureStack-VM-PoC/$gitbranchcode"

DownloadWithRetry -Uri "$gitbranch/scripts/ASDKHelperModule.psm1" -DownloadLocation "$defaultLocalPath\ASDKHelperModule.psm1"

if (Test-Path "$defaultLocalPath\ASDKHelperModule.psm1")
{
    Import-Module "$defaultLocalPath\ASDKHelperModule.psm1"
}
else
{
    throw "required module $defaultLocalPath\ASDKHelperModule.psm1 not found"   
}

#Disables Internet Explorer Enhanced Security Configuration
Disable-InternetExplorerESC

#Enable Internet Explorer File download
New-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings\Zones\3' -Name 1803 -Value 0 -Force
New-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings\Zones\0' -Name 1803 -Value 0 -Force

New-Item HKLM:\Software\Policies\Microsoft\Windows\CredentialsDelegation\AllowFreshCredentials -Force
New-Item HKLM:\Software\Policies\Microsoft\Windows\CredentialsDelegation\AllowFreshCredentialsWhenNTLMOnly -Force
Set-ItemProperty -LiteralPath HKLM:\Software\Policies\Microsoft\Windows\CredentialsDelegation\AllowFreshCredentials -Name 1 -Value "wsman/*" -Type STRING -Force
Set-ItemProperty -LiteralPath HKLM:\Software\Policies\Microsoft\Windows\CredentialsDelegation\AllowFreshCredentialsWhenNTLMOnly -Name 1 -Value "wsman/*" -Type STRING -Force
Set-ItemProperty -LiteralPath HKLM:\Software\Policies\Microsoft\Windows\CredentialsDelegation -Name AllowFreshCredentials -Value 1 -Type DWORD -Force
Set-ItemProperty -LiteralPath HKLM:\Software\Policies\Microsoft\Windows\CredentialsDelegation -Name AllowFreshCredentialsWhenNTLMOnly -Value 1 -Type DWORD -Force
Set-ItemProperty -LiteralPath HKLM:\Software\Policies\Microsoft\Windows\CredentialsDelegation -Name ConcatenateDefaults_AllowFresh -Value 1 -Type DWORD -Force
Set-ItemProperty -LiteralPath HKLM:\Software\Policies\Microsoft\Windows\CredentialsDelegation -Name ConcatenateDefaults_AllowFreshNTLMOnly -Value 1 -Type DWORD -Force
Set-Item -Force WSMan:\localhost\Client\TrustedHosts "*"
Enable-WSManCredSSP -Role Client -DelegateComputer "*" -Force
Enable-WSManCredSSP -Role Server -Force

#Enable Long path support to workaround ASDK 1802 installation issues on common/helper.psm1 
#https://msdn.microsoft.com/en-us/library/aa365247%28VS.85%29.aspx?f=255&MSPPError=-2147217396#maxpath
#Set-ItemProperty -LiteralPath HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem -Name LongPathsEnabled -Value 1 -Type DWORD -Force

Add-WindowsFeature RSAT-AD-PowerShell, RSAT-ADDS -IncludeAllSubFeature

Install-PackageProvider nuget -Force

Set-ExecutionPolicy unrestricted -Force

#Download Install-ASDK.ps1 (installer)
DownloadWithRetry -Uri "$gitbranch/scripts/Install-ASDK.ps1" -DownloadLocation "$defaultLocalPath\Install-ASDK.ps1"
DownloadWithRetry -Uri "$gitbranch/scripts/Install-ASDKv2.ps1" -DownloadLocation "$defaultLocalPath\Install-ASDKv2.ps1"
DownloadWithRetry -Uri "$cloudLabsBlobPath/scripts/CloudLabsInstall.ps1" -DownloadLocation "$cloudLabsPath\CloudLabsInstall.ps1"
DownloadWithRetry -Uri "$cloudLabsBlobPath/scripts/CloudLabsInstall.bat" -DownloadLocation "$cloudLabsPath\CloudLabsInstall.bat"
DownloadWithRetry -Uri "$cloudLabsBlobPath/scripts/creds.txt" -DownloadLocation "$cloudLabsPath\creds.txt"
DownloadWithRetry -Uri "$cloudLabsBlobPath/scripts/CloudLabsPostInstall.ps1" -DownloadLocation "$cloudLabsPath\CloudLabsPostInstall.ps1"
DownloadWithRetry -Uri "$cloudLabsBlobPath/scripts/CloudLabsTenantTasks-01.ps1" -DownloadLocation "$cloudLabsPath\CloudLabsTenantTasks-01.ps1"
DownloadWithRetry -Uri "$cloudLabsBlobPath/scripts/tenant-visualstudiovm.template.json" -DownloadLocation "$cloudLabsPath\tenant-visualstudiovm.template.json"





(Get-Content -Path "$cloudLabsPath\creds.txt") | ForEach-Object {$_ -Replace "adminPasswordValue", "$adminPassword"} | Set-Content -Path "$cloudLabsPath\creds.txt"
(Get-Content -Path "$cloudLabsPath\creds.txt") | ForEach-Object {$_ -Replace "aadTenantfqdnvalue", "$aadTenantFQDN"} | Set-Content -Path "$cloudLabsPath\creds.txt"
(Get-Content -Path "$cloudLabsPath\creds.txt") | ForEach-Object {$_ -Replace "aadUserNamevalue", "$aadUserName"} | Set-Content -Path "$cloudLabsPath\creds.txt"
(Get-Content -Path "$cloudLabsPath\creds.txt") | ForEach-Object {$_ -Replace "aadUserPasswordvalue", "$aadUserPassword"} | Set-Content -Path "$cloudLabsPath\creds.txt"
(Get-Content -Path "$cloudLabsPath\creds.txt") | ForEach-Object {$_ -Replace "azureSubscriptionIDValue", "$azureSubscriptionID"} | Set-Content -Path "$cloudLabsPath\creds.txt"
(Get-Content -Path "$cloudLabsPath\creds.txt") | ForEach-Object {$_ -Replace "azureTenantIDValue", "$azureTenantID"} | Set-Content -Path "$cloudLabsPath\creds.txt"





#Download ASDK Downloader
DownloadWithRetry -Uri "https://aka.ms/azurestackdevkitdownloader" -DownloadLocation "D:\AzureStackDownloader.exe"

#Download and extract Mobaxterm
DownloadWithRetry -Uri "https://aka.ms/mobaxtermLatest" -DownloadLocation "$defaultLocalPath\Mobaxterm.zip"
#Invoke-WebRequest -Uri "https://aka.ms/mobaxtermLatest" -OutFile "$defaultLocalPath\Mobaxterm.zip"
Expand-Archive -Path "$defaultLocalPath\Mobaxterm.zip" -DestinationPath "$defaultLocalPath\Mobaxterm"
Remove-Item -Path "$defaultLocalPath\Mobaxterm.zip" -Force

if (!($AsdkFileList))
    {
        $AsdkFileList = @("AzureStackDevelopmentKit.exe")
        1..10 | ForEach-Object {$AsdkFileList += "AzureStackDevelopmentKit-$_" + ".bin"}
    }

$latestASDK = (findLatestASDK -asdkURIRoot "https://azurestack.azureedge.net/asdk" -asdkFileList $AsdkFileList)[0]

if ($AutoDownloadASDK -eq "true")
{
    #Download ASDK files (BINs and EXE)
    Write-Log @writeLogParams -Message "Finding available ASDK versions"

    $asdkDownloadPath = "d:\"
    $asdkExtractFolder = "Azure Stack Development Kit"

    $asdkFiles = ASDKDownloader -Version $latestASDK -Destination $asdkDownloadPath

    Write-Log @writeLogParams -Message "$asdkFiles"
      
    #Extracting Azure Stack Development kit files
    
    
    $f = Join-Path -Path $asdkDownloadPath -ChildPath $asdkFiles[0].Split("/")[-1]
    $d = Join-Path -Path $asdkDownloadPath -ChildPath $asdkExtractFolder

    Write-Log @writeLogParams -Message "Extracting Azure Stack Development kit files;"
    Write-Log @writeLogParams -Message "to $d"

    ExtractASDK -File $f -Destination $d

    $vhdxFullPath = Join-Path -Path $d -ChildPath "cloudbuilder.vhdx"
    $foldersToCopy = @('CloudDeployment', 'fwupdate', 'tools')

    if (Test-Path -Path $vhdxFullPath)
    {
        Write-Log @writeLogParams -Message "About to Start Copying ASDK files to C:\"
        Write-Log @writeLogParams -Message "Mounting cloudbuilder.vhdx"
        try {
            $driveLetter = Mount-DiskImage -ImagePath $vhdxFullPath -StorageType VHDX -Passthru | Get-DiskImage | Get-Disk | Get-Partition | Where-Object size -gt 500MB | Select-Object -ExpandProperty driveletter
            Write-Log @writeLogParams -Message "The drive is now mounted as $driveLetter`:"
        }
        catch {
            Write-Log @writeLogParams -Message "an error occured while mounting cloudbuilder.vhdx file"
            Write-Log @writeLogParams -Message $error[0].Exception
            throw "an error occured while mounting cloudbuilder.vhdxf file"
        }

        foreach ($folder in $foldersToCopy)
        {
            Write-Log @writeLogParams -Message "Copying folder $folder to $destPath"
            Copy-Item -Path (Join-Path -Path $($driveLetter + ':') -ChildPath $folder) -Destination C:\ -Recurse -Force
            Write-Log @writeLogParams -Message "$folder done..."
        }
        Write-Log @writeLogParams -Message "Dismounting cloudbuilder.vhdx"
        Dismount-DiskImage -ImagePath $vhdxFullPath       
    } 
    
    Write-Log @writeLogParams -Message "Creating shortcut AAD_Install-ASDK.lnk"
    $WshShell = New-Object -comObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut("$env:ALLUSERSPROFILE\Desktop\AAD_Install-ASDK.lnk")
    $Shortcut.TargetPath = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
    $Shortcut.WorkingDirectory = "$defaultLocalPath"
    $Shortcut.Arguments = "-Noexit -command & {.\Install-ASDKv2.ps1 -DeploymentType AAD}"
    $Shortcut.Save()

    Write-Log @writeLogParams -Message "Creating shortcut ADFS_Install-ASDK.lnk"
    $WshShell = New-Object -comObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut("$env:ALLUSERSPROFILE\Desktop\ADFS_Install-ASDK.lnk")
    $Shortcut.TargetPath = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
    $Shortcut.WorkingDirectory = "$defaultLocalPath"
    $Shortcut.Arguments = "-Noexit -command & {.\Install-ASDKv2.ps1 -DeploymentType ADFS}"
    $Shortcut.Save()
}
else
{
    #Creating desktop shortcut for Install-ASDK.ps1
    if ($EnableDownloadASDK)
    {
        $WshShell = New-Object -comObject WScript.Shell
        $Shortcut = $WshShell.CreateShortcut("$env:ALLUSERSPROFILE\Desktop\AAD_Install-ASDK.lnk")
        $Shortcut.TargetPath = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
        $Shortcut.WorkingDirectory = "$defaultLocalPath"
        $Shortcut.Arguments = "-Noexit -command & {.\Install-ASDKv2.ps1 -DownloadASDK -DeploymentType AAD}"
        $Shortcut.Save()

        $WshShell = New-Object -comObject WScript.Shell
        $Shortcut = $WshShell.CreateShortcut("$env:ALLUSERSPROFILE\Desktop\ADFS_Install-ASDK.lnk")
        $Shortcut.TargetPath = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
        $Shortcut.WorkingDirectory = "$defaultLocalPath"
        $Shortcut.Arguments = "-Noexit -command & {.\Install-ASDKv2.ps1 -DownloadASDK -DeploymentType ADFS}"
        $Shortcut.Save()

        $WshShell = New-Object -comObject WScript.Shell
        $Shortcut = $WshShell.CreateShortcut("$env:ALLUSERSPROFILE\Desktop\Install-ASDK.lnk")
        $Shortcut.TargetPath = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
        $Shortcut.WorkingDirectory = "$defaultLocalPath"
        $Shortcut.Arguments = "-Noexit -command & {.\Install-ASDKv2.ps1 -DownloadASDK}"
        $Shortcut.Save()

        $WshShell = New-Object -comObject WScript.Shell
        $Shortcut = $WshShell.CreateShortcut("$env:ALLUSERSPROFILE\Desktop\Latest_Install-ASDK.lnk")
        $Shortcut.TargetPath = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
        $Shortcut.WorkingDirectory = "$defaultLocalPath"
        $Shortcut.Arguments = "-Noexit -command & {.\Install-ASDKv2.ps1 -DownloadASDK -Version $latestASDK}"
        $Shortcut.Save()
    }
    else
    {
        $WshShell = New-Object -comObject WScript.Shell
        $Shortcut = $WshShell.CreateShortcut("$env:ALLUSERSPROFILE\Desktop\AAD_Install-ASDK.lnk")
        $Shortcut.TargetPath = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
        $Shortcut.WorkingDirectory = "$defaultLocalPath"
        $Shortcut.Arguments = "-Noexit -command & {.\Install-ASDKv2.ps1 -DeploymentType AAD}"
        $Shortcut.Save()

        $WshShell = New-Object -comObject WScript.Shell
        $Shortcut = $WshShell.CreateShortcut("$env:ALLUSERSPROFILE\Desktop\ADFS_Install-ASDK.lnk")
        $Shortcut.TargetPath = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
        $Shortcut.WorkingDirectory = "$defaultLocalPath"
        $Shortcut.Arguments = "-Noexit -command & {.\Install-ASDKv2.ps1 -DeploymentType ADFS}"
        $Shortcut.Save()

        $WshShell = New-Object -comObject WScript.Shell
        $Shortcut = $WshShell.CreateShortcut("$env:ALLUSERSPROFILE\Desktop\Install-ASDK.lnk")
        $Shortcut.TargetPath = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
        $Shortcut.WorkingDirectory = "$defaultLocalPath"
        $Shortcut.Arguments = "-Noexit -command & {.\Install-ASDKv2.ps1"
        $Shortcut.Save()
    }
}

Rename-LocalUser -Name $username -NewName Administrator

Add-WindowsFeature Hyper-V, Failover-Clustering, Web-Server -IncludeManagementTools -Restart
