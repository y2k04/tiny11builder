using namespace System.Console
using namespace System.Diagnostics
using namespace System.Environment
using namespace System.Management.Automation

[Console]::Title = "tiny11 builder"
#$Host.UI.RawUI.WindowTitle = "tiny11 builder"

if ((Get-ExecutionPolicy) -ne 'Unrestricted') { Set-ExecutionPolicy Unrestricted -Scope CurrentUser -Confirm:$false }

. .\Helpers.ps1
ElevateIfRequired

$newLine = [Environment]::NewLine
$OSDrive = $env:SystemDrive
$workingDir = "$PSScriptRoot\tiny11"
$arch = $Env:PROCESSOR_ARCHITECTURE
$drives = Get-PSDrive | Select-Object -ExpandProperty 'Root' | Select-String '^[a-z]:\\$' | ForEach-Object {$_ -replace "\\"} | Where-Object { $_ -ne $OSDrive }

New-Item -ItemType Directory -Force -Path "$workingDir\sources" > $null
Start-Transcript -Path "$workingDir\tiny11.log"

Set-PSRepository PSGallery -InstallationPolicy Trusted
if (Get-Module -ListAvailable -Name PSMenu) { Import-Module PSMenu } else { Install-Module PSMenu -Scope CurrentUser -SkipPublisherCheck -Confirm:$false }
if (Get-Module -ListAvailable -Name PSWriteColor) { Import-Module PSWriteColor } else { Install-Module PSWriteColor -Scope CurrentUser -SkipPublisherCheck -Confirm:$false }
. .\Copy-ItemWithProgress.ps1

Clear-Host

function selectDrive() {
    Write-Host "tiny11 image creator (Dev_16-05-24)$newLine${newLine}Please select drive letter for the Windows 11 image:"
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
        Write-Host "tiny11 image creator (Dev_16-05-24)$newLine${newLine}Converting image to WIM...$newLine${$newLine}"
        & dism /Export-Image /SourceImageFile:"$drive\sources\install.esd" /SourceIndex:$index /DestinationImageFile:"$workingDir\sources\install.wim" /Compress:max /CheckIntegrity
    }

    copyFiles
}

function copyFiles() {
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
            Write-Host "$newLine${$newLine}Please select the image index:"
            $index = Show-Menu $images
        }
    }

    startBuild
}

function startBuild() {
    $job = Start-Job -Name "startBuild" -ScriptBlock {
        & takeown /F "$workingDir\sources\install.wim" > $null 2>&1
        & icacls "$workingDir\sources\install.wim" "/grant" "$($adminGroup.Value):(F)" > $null 2>&1
        try { Set-ItemProperty -Path "$workingDir\sources\install.wim" -Name IsReadOnly -Value $false -ErrorAction Stop > $null 2>&1}
        catch {} # This block will catch the error and suppress it.

        New-Item -ItemType Directory -Force -Path "$workingDir\scratchdir" > $null
        & dism /mount-image /imagefile:"$workingDir\sources\install.wim" /index:$index /mountdir:"$workingDir\scratchdir" | ForEach-Object {
            Write-Progress -Activity "Mounting install.wim..." -Status $_
        }

        Write-Progress -Activity "Getting default system UI language..."
        $languageLine = $(& dism /Get-Intl /Image:"$workingDir\scratchdir") -split '\n' | Where-Object { $_ -match 'Default system UI language : ([a-zA-Z]{2}-[a-zA-Z]{2})' }

        if ($languageLine) {
            $languageCode = $Matches[1]
            Write-Host "Info: Found language code: $languageCode"
        } else {
            Write-Host "Error: Default system UI language code not found."
        }

        Write-Progress -Activity "Getting image architecture..."
        & dism /get-wiminfo /wimfile:"$workingDir\sources\install.wim" /index:$index
    }

    while((Get-Job | Where-Object {$_.State -ne "Completed"}).Count -gt 0) {
        $jobProgress = $job.ChildJobs[0].Progress
        $jobProgress = $jobProgress[$jobProgress.Count - 1]
        Write-Progress -Id 0 -Activity "Building tiny11" -PercentComplete $($jobProgress.PercentComplete)
        Write-Progress -ParentId 0 -Id 1 -Activity $($jobProgress.Activity) -Status $($jobProgress.StatusDescription)
        Start-Sleep -Milliseconds 100
    }
}

selectDrive