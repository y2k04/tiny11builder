using namespace System.Security.Principal

function ElevateIfRequired() {
    $adminGroup = [SecurityIdentifier]("S-1-5-32-544").Translate([NTAccount])
    $windowsPrincipal = New-Object WindowsPrincipal([WindowsIdentity]::GetCurrent())

    if (!$windowsPrincipal.IsInRole([WindowsBuiltInRole]::Administrator)) {
        Start-Process "powershell" -ArgumentList $myInvocation.MyCommand.Definition -Verb runas
        exit
    }
}