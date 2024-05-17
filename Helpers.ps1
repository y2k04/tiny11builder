using namespace System.Security.Principal

function ElevateIfRequired() {
    $adminGroup = [SecurityIdentifier]("S-1-5-32-544").Translate([NTAccount])
    $windowsPrincipal = New-Object WindowsPrincipal([WindowsIdentity]::GetCurrent())

    if (!$windowsPrincipal.IsInRole([WindowsBuiltInRole]::Administrator)) {
        Start-Process "powershell" -ArgumentList $myInvocation.MyCommand.Definition -Verb runas
        exit
    }
}

function TakeOwnership($path, $tExtraArgs = "", $iExtraArgs = "") {
    & takeown /f $path $tExtraArgs > $null 2>&1
    & icacls $path /grant "$($adminGroup.Value):(F)" $iExtraArgs > $null 2>&1
}

## this function allows PowerShell to take ownership of the Scheduled Tasks registry key from TrustedInstaller. Based on Jose Espitia's script.
function Enable-Privilege {
    param(
        [ValidateSet("SeAssignPrimaryTokenPrivilege", "SeAuditPrivilege", "SeBackupPrivilege", "SeChangeNotifyPrivilege", "SeCreateGlobalPrivilege", "SeCreatePagefilePrivilege", "SeCreatePermanentPrivilege", "SeCreateSymbolicLinkPrivilege", "SeCreateTokenPrivilege", "SeDebugPrivilege", "SeEnableDelegationPrivilege", "SeImpersonatePrivilege", "SeIncreaseBasePriorityPrivilege", "SeIncreaseQuotaPrivilege", "SeIncreaseWorkingSetPrivilege", "SeLoadDriverPrivilege", "SeLockMemoryPrivilege", "SeMachineAccountPrivilege", "SeManageVolumePrivilege", "SeProfileSingleProcessPrivilege", "SeRelabelPrivilege", "SeRemoteShutdownPrivilege", "SeRestorePrivilege", "SeSecurityPrivilege", "SeShutdownPrivilege", "SeSyncAgentPrivilege", "SeSystemEnvironmentPrivilege", "SeSystemProfilePrivilege", "SeSystemtimePrivilege", "SeTakeOwnershipPrivilege", "SeTcbPrivilege", "SeTimeZonePrivilege", "SeTrustedCredManAccessPrivilege", "SeUndockPrivilege", "SeUnsolicitedInputPrivilege")]
        $Privilege, ## The process on which to adjust the privilege. Defaults to the current process.
        $ProcessId = $pid, ## Switch to disable the privilege, rather than enable it.
        [Switch] $Disable
    )
    $definition = 'using System;using System.Runtime.InteropServices;public class AdjPriv{[DllImport("advapi32.dll",ExactSpelling=true,SetLastError=true)]internal static extern bool AdjustTokenPrivileges(IntPtr htok,bool disall,ref TokPriv1Luid newst,int len,IntPtr prev,IntPtr relen);[DllImport("advapi32.dll",ExactSpelling=true,SetLastError=true)]internal static extern bool OpenProcessToken(IntPtr h,int acc,ref IntPtr phtok);[DllImport("advapi32.dll",SetLastError=true)]internal static extern bool LookupPrivilegeValue(string host,string name,ref long pluid);[StructLayout(LayoutKind.Sequential,Pack=1)]internal struct TokPriv1Luid{public int Count,Attr;public long Luid;}internal const int SE_PRIVILEGE_ENABLED=0x00000002;internal const int SE_PRIVILEGE_DISABLED=0x00000000;internal const int TOKEN_QUERY=0x00000008;internal const int TOKEN_ADJUST_PRIVILEGES=0x00000020;public static bool EnablePrivilege(long processHandle,string privilege,bool disable){bool retVal;TokPriv1Luid tp;IntPtr hproc=new IntPtr(processHandle);IntPtr htok=IntPtr.Zero;retVal=OpenProcessToken(hproc,TOKEN_ADJUST_PRIVILEGES|TOKEN_QUERY,ref htok);tp.Count=1;tp.Luid=0;if(disable){tp.Attr=SE_PRIVILEGE_DISABLED;}else{tp.Attr=SE_PRIVILEGE_ENABLED;}retVal=LookupPrivilegeValue(null,privilege,ref tp.Luid);retVal=AdjustTokenPrivileges(htok,false,ref tp,0,IntPtr.Zero,IntPtr.Zero);return retVal;}}'
    $processHandle = (Get-Process -id $ProcessId).Handle
    $type = Add-Type $definition -PassThru
    $type[0]::EnablePrivilege($processHandle, $Privilege, $Disable)
}

