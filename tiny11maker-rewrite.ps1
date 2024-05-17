using namespace System.Console
using namespace System.Diagnostics
using namespace System.Environment
using namespace System.Management.Automation
using namespace System.Security.AccessControl
using namespace Microsoft.Win32

[Console]::Title = "tiny11 builder (Dev_17-05-24)"
#$Host.UI.RawUI.WindowTitle = "tiny11 builder"

if ((Get-ExecutionPolicy) -ne 'Unrestricted') { Set-ExecutionPolicy Unrestricted -Scope CurrentUser -Confirm:$false }

. .\Helpers.ps1
ElevateIfRequired

$newLine = [Environment]::NewLine
$OSDrive = $env:SystemDrive
$workingDir = "$PSScriptRoot\tiny11"
$arch = $Env:PROCESSOR_ARCHITECTURE
$packagePrefixes = 'Clipchamp.Clipchamp_', 'Microsoft.BingNews_', 'Microsoft.BingWeather_', 'Microsoft.GamingApp_', 'Microsoft.GetHelp_', 'Microsoft.Getstarted_', 'Microsoft.MicrosoftOfficeHub_', 'Microsoft.MicrosoftSolitaireCollection_', 'Microsoft.People_', 'Microsoft.PowerAutomateDesktop_', 'Microsoft.Todos_', 'Microsoft.WindowsAlarms_', 'microsoft.windowscommunicationsapps_', 'Microsoft.WindowsFeedbackHub_', 'Microsoft.WindowsMaps_', 'Microsoft.WindowsSoundRecorder_', 'Microsoft.Xbox.TCUI_', 'Microsoft.XboxGamingOverlay_', 'Microsoft.XboxGameOverlay_', 'Microsoft.XboxSpeechToTextOverlay_', 'Microsoft.YourPhone_', 'Microsoft.ZuneMusic_', 'Microsoft.ZuneVideo_', 'MicrosoftCorporationII.MicrosoftFamily_', 'MicrosoftCorporationII.QuickAssist_', 'MicrosoftTeams_', 'Microsoft.549981C3F5F10_'
$drives = Get-PSDrive | Select-Object -ExpandProperty 'Root' | Select-String '^[a-z]:\\$' | ForEach-Object {$_ -replace "\\"} | Where-Object { $_ -ne $OSDrive }

New-Item -ItemType Directory -Force -Path "$workingDir\sources" > $null
Start-Transcript -Path "$workingDir\tiny11.log"

Set-PSRepository PSGallery -InstallationPolicy Trusted
if (Get-Module -ListAvailable -Name PSMenu) { Import-Module PSMenu } else { Install-Module PSMenu -Scope CurrentUser -SkipPublisherCheck -Confirm:$false }
if (Get-Module -ListAvailable -Name PSWriteColor) { Import-Module PSWriteColor } else { Install-Module PSWriteColor -Scope CurrentUser -SkipPublisherCheck -Confirm:$false }
. .\Copy-ItemWithProgress.ps1

Clear-Host

function selectDrive() {
    Write-Host "$([Console]::Title)$newLine${newLine}Please select drive letter for the Windows 11 image:"
    $drive = Show-Menu $drives

    if ((Test-Path "$drive\sources\boot.wim") -eq $false -or (Test-Path "$drive\sources\install.wim") -eq $false) {
        Write-Color "$newLine${newLine}Error: Can't find Windows installation files in '${drive}\'${newLine}Please select the correct drive letter.$newLine$newLine","Press any key to return to selection..." -Color Red,White
        [Console]::ReadKey()
        Clear-Host
        selectDrive
    } elseif ((Test-Path "$drive\sources\install.esd") -eq $true) {
        $removeESDOnCopy = $true
        Write-Host "$newLine${newLine}Found 'install.esd', needs to be converted to WIM."
        $i = & dism /get-wiminfo /wimfile:"$drive\sources\install.esd" | Where-Object {$_ -match "Name : "} | Foreach-Object { $_ -replace '\S.*.:.' }
        $images = [array]($i | Foreach-Object { "$($i.IndexOf($_)+1) - $_" })
        
        if ($images.Count -eq 1) {
            $index = 1
        } else {
            Write-Host "$newLine${$newLine}Please select the image index:"
            $index = Show-Menu $images
        }

        Clear-Host
        Write-Host "$([Console]::Title)$newLine${newLine}Converting image to WIM...$newLine${$newLine}"
        & dism /Export-Image /SourceImageFile:"$drive\sources\install.esd" /SourceIndex:$index /DestinationImageFile:"$workingDir\sources\install.wim" /Compress:max /CheckIntegrity
    }

    copyFiles($removeESDOnCopy)
}