$registries = @(
    ("HKLM\zCOMPONENTS", "$workingDir\scratchdir\Windows\System32\config\COMPONENTS"),
    ("HKLM\zDEFAULT", "$workingDir\scratchdir\Windows\System32\config\default"),
    ("HKLM\zNTUSER", "$workingDir\scratchdir\Users\Default\ntuser.dat"),
    ("HKLM\zSOFTWARE", "$workingDir\scratchdir\Windows\System32\config\SOFTWARE"),
    ("HKLM\zSYSTEM", "$workingDir\scratchdir\Windows\System32\config\SYSTEM")
)

$bootRegKeys = [ordered]@{
    "Add system requirements bypass" = @(
        ("add", "HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache", "SV1", "REG_DWORD", 0),
        ("add", "HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache", "SV2", "REG_DWORD", 0),
        ("add", "HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache", "SV1", "REG_DWORD", 0),
        ("add", "HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache", "SV2", "REG_DWORD", 0),
        ("add", "HKLM\zSYSTEM\Setup\LabConfig", "BypassCPUCheck", "REG_DWORD", 1),
        ("add", "HKLM\zSYSTEM\Setup\LabConfig", "BypassRAMCheck", "REG_DWORD", 1),
        ("add", "HKLM\zSYSTEM\Setup\LabConfig", "BypassSecureBootCheck", "REG_DWORD", 1),
        ("add", "HKLM\zSYSTEM\Setup\LabConfig", "BypassStorageCheck", "REG_DWORD", 1),
        ("add", "HKLM\zSYSTEM\Setup\LabConfig", "BypassTPMCheck", "REG_DWORD", 1),
        ("add", "HKLM\zSYSTEM\Setup\MoSetup", "AllowUpgradesWithUnsupportedTPMOrCPU", "REG_DWORD", 1)
    )
}

$installRegKeys = [ordered]@{
    "Add system requirements bypass" = @(
        ("add", "HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache", "SV1", "REG_DWORD", 0),
        ("add", "HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache", "SV2", "REG_DWORD", 0),
        ("add", "HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache", "SV1", "REG_DWORD", 0),
        ("add", "HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache", "SV2", "REG_DWORD", 0),
        ("add", "HKLM\zSYSTEM\Setup\LabConfig", "BypassCPUCheck", "REG_DWORD", 1),
        ("add", "HKLM\zSYSTEM\Setup\LabConfig", "BypassRAMCheck", "REG_DWORD", 1),
        ("add", "HKLM\zSYSTEM\Setup\LabConfig", "BypassSecureBootCheck", "REG_DWORD", 1),
        ("add", "HKLM\zSYSTEM\Setup\LabConfig", "BypassStorageCheck", "REG_DWORD", 1),
        ("add", "HKLM\zSYSTEM\Setup\LabConfig", "BypassTPMCheck", "REG_DWORD", 1),
        ("add", "HKLM\zSYSTEM\Setup\MoSetup", "AllowUpgradesWithUnsupportedTPMOrCPU", "REG_DWORD", 1)
    )
    "Disable sponsored apps" = @(
        ("add", "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager", "OemPreInstalledAppsEnabled", "REG_DWORD", 0),
        ("add", "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager", "PreInstalledAppsEnabled", "REG_DWORD", 0),
        ("add", "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager", "SilentInstalledAppsEnabled", "REG_DWORD", 0),
        ("add", "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager", "ContentDeliveryAllowed", "REG_DWORD", 0),
        ("add", "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager", "FeatureManagementEnabled", "REG_DWORD", 0),
        ("add", "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager", "SoftLandingEnabled", "REG_DWORD", 0),
        ("add", "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager", "SubscribedContentEnabled", "REG_DWORD", 0),
        ("add", "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager", "SubscribedContent-310093Enabled", "REG_DWORD", 0),
        ("add", "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager", "SubscribedContent-338388Enabled", "REG_DWORD", 0),
        ("add", "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager", "SubscribedContent-338389Enabled", "REG_DWORD", 0),
        ("add", "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager", "SubscribedContent-338393Enabled", "REG_DWORD", 0),
        ("add", "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager", "SubscribedContent-353694Enabled", "REG_DWORD", 0),
        ("add", "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager", "SubscribedContent-353696Enabled", "REG_DWORD", 0),
        ("add", "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager", "SystemPaneSuggestionsEnabled", "REG_DWORD", 0),
        ("add", "HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent", "DisableWindowsConsumerFeatures", "REG_DWORD", 1),
        ("add", "HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent", "DisableConsumerAccountStateContent", "REG_DWORD", 1),
        ("add", "HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent", "DisableCloudOptimizedContent", "REG_DWORD", 1),
        ("add", "HKLM\zSOFTWARE\Microsoft\PolicyManager\current\device\Start", "ConfigureStartPins", "REG_SZ", '{"pinnedList": [{}]}'),
        ("add", "HKLM\zSOFTWARE\Policies\Microsoft\PushToInstall", "DisablePushToInstall", "REG_DWORD", 1),
        ("add", "HKLM\zSOFTWARE\Policies\Microsoft\MRT", "DontOfferThroughWUAU", "REG_DWORD", 1),
        ("delete", "HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\Subscriptions"),
        ("delete", "HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SuggestedApps")
    )
    "Enable local accounts on OOBE" = @(
        ("add", "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\OOBE", "BypassNRO", "REG_DWORD", 1)
    )
    "Disable reserved storage" = @(
        ("add", "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager", "ShippedWithReserves", "REG_DWORD", 0)
    )
    "Disable chat icon" = @(
        ("add", "HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Chat", "ChatIcon", "REG_DWORD", 3),
        ("add", "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced", "TaskbarMn", "REG_DWORD", 0)
    )
    "Remove Microsoft Edge related keys" = @(
        ("delete", "HKLM\zSOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge"),
        ("delete", "HKLM\zSOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge Update")
    )
    "Disable OneDrive folder backup" = @(
        ("add", "HKLM\zSOFTWARE\Policies\Microsoft\Windows\OneDrive", "DisableFileSyncNGSC", "REG_DWORD", 1)
    )
    "Disable telemetry" = @(
        ("add", "HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo", "Enabled", "REG_DWORD", 0),
        ("add", "HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Privacy", "TailoredExperiencesWithDiagnosticDataEnabled", "REG_DWORD", 0),
        ("add", "HKLM\zNTUSER\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy", "HasAccepted", "REG_DWORD", 0),
        ("add", "HKLM\zNTUSER\Software\Microsoft\Input\TIPC", "Enabled", "REG_DWORD", 0),
        ("add", "HKLM\zNTUSER\Software\Microsoft\InputPersonalization", "RestrictImplicitInkCollection", "REG_DWORD", 1),
        ("add", "HKLM\zNTUSER\Software\Microsoft\InputPersonalization", "RestrictImplicitTextCollection", "REG_DWORD", 1),
        ("add", "HKLM\zNTUSER\Software\Microsoft\InputPersonalization\TrainedDataStore", "HarvestContacts", "REG_DWORD", 0),
        ("add", "HKLM\zNTUSER\Software\Microsoft\Personalization\Settings", "AcceptedPrivacyPolicy", "REG_DWORD", 0),
        ("add", "HKLM\zSOFTWARE\Policies\Microsoft\Windows\DataCollection", "AllowTelemetry", "REG_DWORD", 0),
        ("add", "HKLM\zSYSTEM\ControlSet001\Services\dmwappushservice", "Start", "REG_DWORD", 4)
    )
    "Delete Application Compatibility Appraiser" = @(
        ("delete", "HKLM\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks\{0600DD45-FAF2-4131-A006-0B17509B9F78}")
    )
    "Delete Customer Experience Improvement Program" = @(
        ("delete", "HKLM\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks\{4738DE7A-BCC1-4E2D-B1B0-CADB044BFA81}"),
        ("delete", "HKLM\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks\{6FAC31FA-4A85-4E64-BFD5-2154FF4594B3}"),
        ("delete", "HKLM\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks\{FC931F16-B50A-472E-B061-B6F79A71EF59}")
    )
    "Delete Program Data Updater" = @(
        ("delete", "HKLM\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks\{0671EB05-7D95-4153-A32B-1426B9FE61DB}")
    )
    "Delete autochk proxy" = @(
        ("delete", "HKLM\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks\{87BF85F4-2CE1-4160-96EA-52F554AA28A2}"),
        ("delete", "HKLM\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks\{8A9C643C-3D74-4099-B6BD-9C6D170898B1}")
    )
    "Delete QueueReporting" = @(
        ("delete", "HKLM\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks\{E3176A65-4E44-4ED3-AA73-3283660ACB9C}")
    )
}