function copyFiles($removeESDOnCopy) {
    Clear-Host
    Write-Progress -Id 0 -Activity "Preparing to build tiny11" -Status "Copying Windows image..." -PercentComplete 0
    do { Copy-ItemWithProgress $drive $workingDir -ProgressID 0 -OutVariable $status } until ($status)

    if ($removeESDOnCopy -eq $true) {
        Set-ItemProperty -Path "$workingDir\sources\install.esd" -Name IsReadOnly -Value $false > $null 2>&1
        Remove-Item "$workingDir\sources\install.esd" > $null 2>&1
    }

    if ([string]::IsNullOrEmpty($index)) {
        $i = & dism /get-wiminfo /wimfile:"$workingDir\sources\install.wim" | Where-Object {$_ -match "Name : "} | Foreach-Object { $_ -replace '\S.*.:.' }
        $images = [array]($i | Foreach-Object { "$($i.IndexOf($_)+1) - $_" })
        
        if ($images.Count -eq 1) {
            $index = 1
        } else {
            Write-Host "$([Console]::Title)$newLine${$newLine}Please select the image index:"
            $index = Show-Menu $images
        }
    }

    startBuild
}

function startBuild() {
    Clear-Host
    Write-Host "$([Console]::Title)$newLine${$newLine}"
    $job = Start-Job -Name "startBuild" -ScriptBlock {
        TakeOwnership("$workingDir\sources\install.wim")
        try { Set-ItemProperty -Path "$workingDir\sources\install.wim" -Name IsReadOnly -Value $false -ErrorAction Stop > $null 2>&1}
        catch {} # This block will catch the error and suppress it.

        New-Item -ItemType Directory -Force -Path "$workingDir\scratchdir" > $null
        & dism /mount-image /imagefile:"$workingDir\sources\install.wim" /index:$index /mountdir:"$workingDir\scratchdir" | ForEach-Object {
            Write-Progress -Activity "Mounting install image..." -Status $_
        }

        Write-Progress -Activity "Getting default system UI language..." -Status ""
        $languageCode = $(& dism /Get-Intl /Image:"$workingDir\scratchdir") -split '\n' | Where-Object { if ($_ -match 'Default system UI language : ([a-zA-Z]{2}-[a-zA-Z]{2})') { $matches[1] }}
        if ($languageCode) {
            Write-Host "Info: Found language code: $languageCode"
        } else {
            Write-Host "Error: Default system UI language code not found."
        }

        Write-Progress -Activity "Getting image architecture..."
        $imgArch = & dism /get-wiminfo /wimfile:"$workingDir\sources\install.wim" /index:1 | Foreach-Object { if ($_ -match "Architecture : (.*)") { $matches[1] }}
        if ($imgArch -eq 'x64') {
            $imgArch = 'amd64'
            Write-Host "Info: Found image architecture: $imgArch"
        } elseif (-not $arch) {
            Write-Host "Error: Image architecture not found."
        }

        Write-Progress -Activity "Preparing to remove preinstalled packages..." -Status "Getting preinstalled packages"
        $packages = & dism /image:"$workingDir\scratchdir" /Get-ProvisionedAppxPackages | Foreach-Object { if ($_ -match "PackageName : (.*)") { $matches[1] }}
        Write-Progress -Status "Selecting packages to remove..."
        $packagesToRemove = $packages | Foreach-Object { $packagePrefixes -contains "$_" }
        Write-Progress -Activity "Removing packages..." -Status ""
        $packagesToRemove | ForEach-Object {
            Write-Progress -Status "($($packagesToRemove.IndexOf($_) + 1) of $($packagesToRemove.Count + 1)) $_"
            & dism /image:"$workingDir\scratchdir" /Remove-ProvisionedAppxPackage /PackageName:"$_"  > $null 2>&1
        }
        
        Write-Progress -Status "Removing Microsoft Edge"
        Remove-Item -Path "$workingDir\scratchdir\Program Files (x86)\Microsoft\Edge" -Recurse -Force > $null 2>&1
        Remove-Item -Path "$workingDir\scratchdir\Program Files (x86)\Microsoft\EdgeUpdate" -Recurse -Force > $null 2>&1
        Remove-Item -Path "$workingDir\scratchdir\Program Files (x86)\Microsoft\EdgeCore" -Recurse -Force > $null 2>&1
        if ($imgArch -eq 'amd64' -or 'arm64') {
            $folderPath = Get-ChildItem -Path "$workingDir\scratchdir\Windows\WinSxS" -Filter "$($imgArch)_microsoft-edge-webview_31bf3856ad364e35*" -Directory | Select-Object -ExpandProperty FullName > $null
            if ($folderPath) {
                & takeown /f "$folderPath" /r > $null
                & icacls "$folderPath" /grant "$($adminGroup.Value):(F)" /T /C > $null
                Remove-Item -Path "$folderPath" -Recurse -Force > $null
            }
        }
        TakeOwnership("$workingDir\scratchdir\Windows\System32\Microsoft-Edge-Webview", "/r", "/T /C")
        Remove-Item -Path "$workingDir\scratchdir\Windows\System32\Microsoft-Edge-Webview" -Recurse -Force > $null

        Write-Progress -Status "Removing OneDrive"
        TakeOwnership("$workingDir\scratchdir\Windows\System32\OneDriveSetup.exe", "/r", "/T /C")
        Remove-Item -Path "$workingDir\scratchdir\Windows\System32\OneDriveSetup.exe" -Force > $null

        Write-Progress -Activity "Loading image registry..." -Status ""
        $registries | ForEach-Object { & reg load $_[0] $_[1] > $null }

        Write-Progress -Activity "Modifying registry key permissions..." -Status "Enabling take ownership privilege"
        Enable-Privilege SeTakeOwnershipPrivilege
        Write-Progress -Status "Taking ownership of registry key"
        $rkey = [Registry]::LocalMachine.OpenSubKey("zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks",[RegistryKeyPermissionCheck]::ReadWriteSubTree,[RegistryRights]::TakeOwnership)
        $rACL = $rKey.GetAccessControl()
        $rACL.SetOwner($adminGroup)
        $rKey.SetAccessControl($regACL)
        $rKey.Close()
        Write-Progress -Status "Modifying Administrators group permissions on registry key"
        $rKey = [Registry]::LocalMachine.OpenSubKey("zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks",[RegistryKeyPermissionCheck]::ReadWriteSubTree,[RegistryRights]::ChangePermissions)
        $rACL = $rKey.GetAccessControl()
        $rRule = New-Object RegistryAccessRule($adminGroup,"FullControl","ContainerInherit","None","Allow")
        $rACL.SetAccessRule($rRule)
        $rKey.SetAccessControl($rACL)
        $rKey.Close()

        Write-Progress -Activity "Modifying image registry..." -Status ""
        $installRegKeys.GetEnumerator() | Foreach-Object {
            Write-Progress -Status $_.Key
            $_.Value | Foreach-Object {
                if ($_[0] -eq "add") {
                    & reg add $_[1] /v $_[2] /t $_[3] /d $_[4] /f > $null
                }
                elseif ($_[0] -eq "delete") {
                    & reg delete $_[1] /f > $null
                }
                else {
                    Write-Host "Warning: '$($_[0])' is an unknown registry operation."
                }
            }
        }

        Write-Progress -Activity "Unloading image registry..." -Status ""
        $registries | ForEach-Object { & reg unload $_[0] > $null }

        & dism /image:"$workingDir\scratchdir" /Cleanup-Image /StartComponentCleanup /ResetBase | ForEach-Object {
            Write-Progress -Activity "Cleaning up install image..." -Status $_
        }

        & dism /unmount-image /mountdir:"$workingDir\scratchdir" /commit | ForEach-Object {
            Write-Progress -Activity "Unmounting install image..." -Status $_
        }

        & dism /Export-Image /SourceImageFile:"$workingDir\sources\install.wim" /SourceIndex:$index /DestinationImageFile:"$workingDir\sources\install2.wim" /compress:max | ForEach-Object {
            Write-Progress -Activity "Saving install image..." -Status $_
        }
        Remove-Item -Path "$workingDir\sources\install.wim" -Force > $null
        Rename-Item -Path "$workingDir\sources\install2.wim" -NewName "install.wim" > $null

        TakeOwnership("$workingDir\sources\boot.wim")
        try { Set-ItemProperty -Path "$workingDir\sources\boot.wim" -Name IsReadOnly -Value $false -ErrorAction Stop > $null 2>&1}
        catch {} # This block will catch the error and suppress it.

        & dism /mount-image /imagefile:"$workingDir\sources\boot.wim" /index:2 /mountdir:"$workingDir\scratchdir" | ForEach-Object {
            Write-Progress -Activity "Mounting boot image..." -Status $_
        }

        Write-Progress -Activity "Loading image registry..." -Status ""
        $registries | ForEach-Object { & reg load $_[0] $_[1] > $null }

        Write-Progress -Activity "Modifying image registry..." -Status ""
        $bootRegKeys.GetEnumerator() | Foreach-Object {
            Write-Progress -Status $_.Key
            $_.Value | Foreach-Object {
                if ($_[0] -eq "add") {
                    & reg add $_[1] /v $_[2] /t $_[3] /d $_[4] /f > $null
                }
                elseif ($_[0] -eq "delete") {
                    & reg delete $_[1] /f > $null
                }
                else {
                    Write-Host "Warning: '$($_[0])' is an unknown registry operation."
                }
            }
        }

        Write-Progress -Activity "Unloading image registry..." -Status ""
        $registries | ForEach-Object { & reg unload $_[0] > $null }

        & dism /unmount-image /mountdir:"$workingDir\scratchdir" /commit | ForEach-Object {
            Write-Progress -Activity "Unmounting boot image..." -Status $_
        }

        & dism /Export-Image /SourceImageFile:"$workingDir\sources\boot.wim" /SourceIndex:2 /DestinationImageFile:"$workingDir\sources\boot2.wim" /compress:max | ForEach-Object {
            Write-Progress -Activity "Saving boot image..." -Status $_
        }
        Remove-Item -Path "$workingDir\sources\boot.wim" -Force > $null
        Rename-Item -Path "$workingDir\sources\boot2.wim" -NewName "boot.wim" > $null

        Write-Progress -Activity "Copying unattended file for bypassing MS account on OOBE..." -Status ""
        Copy-Item -Path "$PSScriptRoot\autounattend.xml" -Destination "$workingDir\autounattend.xml" -Force > $null

        Write-Progress -Activity "Removing temp directory..."
        Remove-Item -Path "$workingDir\scratchdir" -Recurse -Force > $null

        & "$PSScriptRoot\oscdimg.exe" -m -o -u2 -udfver102 "-bootdata:2#p0,e,b$workingDir\boot\etfsboot.com#pEF,e,b$workingDir\efi\microsoft\boot\efisys.bin" "$workingDir" "$PSScriptRoot\tiny11.iso" | ForEach-Object {
            Write-Progress -Activity "Creating ISO image..." -Status $_
        }

        Write-Progress -Activity "Cleaning up..." -Status ""
        Remove-Item -Path "$workingDir" -Recurse -Force > $null
    }

    while((Get-Job | Where-Object {$_.State -ne "Completed"}).Count -gt 0) {
        $jobProgress = $job.ChildJobs[0].Progress
        $jobProgress = $jobProgress[$jobProgress.Count - 1]
        Write-Progress -Id 0 -Activity "Building tiny11" -PercentComplete $($jobProgress.PercentComplete)
        Write-Progress -ParentId 0 -Id 1 -Activity $($jobProgress.Activity) -Status $($jobProgress.StatusDescription)
        Start-Sleep -Milliseconds 100
    }

    Clear-Host 
    Write-Host "$([Console]::Title)$newLine${newLine}tiny11 ISO image has been created!${$newLine}Output path: '${$PSScriptRoot}\tiny11.iso'$newLine${$newLine}Press any key to exit...$newLine"
    [Console]::ReadKey()

    Stop-Transcript
    exit
}

selectDrive