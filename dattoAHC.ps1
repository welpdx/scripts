$varTitle="Agent Health Check v2.3.308" #may 2026

<#
    Datto RMM Health Check Tool/Standalone version :: Written by seagull, 2017-2026
    this tool may not be redistributed outside of official kaseya channels.
    this tool is NOT open-source and has NOT been released under public licence.
#>

#component check (DISABLED) :: this build runs standalone (e.g. ScreenConnect Backstage), not under the Datto Agent
#if ($env:cs_profile_name) {
#    write-host "This interactive script does not support being run as a Component."
#    write-host "A Componentised version of this script is available from the ComStore"
#    write-host "under the name 'Agent Health Direct-Check [WIN]'."
#    exit 1
#}

#pwsh check
if ($PSVersionTable.psVersion.Major -gt 5) {
    write-host "! ERROR: PWSH (Microsoft PowerShell) is not supported." -fo Red
    write-host "  Please run this script with Windows PowerShell (2.0-5.1)."
    exit 1
}

# =========================================================== STANDALONE CONFIG (ScreenConnect Backstage etc.) ===========================================================
# This build runs fully unattended (no prompts). It is intended to be launched from a SYSTEM / Administrator
# shell - for example, from ScreenConnect Backstage - with a single line:
#
#     irm https://raw.githubusercontent.com/welpdx/scripts/refs/heads/main/dattoAHC.ps1 | iex
#
# Behaviour is controlled by the CONFIG section just below. Any setting can ALSO be overridden at run time by
# setting an environment variable of the same name first, e.g.:
#     $env:usrFixDotNet='true'; irm <url> | iex
#
# Certificates are CHECKED ONLY: the tool reports problems but NEVER installs or modifies a certificate.
# WMI repair is automatic: skipped when no WMI issues are detected, attempted otherwise.

#----- output directory :: every log file AND the full console transcript are written here -----
$CSATCDir="C:\programdata\dattoATC"

#========================= CONFIG (edit these defaults, or set the matching $env: var) =========================
$varPlatform    = "6"       # RMM region. 1=Pinotage 2=Merlot 3=Syrah 4=Zinfandel 5=Concord 6=Vidal 7=Moscato. Use 'infer' to read it from the installed Agent.
$varRunDotNet   = $false    # $true = run the Microsoft .NET Framework Repair Tool (~5 min; downloads an EXE)
$varCollectLogs = $true     # $true = copy the Agent's log / operational files into $CSATCDir
#=============================================================================================================

#helper: turn a string (e.g. an environment-variable override) into a boolean
function csToBool ($val, $default) {
    $s="$val".Trim()
    if (!$s) {return $default}
    return ($s -match '^(true|yes|y|1|on|enable|enabled)$')
}

#apply optional environment-variable overrides
if ("$env:usrPlatform".Trim())    {$varPlatform    = "$env:usrPlatform".Trim()}
if ("$env:usrFixDotNet".Trim())   {$varRunDotNet   = csToBool $env:usrFixDotNet   $varRunDotNet}
if ("$env:usrCollectLogs".Trim()) {$varCollectLogs = csToBool $env:usrCollectLogs $varCollectLogs}

#create the output directory (fall back to a writable TEMP location if ProgramData is not available)
try {
    if (!(test-path $CSATCDir)) {new-item $CSATCDir -type directory -Force -ea Stop | out-null}
} catch {
    $CSATCDir="$env:TEMP\dattoATC"
    if (!(test-path $CSATCDir)) {new-item $CSATCDir -type directory -Force -ea 0 | out-null}
}

#start a transcript so EVERYTHING shown on screen is ALSO saved to disk, in real time
$CSTranscript="$CSATCDir\AHC-$env:computername-Transcript-$(get-date -f yyyyMMdd-HHmmss).log"
try {Start-Transcript -Path $CSTranscript -Force -ea Stop | out-null; $CSTranscriptOn=$true} catch {$CSTranscriptOn=$false}

#cosmetix (wrapped: a non-interactive host may not implement these)
try {
    $host.ui.RawUI.WindowTitle="Agent Health Check " + $varTitle #give it a title
    $Host.UI.RawUI.BackgroundColor='Black'                       #paint the screen black
    clear
} catch {}

# =========================================================== VARIABLES & FUNCTIONS ===========================================================

#configure net
[System.Net.ServicePointManager]::SecurityProtocol=[Enum]::ToObject([System.Net.SecurityProtocolType], 3072)
[System.Net.ServicePointManager]::ServerCertificateValidationCallback={$true}

if (([IntPtr]::size) -eq 4) {
    $varProg32=$env:ProgramFiles
    $CSRegSoftware='HKLM:\Software'
} else {
    $varProg32=${env:ProgramFiles(x86)}    
    $CSRegSoftware='HKLM:\Software\WOW6432Node'
}

#run via "irm <url> | iex" means there is no script file on disk, so use the output directory as our working dir
$varScriptDir=$CSATCDir
$CSAdmin=([bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()).groups -match "S-1-5-32-544"))

try {
   $varWMIOut=gwmi Win32_OperatingSystem -ea Stop
   [int]$varWinVer=$varWMIOut.buildNumber
   [int]$varSKU=$varWMIOut.operatingSystemSKU
   $varCaption=$varWMIOut.caption
   $varLastBootWMI=$varWMIOut.lastBootUpTime
} catch {
   write-host "! ERROR: Unable to enumerate device WMI." -fo Red
   write-host "  This will cause some errors to appear; please attempt to fix the WMI on page two."

   #flag WMI issues
   $varWMIIssues="Significant"

   #highlight issues in log
   [int]$varWinVer=0
   [int]$varSKU=0
   $varCaption="Unknown Windows Device (WMI dysfunctional)"
   $varLastBootWMI=0
}

#get the programdata directory, which is less straightforward than you'd think
if (get-process -name AEMAgent -ea 0) {
    $CSProgData=(get-process -name AEMAgent -ea 0).path | split-path -Parent -ea 0 | split-path -parent -ea 0
    $CSDataLog=get-content "$CSProgData\AEMAgent\DataLog\aemagent.log" -encoding UTF8 -ea 0
} else {
    $CSDataLog=get-content "$env:ProgramData\CentraStage\AEMAgent\DataLog\aemagent.log" -encoding UTF8 -ea 0
}

Function EpochTime {
    [long][double]::Parse((Get-Date -UFormat %s))
}

function makeFolder {
    if ($CSATCDir) {$varBase=$CSATCDir} else {$varBase=$varScriptDir}
    $script:varResultDir="$varBase\AHC-$env:computername-Result-$(EpochTime)"
    new-item "$varResultDir\" -type directory -Force | out-null
}

function Get-HTTPHeaders { # by geoff varosky/sharepointyankee.com
    param( 
        [Parameter(ValueFromPipeline=$true)] 
        [string] $Url 
    )

    $request=[System.Net.WebRequest]::Create($Url)
    $response=$request.GetResponse()
    try {
        $headers=$response.Headers
        $headers.allKeys | select @{Name="Key"; Expression={$_}}, @{Name="Value"; Expression={$headers.GetValues($_)}}
    } finally {
        $response.Close()
    }
}

function makeHTTPRequest ($tempHost, $response, $response2) { #v9
    $attempts=0
    while ($attempts -ne 3) {
        $tempReturn=$null
        $tempResponse=$null
        try {
            $tempRequest=[System.Net.WebRequest]::Create($tempHost)
            if ($env:CS_PROFILE_PROXY_TYPE -ge '1') {
                getProxy
                $tempRequest.Proxy=New-Object System.Net.WebProxy("$script:varProxyLoc`:$script:varProxyPort",$true)
            }
            $tempResponse=$tempRequest.GetResponse()
            $tempReturn=($tempResponse.StatusCode -as [int])
        } catch [System.Net.WebException] {
            $tempResponse=$_.Exception.Response
            if ($tempResponse) {$tempReturn=$tempResponse.StatusCode.Value__}
        } catch {
            $tempReturn=$null
        } finally {
            if ($tempResponse) {$tempResponse.Close()}
        }

        $attempts++
        if (($tempReturn -as [string]).length -eq 3) {break}
    }

    #$script:CSToolReport+=": DEBUG: $tempHost returned HTTP $tempReturn"
    start-sleep -seconds 2 #anti-throttling
    return ($tempReturn -ne $null -and ($tempReturn -eq $response -or $tempReturn -eq $response2))
}

function makeIPRequest ($tempHostArray, $tempName, $tempSuffix) { #unique variant for testing CCs specifically
    $tempTotal=(($tempHostArray.split())|measure-object).count
    foreach ($tempHost in $tempHostArray.split()) {
        $tempIPRequest=new-object net.sockets.tcpclient
        if ($tempSuffix) {
            $tempIPRequest.beginConnect($("$temphost"+"$tempsuffix"),443,$Null,$Null ) | Out-Null
        } else {
            $tempIPRequest.beginConnect("$tempHost",443,$null,$null) | Out-Null
        }

        While (-not $tempIPRequest.Connected) {
            $attempts++
            start-sleep -seconds 1
            if ($attempts -ge 5) {break}
        }

        if ($tempIPRequest.Connected) {
            $tempPass++
            if ($tempSuffix) {
                $script:CSToolReport+="+ SUCCESS: $tempName $("$tempHost"+"$tempSuffix")"
            } else {
                $script:CSToolReport+="+ SUCCESS: $tempName $tempHost"
            }
        } else {
            if ($tempSuffix) {
                $script:CSToolReport+="! FAILURE: $tempName $("$tempHost"+"$tempSuffix")"
            } else {
                $script:CSToolReport+="! FAILURE: $tempName $tempHost"
            }
        }
        $tempIPRequest.close()
        clear-variable attempts -ea 0
    }

    #tally the results
    if ($tempPass -ne $tempTotal) {
        return $false
    } else {
        return $true
    }
}

function processIPList ($tempHostArray, $tempHeader, $tempLabel) { #unique variant for testing tunnel/platform IP lists specifically
    $tempTotal=(($tempHostArray)|measure-object).count
    $tempPass=0
    foreach ($tempHost in [array]$tempHostArray) {
        #perform the check
        $tempIPRequest=new-object net.sockets.tcpclient
        $tempIPRequest.BeginConnect($tempHost,443,$Null,$Null) | Out-Null
        start-sleep -milliseconds 300
        if ($tempIPRequest.Connected) {
            #successful connection, increment the readout
            $tempPass++
            $tempPassStr='{0:D2}' -f $tempPass

            #update the readout
            write-host "`r$tempHeader [$tempPassStr/$tempTotal]" -NoNewline
            $script:CSToolReport+=" + OK: $tempLabel ($tempHost)"
        } else {
            $script:CSToolReport+=" ! NO: $tempLabel ($tempHost)"
        }
        $tempIPRequest.close()
    }

    #tally the results
    write-host "`r$tempHeader " -NoNewline
    if ($tempPass -eq $tempTotal) {
        write-host "[$tempPassStr/$tempTotal]" -fo Green -NoNewline
        $script:CSToolReport+="+ SUCCESS: 100% of IP addresses were contactable"
    } elseif ($tempPass -ge ($tempTotal*0.25)) {
        write-host "[$tempPassStr/$tempTotal]" -fo Yellow -NoNewline
        $script:CSToolReport+="+ SUCCESS: At least 25% of IP addresses were contactable (this is typical)"
    } else {
        write-host "[$tempPassStr/$tempTotal]" -fo Red -NoNewline
        $script:CSToolReport+="! FAILURE: Fewer than 25% of IP addresses were contactable."
    }
}

function toSHA256 {
	-Join ($([System.Security.Cryptography.SHA256]::Create()).ComputeHash((New-Object IO.StreamReader $input).BaseStream) | ForEach {"{0:x2}" -f $_})
}

function getGUID2 ($softwareTitle) { #returns display name, not parent key/MSI GUID
    ("HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall","HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall") | % {
        try {
            gci -Path $_ -ea 0| % {gp $_.PSPath -ea 0} | ? {$_.DisplayName -match $softwareTitle} | % {
                return $_.DisplayName
            }
        } catch {
            return $null
        }
    }
}

# ==================================================================== PAGE ONE ===================================================================

write-host "Page 1: Platform Connectivity" -fo Green
write-host "Started @ $(Get-Date)" -fo Cyan
write-host "============================="

#------------------------------------------------ sub-section: script update check

[xml]$CSToolVer_XML=(New-Object System.Net.WebClient).DownloadString("https://storage.centrastage.net/version.xml")

if (!$CSToolVer_XML) {
    write-host 'Could not check tool version. Please whitelist https://storage.centrastage.net.' -fo Red
    write-host `r
} else {
    if ($CSToolVer_XML.seagull.build -notmatch $varTitle) {
        write-host "Agent Health Check Tool is out of date." -fo Red
        write-host 'Download the latest build from: ' -NoNewline
        write-host 'http://dat.to/ahcdl' -fo Cyan
        write-host `r
    }
}

#------------------------------------------------ sub-section: check (administrative) privilege

if (!$CSAdmin) {
    $varOnDemand=0
    write-host "Script is not being run as an Administrator." -fo Red
    write-host "Re-launch as Admin to enable gathering/analysis of Agent operational data?"
    write-host "(This may not work if the Health Check Tool file is on a Network Drive!)"
    write-host "(Admin relaunch is disabled in non-interactive mode; continuing without elevation.)" -fo Yellow
    switch -Regex ('no') {
        default {
            #do nothing
        } 'A|a|Y|y' {
            #write our current directory to a hard file since admin launches in sys32
            $pwd.path | out-file "$env:TEMP\~AEMHC.tmp"
            #relaunch the shell in admin-mode
            $newProcess=new-object System.Diagnostics.ProcessStartInfo "PowerShell";
            $newProcess.Arguments="-executionpolicy bypass &'" + $script:MyInvocation.MyCommand.Path + "'"
            $newProcess.Verb="runas";
            [System.Diagnostics.Process]::Start($newProcess);
            exit
        }
    }
    write-host "`r"
} else {
    #congratulate the user
    write-host "Administrative permissions confirmed." -fo Cyan
    write-host "`r"
    #search for the .tmp file; if it is found, load it, then delete it
    if (test-path "$env:TEMP\~AEMHC.tmp") {
        get-content "$env:TEMP\~AEMHC.tmp" | cd
        Remove-Item "$env:TEMP\~AEMHC.tmp"
        $varScriptDir=$pwd.path
    }
    #40HC89: load agent XML files into memory NOW so we can check to see if device is onDemand :: [0] unknown [1] disabled [2] enabled :: MY KINGDOM FOR NATIVE TERNARY LOGIC
    $arrXMLFiles=@()
    $arrXMLFiles+=$((Get-ChildItem -Path "$env:SystemRoot\System32\config\systemprofile\AppData\Local\CentraStage" -Filter 'user.config' -recurse -force -ea 0 | select -last 1).FullName)
    $arrXMLFiles+=$((Get-ChildItem -Path "$env:SystemRoot\SysWOW64\config\systemprofile\AppData\Local\CentraStage" -Filter 'user.config' -recurse -force -ea 0 | select -last 1).FullName)

    if (($arrXMLFiles | ? {$_}).count -ge 1) {
        if ((((get-content $arrXMLFiles[0] -EA stop) -as [xml]).configuration.userSettings."CentraStage.Cag.Core.Settings".setting | ? {$_.Name -eq 'OnDemand'}).Value -eq 'true') {
            $varOnDemand=2
        } else {
            $varOnDemand=1
        }
    } else {
        $varOnDemand=0
    }
}

#------------------------------------------------ sub-section: check powershell constrained language mode

if ($ExecutionContext.SessionState.LanguageMode.value__ -ne 0) {
	write-host "! NOTICE: PowerShell Constrained-language mode is enabled for this device." -fo Red
	write-host "  Whilst Datto RMM will co-operate with this setting, ComStore Components in toto are"
	write-host "  not written for this mode and may not be compatible with it, leading to issues."
	write-host "  This tool does not play well with Constrained-language mode and thus has been halted."
	write-host `r
	write-host "  If Constrained-language mode has been enabled due to security concerns,"
	write-host "  please ensure your understanding of the setting confers with Microsoft's."
	write-host "  For some partners, enabling this setting will cause more issues than it resolves."
	write-host "  More: https://devblogs.microsoft.com/powershell/powershell-constrained-language-mode/"
	write-host `r
	write-host "  Execution halted: tool is not compatible with system running state." -fo Cyan
	exit 1
}

#------------------------------------------------ sub-section: confirm platform

#write basic information to the report
$script:CSToolReport=@()
$script:CSToolReport+= "$varTitle`: Verbose Output Log"
$script:CSToolReport+= "=================================="
$script:CSToolReport+= ": Endpoint Hostname:                $env:computername"
$script:CSToolReport+= ": Endpoint Windows Version:         Build $varWinver / $varCaption"
$script:CSToolReport+= ": Date/Time of Tool Execution:      $(Get-Date) :: $((Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation").TimeZoneKeyName)"

#write agent state to the report
if ($varOnDemand -eq 1) {
    $script:CSToolReport+= ": Agent State (Managed/OnDemand):   Managed - all checks will be performed"
} elseif ($varOnDemand -eq 2) {
    $script:CSToolReport+= ": Agent State (Managed/OnDemand):   OnDemand - some checks will be omitted"
} else {
    $script:CSToolReport+= ": Agent State (Managed/OnDemand):   Unknown - some checks may be omitted (Log files may be absent or tool is not being run as Admin)"
}

#present server selection to user
write-host "                                     -== Connectivity Check ==-" -fo Green
write-host `r
if (Test-Path "$varProg32\CentraStage\CagService.exe.config") {
    write-host "                           [ENTER]" -fo Green -NoNewline; write-host " Infer platform from Agent installation"
}
write-host "  1" -fo Green -NoNewline; write-host " Pinotage (EMEA West 1) " -fo White -NoNewline
write-host "|" -fo DarkGray -NoNewline; write-host " 2" -fo Green -NoNewline; write-host " Merlot (EMEA West 2) " -fo White -NoNewline
write-host "|" -fo DarkGray -NoNewline; write-host " 3" -fo Green -NoNewline; write-host " Syrah (Asia-Pacific) " -fo White -NoNewline
write-host "|" -fo DarkGray -NoNewline; write-host " 4" -fo Green -NoNewline; write-host " Zinfandel (US West) " -fo White
write-host "               5" -fo Green -NoNewline; write-host " Concord (US East 1) " -fo White -NoNewLine
write-host "|" -fo DarkGray -NoNewline; write-host " 6" -fo Green -NoNewline; write-host " Vidal (US East 2) " -fo White -NoNewline

<#
yes, congratulations, you found it. keep it hush-hush, yeah? cosa nostra.
write-host "|" -fo DarkGray -NoNewline; write-host " 7" -fo Green -NoNewline; write-host " Moscato (EMEA West 3)" -fo White
#>

write-host `r

#non-interactive platform resolution (Datto RMM) :: default is 6 (Vidal / US East 2)
#  set usrPlatform=infer (or auto) to intuit the platform from the installed Agent configuration instead
if ($varPlatform -match '^(infer|auto)$') {
    if (Test-Path "$varProg32\CentraStage\CagService.exe.config") {
        $varPlatform=($((Get-Content "$varProg32\CentraStage\CagService.exe.config" -ea 0) -as [xml]).configuration.applicationSettings."CentraStage.Cag.Core.AppSettings".setting | ? {$_.Name -eq 'CsIp'}).Value
        write-host "- Platform inferred from installed Agent configuration." -fo Cyan
    } else {
        write-host "! NOTICE: usrPlatform=infer requested but no Agent config was found; defaulting." -fo Yellow
        $varPlatform=$null
    }
}
if (!$varPlatform) {$varPlatform='6'}
if ($varPlatform -notmatch '^[1-7]$' -and $varPlatform -notmatch 'pinotage|merlot|syrah|zinfandel|concord|vidal|moscato') {
    write-host "! NOTICE: usrPlatform value '$varPlatform' is not valid; defaulting to 6 (Vidal)." -fo Yellow
    $varPlatform='6'
}
write-host "- Datto RMM platform selection: $varPlatform" -fo Cyan

switch -regex ($varPlatform) {
    '^(1|01cc)'        {$varCC_Name='Pinotage'; $varCC_NameAlt=$null;       $arrCC_CC='01cc'}
    '^(2|02cc)'        {$varCC_Name='Merlot';   $varCC_NameAlt='-merlot';   $arrCC_CC='02cc'}
    '^(3|.*syrah.*)'   {$varCC_Name='Syrah';    $varCC_NameAlt='-syrah';    $arrCC_CC='syrahcc','01syrahcc'}
    '^(4|03cc)'        {$varCC_Name='Zinfandel';$varCC_NameAlt='-zinfandel';$arrCC_CC='03cc'}
    '^(5|.*concord.*)' {$varCC_Name='Concord';  $varCC_NameAlt='-concord';  $arrCC_CC='concordcc','01concordcc'}
    '^(6|.*vidal.*)'   {$varCC_Name='Vidal';    $varCC_NameAlt='-vidal';    $arrCC_CC='vidalcc','01vidalcc'}
    '^(7|.*moscato.*)' {$varCC_Name='Moscato';  $varCC_NameAlt='-moscato';  $arrCC_CC='moscatocc','01moscatocc'}
    default {
        write-host "! ERROR: No platform selection was passed across." -fo red
        write-host "  PARTNERS:  Please report this error."
        write-host "  EMPLOYEES: The tool doesn't work on internal servers."
        exit 1
    }
}

write-host "Platform Selected: " -fo DarkGray -NoNewline; write-host "$varCC_Name" -fo White
write-host `r

#------------------------------------------------ sub-section: the Business End

$script:CSToolReport+=": Datto RMM Platform:               $varCC_Name"
$script:CSToolReport+="=================================="
$script:CSToolReport+=""
$script:CSToolReport+="= Connectivity Scan results for Datto RMM Host-based services:"

#web portal & graphQL API (CSM deprecated)
write-host "     Web Portal                 " -nonewline

if (makeHTTPRequest $("https://$varCC_Name"+"rmm.centrastage.net") 403) {
    $varPortalSuccess++
    $script:CSToolReport+="+ SUCCESS: Web Portal               $("https://$varCC_Name.rmm.datto.com")"
} else {
    $script:CSToolReport+="! FAILURE: Web Portal               $("https://$varCC_Name.rmm.datto.com")"
}

if (makeIPRequest "$varCC_Name-frontend-api.centrastage.net" "Web Portal GraphQL API  ") {
    $varPortalSuccess++
}

if ($varPortalSuccess -ge 2) {
    write-host "    OK!" -fo Green -NoNewline
} else {
    write-host " Failed" -fo Red -NoNewline
}

write-host "   ||   " -fo DarkGray -nonewline

#monitoring service
write-host "Monitoring Service          " -nonewline
If (makeHTTPRequest "https://$varCC_Name-monitoring.centrastage.net/device/1234/monitor" 200) { 
    write-host "   OK!" -fo Green
    $script:CSToolReport+="+ SUCCESS: Monitoring Service       https://$varCC_Name-monitoring.centrastage.net"
} else {
    write-host "Failed" -fo Red
    $script:CSToolReport+="! FAILURE: Monitoring Service       https://$varCC_Name-monitoring.centrastage.net"
}

#------------------------------------------------ sub-section: cypher/CC connectivity check

write-host "     Control Channel             " -NoNewline

#first, check to see if all the cyphers required for CC connections are enabled
if ($CSAdmin) {
    [int]$varCypherSuccess=0
    $arrCyphersY=@()
    [System.Collections.ArrayList]$arrCyphersN="WoW:256CBC384","WoW:128CBC256","WoW:256GCM384","WoW:128GCM256","Ntv:256CBC384","Ntv:128CBC256","Ntv:256GCM384","Ntv:128GCM256"
    "HKLM:\Software\WOW6432Node","HKLM:\Software" | % {
        if ($_ -match '6432') {$prefix='WoW'} else {$prefix='Ntv'}
        try {
            ((get-itemproperty "$_\Policies\Microsoft\Cryptography\Configuration\SSL\00010002" -ea stop).Functions) -split ',' | % {
                #if the key isn't defined, throw
                if ([string]::IsNullOrWhiteSpace($_)) {throw}
                #key is defined; what's in it
                switch -regex ($_) {
                    '^TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384($|_)' {
                        $varCypherSuccess++
                        $arrCyphersN.Remove("$prefix`:256CBC384")
                        $arrCyphersY+="$prefix`:256CBC384"
                    } '^TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256$($|_)' {
                        $varCypherSuccess++
                        $arrCyphersN.Remove("$prefix`:128CBC256")
                        $arrCyphersY+="$prefix`:128CBC256"
                    } '^TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256$($|_)' {
                        $varCypherSuccess++
                        $arrCyphersN.Remove("$prefix`:128GCM256")
                        $arrCyphersY+="$prefix`:128GCM256"
                    } '^TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384$($|_)' {
                        $varCypherSuccess++
                        $arrCyphersN.Remove("$prefix`:256GCM384")
                        $arrCyphersY+="$prefix`:256GCM384"
                    }
                }
            }
        } catch {
            $varCypherSuccess+=4 #if nothing's been configured, the defaults will see us through
        }
    }
    
    if ($varCypherSuccess -lt 1) {
        #no good cypher enabled :: throw the check
        write-host "Cypher" -fo Red -NoNewline
        $script:CSToolReport+="! FAILURE: Device does not have appropriate Cyphers enabled to facilitate a TLS connection to the Control Channel."
        $script:CSToolReport+="           Please ensure this device is still supported by Microsoft and has the latest updates and patches installed."
        $script:CSToolReport+="           If this error persists after doing this, please speak with Support and/or enable the Cyphers with the IISCrypto tool."
    } else {
        #at least one good cypher enabled :: perform the check
        if ($varCypherSuccess -lt 8) {
            if ([intptr]::Size -eq 4) {$varCypherSuccess-=4} #cosmetic compensation for the four erroneous WOW6432NODE passes on x86
            $script:CSToolReport+=": NOTICE: Device does not have all Cyphers enabled to facilitate a TLS connection to the Control Channel."
            $script:CSToolReport+="          The total amount of necessary Cyphers that were enabled was $varCypherSuccess out of a possible $([intptr]::Size)."
            $script:CSToolReport+="          Cyphers missing (TLS_ECDHE_RSA_WITH_AES): $($arrCyphersN -as [string])"
            $script:CSToolReport+="          Cyphers present (TLS_ECDHE_RSA_WITH_AES): $($arrCyphersY -as [string])"
            $script:CSToolReport+="          If the Agent is not connecting reliably or at all, please speak with Support and/or re-enable the Cyphers with the IISCrypto tool."
        } else {
            $script:CSToolReport+="+ SUCCESS: Device has necessary TLS Cyphers installed to facilitate Control Channel connection."
        }

        #actually check the connection :: try up to three times
        $varCounter=0
        while ($varCounter -lt 3) {
            if (makeIPRequest "$arrCC_CC" "Control Channel         " ".centrastage.net") {
                $varCCCheck++
                $varCounter=99
            } else {
                start-sleep -seconds 5
                $varCounter++
            }
        }

        if ($varCounter -eq 99) {
            write-host "   OK!" -fo Green -NoNewline
        } else {
            write-host "Failed" -fo Red -NoNewline
        }
    }
} else {
    write-host " Admin" -fo Red -NoNewline
    $script:CSToolReport+="! NOTICE: Unable to gauge Control Channel connectivity: No admin access to check connection cyphers."
}

write-host "   ||   " -fo DarkGray -nonewline

#audit service
write-host "Audit Service               " -NoNewline
if (makeHTTPRequest "https://$varCC_Name-audit.centrastage.net/cs/version" 200) {
    write-host "   OK!" -fo Green
    $script:CSToolReport+="+ SUCCESS: Audit service            https://$varCC_Name-audit.centrastage.net"
} else {
    write-host "Failed" -fo Red
    $script:CSToolReport+="! FAILURE: Audit service            https://$varCC_Name-audit.centrastage.net"
}

#=============================================== new line ===============================================

#ts
write-host "     Local Tunnel Server         " -NoNewline
if (makeIPRequest "ts.centrastage.net" "Local Tunnel Server     ") {
    write-host "   OK!" -fo Green -NoNewline
} else {
    write-host "Failed" -fo Red -NoNewline
}

write-host "   ||   " -fo DarkGray -nonewline

#real-time
write-host "Real-time Service           " -nonewline
if (makeHTTPRequest "https://$varCC_Name-realtime.centrastage.net/notifications/test" 200) {
    write-host "   OK!" -fo Green
    $script:CSToolReport+="+ SUCCESS: Real-time service        https://$varCC_Name-realtime.centrastage.net"
} else {
    write-host "Failed" -fo Red
    $script:CSToolReport+="! FAILURE: Real-time service        https://$varCC_Name-realtime.centrastage.net"
}

#=============================================== new line ===============================================

#component repo/s
write-host "     Components (Local/Offsite) " -nonewline
if (makeHTTPRequest "https://cpt$varCC_NameAlt.centrastage.net" 403) {
    $varCPTSuccess++
    $script:CSToolReport+="+ SUCCESS: Components (Local)       https://cpt$varCC_NameAlt.centrastage.net"
} else {
    $script:CSToolReport+="! FAILURE: Components (Local)       https://cpt$varCC_NameAlt.centrastage.net"
}

if (makeHTTPRequest "https://cpt$varCC_NameAlt.centrastage.net.s3.amazonaws.com" 403) {
    $varCPTSuccess++
    $script:CSToolReport+="+ SUCCESS: Components (Offsite)     https://cpt$varCC_NameAlt.centrastage.net.s3.amazonaws.com"
} else {
    $script:CSToolReport+="! FAILURE: Components (Offsite)     https://cpt$varCC_NameAlt.centrastage.net.s3.amazonaws.com"
}

if ($varCPTSuccess -ne 2) {
    write-host " Failed" -fo Red -NoNewline
} else {
    write-host "2/2 OK!" -fo Green -NoNewline
}

write-host "   ||   " -fo DarkGray -nonewline

#agent service
write-host "Agent Service               " -nonewline
if (makeHTTPRequest "https://$varCC_Name-agent.centrastage.net/cs/version" 200) {
    write-host "   OK!" -fo Green
    $script:CSToolReport+="+ SUCCESS: Agent service            https://$varCC_Name-agent.centrastage.net"
} else {
    write-host "Failed" -fo Red
    $script:CSToolReport+="! FAILURE: Agent service            https://$varCC_Name-agent.centrastage.net"
}

#=============================================== new line ===============================================

#agent notifications
write-host "     Agent Notifications         " -NoNewline
if (makeHTTPRequest "https://$varCC_Name-agent-notifications.centrastage.net" 401) {
    write-host "   OK!" -fo Green -NoNewline
    $script:CSToolReport+="+ SUCCESS: Agent Notifications      https://$varCC_Name-agent-notifications.centrastage.net"
} else {
    write-host "Failed" -fo Red -NoNewline
    $script:CSToolReport+="! FAILURE: Agent Notifications      https://$varCC_Name-agent-notifications.centrastage.net"
}

write-host "   ||   " -fo DarkGray -nonewline

#agent communications
write-host "Agent Communications        " -nonewline
if (makeHTTPRequest "https://$varCC_Name-agent-comms.centrastage.net" 401) {
    write-host "   OK!" -fo Green
    $script:CSToolReport+="+ SUCCESS: Agent Communications     https://$varCC_Name-agent-comms.centrastage.net"
} else {
    write-host "Failed" -fo Red
    $script:CSToolReport+="! FAILURE: Agent Communications     https://$varCC_Name-agent-comms.centrastage.net"
}

#=============================================== new line ===============================================

#agent gateway
[int]$varSuccess=0
write-host "     Agent Gateway & Features    " -NoNewline #stop adding subdomains, you're killing me
if (makeHTTPRequest "https://agent-gateway.$varCC_Name.rmm.datto.com" 403) {
    $varSuccess+=1
    $script:CSToolReport+="+ SUCCESS: Agent Gateway            https://agent-gateway.$varCC_Name.rmm.datto.com"
} else {
    $script:CSToolReport+="! FAILURE: Agent Gateway            https://agent-gateway.$varCC_Name.rmm.datto.com"
}

if (makeHTTPRequest "https://features.$varCC_Name.rmm.datto.com" 404) {
    $varSuccess+=2
    $script:CSToolReport+="+ SUCCESS: Agent Feature-flags      https://features.$varCC_Name.rmm.datto.com"
} else {
    $script:CSToolReport+="! FAILURE: Agent Feature-flags      https://features.$varCC_Name.rmm.datto.com"
}

if ($varSuccess -eq 3) {
    write-host "   OK!" -fo Green -NoNewline
} else {
    write-host "Issues" -fo Red -NoNewline
}

write-host "   ||   " -fo DarkGray -nonewline

#------------------------------------------------ sub-section: windows update checks

$script:CSToolReport+=""
$script:CSToolReport+=": Connectivity Scan results for Windows Update services:"
write-host "Windows Update Sites     " -nonewline
("https://windowsupdate.microsoft.com","http://download.windowsupdate.com","https://download.microsoft.com","http://ctldl.windowsupdate.com","https://update.microsoft.com") | % {
    if (makeHTTPRequest "$_" 200) {
        $script:CSToolReport+="+ SUCCESS: Windows Update Services  $_"
        $varWUpd++
    } else {
        $script:CSToolReport+="! FAILURE: Windows Update Services  $_"
    }
}

if (makeHTTPRequest "http://dl.delivery.mp.microsoft.com" 403) {
    $script:CSToolReport+="+ SUCCESS: Windows Update Services  http://dl.delivery.mp.microsoft.com"
    $varWUpd++
} else {
    $script:CSToolReport+="! FAILURE: Windows Update Services  http://dl.delivery.mp.microsoft.com"
}

("https://wdcp.microsoft.com","https://wdcpalt.microsoft.com") | % {
    if (makeHTTPRequest "$_" 503) {
        $script:CSToolReport+="+ SUCCESS: Windows Update Services  $_"
        $varWUpd++
    } else {
        $script:CSToolReport+="! FAILURE: Windows Update Services  $_"
    }
}

if ($varWUpd -ne 8) {
    write-host "      $varWUpd/8" -fo Red
    $script:CSToolReport+=": Windows Update sites can be unreliable. Treat a couple of failures as an anomaly."
} else {
    write-host "8/8 OK!"        -fo Green
}

#=============================================== new line ===============================================

$script:CSToolReport+=""
$script:CSToolReport+=": Connectivity Scan results for Datto RMM IP-based services:"

#gather platform IP addresses from DNS
write-host "     Platform IPs" -NoNewline

#first, compile a list of IPs for the platform at-hand to check later
$arrPlatIPs=@()
try {
    $varPlatIPCheck=[System.Net.Dns]::GetHostAddresses("$varCC_Name-ips.centrastage.net")
    if ($(($varPlatIPCheck|measure-object).count) -le 0) {
        throw
    } else {
        $varPlatIPCheck | % {
            $arrPlatIPs+=$($_.IPAddressToString)
        }
    }
} catch {
    write-host "             No Access" -fo Red -NoNewline
    $script:CSToolReport+="! FAILURE: Platform IP list         $varCC_Name-ips.centrastage.net"
    $script:CSToolReport+="           The tool will be unable to test Platform IPs as it could not enumerate any."
}

#now check through our list
if (($arrPlatIPs|measure-object).count -ge 1) {
    processIPList $arrPlatIPs "     Platform IPs              " "Platform     "
}

write-host "   ||   " -fo DarkGray -nonewline

#VERSION: cagService
write-host "Service version   " -nonewline
try {
    [xml]$varCagSvcXML=(New-Object System.Net.WebClient).DownloadString("https://update$varCC_NameAlt.centrastage.net/cagupdate/UpdateState.xml")
    write-host "OK:        $($varCagSvcXML.UpdateStatus.CurrentVersion)" -fo Yellow
    $varCagSvc=$varCagSvcXML.UpdateStatus.CurrentVersion
} catch {
    write-host "    No Access" -fo Red
}

#=============================================== new line ===============================================

#tunnel servers :: as before, but with an additional compilation step
write-host "     Tunnel Server IPs" -NoNewline
$arrTunIPs=@()
try {
    $varTunIPCheck=[System.Net.Dns]::GetHostAddresses("tunnel-ips.centrastage.net")
    if ($(($varTunIPCheck|measure-object).count) -le 0) {
        #do nothing, we'll verify later
    } else {
        $varTunIPCheck | % {
            $arrTunIPs+=$($_.IPAddressToString)
        }
    }
} catch {
    $CSTunIPFail=$true
}

#now check through our list
if (($arrTunIPs|measure-object).count -ge 1) {
    processIPList $arrTunIPs "     Tunnel Server IPs       " "Tunnel Server"
} else {
    $CSTunIPFail=$true
}

if ($CSTunIPFail) {
    write-host "        No Access" -fo Red -NoNewline
    $script:CSToolReport+="! FAILURE: Platform IP list         tunnel-ips.centrastage.net"
    $script:CSToolReport+="           The tool will be unable to test Tunnel Server IPs as it could not enumerate any."
}

write-host "   ||   " -fo DarkGray -nonewline

#aemagent version
write-host "AEMAgent version  " -nonewline
try {
$varAEMAjson=(New-Object System.Net.WebClient).DownloadString("https://update$varCC_NameAlt.centrastage.net/cagupdate/aem-agent/version.json")
$varAEMAver=$varAEMAjson.split('"')[3]
    write-host "OK: $varAEMAVer" -fo Yellow
} catch {
    write-host "      No Access" -fo Red
}

#=============================================== new line ===============================================

write-host `r
write-host "        Expect ~10 IP check failures." -fo Green -NoNewline
write-host " Version checks are testing connectivity." -fo Cyan
write-host `r

write-host "Datto RMM Platform connectivity checks complete." -fo Cyan
write-host "Advancing to Page 2 (Endpoint checks)..." -fo Cyan

# ==================================================================== PAGE TWO ===================================================================

#------------------------------------------------ sub-section: preamble

write-host "Page 2: Endpoint Health"
if ($CSAdmin) {
    write-host "Tool is being run as an Administrator    " -fo Cyan
} else {
    write-host "Tool is not being run as an Administrator" -fo Red
}
write-host "============================="
write-host "                               -== Endpoint Checks ==-" -fo Green
write-host `r

#system info
write-host "     Device Detail: " -NoNewline
write-host "`"$env:Computername`" " -NoNewline -fo Yellow
write-host "Build $varWinver / $varCaption "

#------------------------------------------------ sub-section: SKU check (july 2024)

#write log output
$script:CSToolReport+="=================================="
$script:CSToolReport+= ""
$script:CSToolReport+="= Endpoint and Agent Health Check Results:"

#check
write-host "            OS SKU: " -NoNewline; write-host "$varSKU" -NoNewline -fo Yellow; write-host " / " -NoNewline

if (((7..10),(12..15),(17..25),(29..46),(50..56),(59..64),72,76,77,79,80,95,96,109,110,120,(143..148),159,160,168,169 | % {$_}) -contains $varSKU) {
    write-host "Device is a Server" -fo Cyan
    $script:CSToolReport+=": Device is a Server (SKU $varSKU)."
    $varServer=$true
} elseif ((2,3,5,11,26,47,66,68,(98..101) | % {$_}) -contains $varSKU) {
    write-host "Device is running a Home version of Windows" -fo Red
    $script:CSToolReport+="! WARNING: Device is running a Home version of Windows (SKU $varSKU)."
    $script:CSToolReport+="           This SKU is not officially supported or tested against."
} else {
    write-host "Device is a Workstation" -fo Cyan
    $script:CSToolReport+=": Device is a Workstation (SKU $varSKU)."
}

#------------------------------------------------ sub-section: uptime calculation

try {
    $varLastBootTime=[Management.ManagementDateTimeConverter]::ToDateTime($varLastBootWMI) | New-TimeSpan
     $varBootString='{0:D3}D ' -f $varLastBootTime.Days
    $varBootString+='{0:D2}H ' -f $varLastBootTime.Hours
    $varBootString+='{0:D2}M ' -f $varLastBootTime.Minutes
} catch {
    $varWMIIssues="Significant"
    $varBootString="WMI Error"
}

write-host "     System Uptime: " -NoNewline
write-host $varBootString -fo Yellow

write-host "`r"

$script:CSToolReport+=": System Uptime: $varBootString"

#------------------------------------------------ sub-section: AEMAgent

#AEMAgent check (stalled/issues/outdated/offline)
write-host "     AEMAgent State           " -NoNewline

if ($varOnDemand -eq 1) {
    #startup issues :: 5779805
    try {
        if (((get-date) - $((get-item "$env:PROGRAMDATA\CentraStage\AEMAgent\DataLog\aemagent.log").LastWriteTime)) -gt $(new-timespan -minutes 30)) {
            $CSAAIssues="  Stalled"
            $script:CSToolReport+= "! FAILURE: AEMAgent appears to have stopped logging data."
            $script:CSToolReport+= "           Please consider reinstalling the Agent."
        } else {
            $script:CSToolReport+= "+ SUCCESS: AEMAgent is able to start up successfully."
        }
    } catch {
            $CSAAIssues="  Absent"
            $script:CSToolReport+= "! FAILURE: AEMAgent does not appear to be producing logging data."
            $script:CSToolReport+= "           It is possible AEMAgent has not been despatched onto this device."
    }

    #HTTP OK
    if ($CSAAIssues) {
        $script:CSToolReport+= " Skipping HTTP check as the Monitoring Agent has not started properly."
    } else {
        #make a log instalment of just the active session and analyse it for the correct HTTP OKs
        try {
            $CSCurrentLog=$CSDataLog | Select-Object -Skip ((($CSDataLog | Select-String -Pattern 'SYSTEM START')[-1].LineNumber) - 1)
        } catch {
            $CSCurrentLog=$CSDataLog
        }

        $varLog50=($CSCurrentLog | select -Last 50 -ErrorAction SilentlyContinue) -split [System.Environment]::NewLine

        if (($CSCurrentLog | ? {$_ -match "`"HttpStatusCode`": 200"} | Measure-Object).count -lt 3) {
            if (!$CSAAIssues) {$CSAAIssues="Restarted"}
            Stop-Process -Name AEMAgent -Force -ErrorAction SilentlyContinue 2>&1>$null
            start-sleep -seconds 1
            $count=0
            $script:CSToolReport+= "! FAILURE: AEMAgent appears to be having trouble sustaining a connection. (Fewer HTTP 200s than expected.)"
            $script:CSToolReport+= "           The AEMAgent Process has been restarted. Please re-run this test in two minutes and contact support if issues persist."
            while (!(get-process AEMAgent -ErrorAction SilentlyContinue)) {
                $count++
                $varRuntime=60-$count
                write-host "     Wait ($varRuntime) " -fo DarkGray
                [Console]::SetCursorPosition(30,8)
                if ($count -eq 60) {
                    $CSAAIssues="   Failed"
                    $script:CSToolReport+= "! FAILURE: The AEMAgent Process could not be restarted gracefully. Consider re-installing."
                    break
                }
                start-sleep -Seconds 1
            }
        } else {
            $script:CSToolReport+= "+ SUCCESS: AEMAgent appears to be communicating with the platform. Additional tests will be performed later."
        }
    }

    #is it the latest version?
    $CSAAVerLocal=((($CSDataLog | Select-Object -Last 10 | select-string -Pattern '^[0-9]' | select-object -last 1) -as [string]) -split ("\|"))[0]
    if (!$CSAAVerLocal) {
        $CSAAIssues="   Absent"
        $script:CSToolReport+= "! FAILURE: AEMAgent does not appear to be running."
        $script:CSToolReport+= "  Ensure CagService has proper connectivity to the platform in order to download AEMAgent."
    } elseif ($CSAAVerLocal -ne $varAEMAVer) {
        #version mismatch
        if (!$CSAAIssues) {$CSAAIssues=" Outdated"}
        $script:CSToolReport+= "! FAILURE: AEMAgent is out of date (Latest: $varAEMAVer/Local: $CSAAVerLocal)."
        $script:CSToolReport+= "           This might be because the device cannot run .NET 6.0. Ensure the latest VC++ Redist is installed."
    } else {
        $script:CSToolReport+= "+ SUCCESS: AEMAgent is up-to-date (Version $varAEMAVer)."
    }

    #is it running?
    if ((get-process AEMAgent -ea 0 | Measure-Object).count -lt 1) {
        $script:CSToolReport+= "! FAILURE: AEMAgent is not running. It may not be installed."
        $script:CSToolReport+= "  If subsequent checks indicate connection issues, please ensure CagService is able to connect to download AEMAgent."
        if (!$CSAAIssues) {$CSAAIssues="  Offline"}
    } else {
        $script:CSToolReport+= "+ SUCCESS: AEMAgent is running and monitoring."
    }

    #is it blocked?
    if (($CSCurrentLog | where-object {$_ -match 'Waiting for human approval|KeyException'} | Measure-Object).count -ge 1) {
        $CSAAIssues=" Blocked?"
        $script:CSToolReport+= "! WARNING: The platform may be rejecting the device's Agent key. Check the device over and ensure it hasn't been tampered with."
        $script:CSToolReport+= "           If it hasn't been already, re-approve the device from the New UI in the Devices section."
    }

    #is it in the correct location i
    $CSReg=(gp "HKLM:\Software\CentraStage" -ea 0).AgentFolderLocation
    if ($CSReg) {
        if ($CSProgData) {
            if ($CSReg -ne $CSProgData) {
                $CSAAIssues=" Registry"
                $script:CSToolReport+= "! WARNING: HKLM:\Software\CentraStage!AgentFolderLocation and actual AEMAgent running locations disagree."
                $script:CSToolReport+= "  AgentFolderLocation value: [$CSReg]"
                $script:CSToolReport+= "  Please contact Support. A reinstallation is recommended."
            }
        }
    } else {
        $CSAAIssues=" Registry"
        $script:CSToolReport+= "! WARNING: The Registry value HKLM:\Software\CentraStage!AgentFolderLocation is absent. Reinstall recommended."
    }

    #is it in the correct location ii
    if ($CSAAIssues -ne " Registry") {
        if (($CSProgData | split-path -leaf) -notmatch '^CentraStage$') {
            $CSAAIssues=" Location"
            $script:CSToolReport+= "! WARNING: Agent folder install location is not ProgramData\CentraStage."
            $script:CSToolReport+= "  Please contact Support. A reinstallation is recommended."
        }
    }

    #event log issues?
    if (($CSCurrentLog | where-object {$_ -match 'The event log file is corrupted'} | Measure-Object).count -ge 1) {
        $CSAAIssues="Event Log"
        $script:CSToolReport+= "! WARNING: The Agent is reporting that the device's Event Log is corrupted. Please triage."
    }

    if (!$CSAAIssues) {
        write-host "      OK!" -fo Green -NoNewline
    } else {
        write-host "$CSAAIssues" -fo Red -NoNewline
    }
} elseif ($varOnDemand -eq 2) {
    write-host " OnDemand" -fo Yellow -NoNewline
    $script:CSToolReport+= ": UNKNOWN: AEMAgent health checks skipped; the Agent is running as OnDemand, so AEMAgent is not running."
} else {
    write-host " No Admin" -fo Red -NoNewline
    $script:CSToolReport+= ": UNKNOWN: AEMAgent health checks skipped; as the script was not run as Administrator, the OnDemand check could not run."
}

write-host "   ||   " -fo DarkGray -nonewline

#------------------------------------------------ sub-section: CagService

#is it the latest version
$CSAgentVer=(([System.Diagnostics.FileVersionInfo]::GetVersionInfo("$varProg32\CentraStage\Core.dll").FileVersion).split(".")[3])
if ($varCagSvc) {
    if ($varCagSvc -eq $CSAgentVer) {
        $script:CSToolReport+= "+ SUCCESS: CagService Agent Service is up-to-date (Version $CSAgentVer)."
    } else {
        $CSCSIssues="       Outdated"
        $script:CSToolReport+= "! FAILURE: CagService is out of date."
        $script:CSToolReport+= "           Latest version is $varCagSvc. Version on Endpoint is $CSAgentVer`."
    }
} else {
    $CSCSIssues="         Issues"
    $script:CSToolReport+= "! FAILURE: Connection issues prevented the tool from finding out whether CagService is up-to-date."
}

#is it running
write-host "CagService State   " -NoNewline
if ((get-process CagService -ea 0 | measure-object).count -lt 1) {
    if (!$CSCSIssues) {$CSCSIssues="        Offline"}
    $script:CSToolReport+= "! FAILURE: CagService Agent Service is not running."
} else {
    $script:CSToolReport+= "+ SUCCESS: CagService Agent Service is running. "
}

#is gui.exe the same version as core.dll?
if ($varCagSvc -eq $((([System.Diagnostics.FileVersionInfo]::GetVersionInfo("$varProg32\CentraStage\gui.exe").FileVersion).split(".")[3]))) {
    $script:CSToolReport+= "+ SUCCESS: GUI.exe and Core.dll are the same version."
} else {
    $CSCSIssues="       Outdated"
    $script:CSToolReport+= "! FAILURE: GUI.exe and Core.dll are not the same version."
}

#is the device overprovisioned? (this will override any other issue)
$CSLog=get-content "$varProg32\CentraStage\log.txt" -ea 0
if ($CSLog | Select-String -Pattern 'error code 429' -Quiet) {
    if (!($CSLog | Select-String -Pattern 'Response is Http - 200' -Quiet)) {
        $CSCSIssues="Overprovisioned"
        $script:CSToolReport+= "! FAILURE: The Agent cannot contact the platform because the account has passed its device limit."
        $script:CSToolReport+= "           Please reduce the amount of devices in your account or contact your account manager."
    }
}

#dotnet misconfiguration (override)
if (([IntPtr]::size) -eq 8) {
    if (test-path "$env:systemRoot\Microsoft.NET\Framework64\v2.0.50727\ldr64.exe" -ea 0) {
        if (((cmd /c "$env:systemRoot\Microsoft.NET\Framework64\v2.0.50727\ldr64.exe query" | select-string '0x0') -as [string]).split('x')[1] -eq '00000000') {
            $CSCSIssues="Framework Issue"
            $script:CSToolReport+="! FAILURE: This device has been configured to use the 32-bit (Windows-on-Windows) version of the .NET Framework."
            $script:CSToolReport+=""
            $script:CSToolReport+="  Some applications, like CagService, are configured to use the device's native architecture, but a setting"
            $script:CSToolReport+="  exists for .NET to use the 32-bit version in all situations. On this device, that setting has been enabled."
            $script:CSToolReport+="  This override setting is incompatible with the Datto RMM Agent as it is known to cause multiple issues."
            $script:CSToolReport+=""
            $script:CSToolReport+="  As this is a localised issue, Support cannot assist with it; most likely this setting was either configured"
            $script:CSToolReport+="  deliberately by the System Administrator or unilaterally during an unrelated software installation."
            $script:CSToolReport+="  (The default behaviour of the .NET Framework on 64-bit systems is to use 64-bit wherever possible.)"
            $script:CSToolReport+="  In either case, changing it back to the recommended system default could cause unforeseen issues, so the"
            $script:CSToolReport+="  command given below should be run on this endpoint only after careful consideration."
            $script:CSToolReport+=""
            $script:CSToolReport+="  The following Batch command will set the .NET Framework back to its default architecture setting:"
            $script:CSToolReport+="  C:\Windows\Microsoft.NET\Framework64\v2.0.50727\ldr64.exe set64"
            $script:CSToolReport+=""
            $script:CSToolReport+="  This will re-configure the Framework to use 64-bit where possible. This will fix the Datto RMM Agent, but"
            $script:CSToolReport+="  it may break whatever else needed things configured that way in the first place. Kaseya cannot be held"
            $script:CSToolReport+="  responsible for issues that arise as a result of changing this setting back to its system default."
        }
    }
}

if (!$CSCSIssues) {
    write-host "            OK!" -fo Green
} else {
    write-host "$CSCSIssues" -fo Red
}

#=============================================== new line ===============================================

#------------------------------------------------ sub-section: smaller checks

#monitor health: errors appearing in AEMAgentLog
write-host "     Monitor Health            " -nonewline

$arrError=@{
   'Exception'           ='Connection exception; a connection was attempted but failed without receiving a proper response.'
   'RE-TRY'              ='Connection retry attempt; a connection failure spawned a subsequent reconnection attempt.'
   'HttpStatusCode": 403'='HTTP 403: Unauthorised. This can indicate platform-side device rejection. Check the web portal for device approvals.'
}

$arrError.GetEnumerator() | % {
    $currentName=$_.Name
    $currentValue=$_.Value
    if ((($varLog50 | ? {$_ -match $currentName} | measure-object).count) -gt 4) {
        $CSMonHealth="  Issues"
        $script:CSToolReport+= "! FAILURE: $(($varLog50 | ? {$_ -match $currentName} | Measure-Object).count) recent errors matching `'$currentName`' detected in AEMAgent log file. "
        $script:CSToolReport+= "           Error detail: $currentValue"
    }
}

if (!$CSMonHealth) {
    write-host "     OK!" -fo Green -NoNewline
    $script:CSToolReport+= "+ SUCCESS: No connection issues were identified in the AEMAgent monitoring log. "
} else {
    write-host "$CSMonHealth" -fo Red -NoNewline
}

write-host "   ||   " -fo DarkGray -nonewline

#duplicate nlog.dll check
write-host "NLog.dll Clashes          " -nonewline
$CSPathTest=@(Get-ChildItem -Path "C:\Windows\Microsoft.NET\assembly" -Recurse | Where-Object {$_.Name -match "^nlog\.dll"})
if ($CSPathTest.length -gt 0) {
        $CSDupeFound=$true
        $script:CSToolReport+= "! FAILURE: NLog.dll was found in the Endpoint`'s GAC, which can cause the Agent not to start."
        $script:CSToolReport+= "           If the Agent does not start, remove NLog.dll from the C:\Windows\Microsoft.NET\Assembly location."
        $script:CSToolReport+= "           If the Agent is functioning normally, this can be disregarded."
}
if (!$CSDupeFound) {
    write-host " 0 Found" -fo Green
    $script:CSToolReport+= "+ SUCCESS: No NLog.dll clashes were found on Endpoint."
} else {
    write-host "Detected" -fo Red
}

#=============================================== new line ===============================================

#------------------------------------------------ sub-section: dotnet checks for 10.8+

write-host "     System Compatibility   " -nonewline
#if it's less than ten/some server variants, throw it in the bin
if ($varWinver -lt 10240) {
    switch -regex ($varWinver) {
        '^2' {
            write-host "   Obsolete" -fo Red -NoNewline
            $script:CSToolReport+="! FAILURE: The Agent is no longer supported on Windows XP. Please replace the device."
        } '^3' {
            write-host "   Obsolete" -fo Red -NoNewline
            $script:CSToolReport+="! FAILURE: The Agent is no longer supported on Windows XP/Server 2003. Please replace the device."
        } '^6' {
            write-host "   Obsolete" -fo Red -NoNewline
            if ($varServer) {
                $script:CSToolReport+="! FAILURE: The Agent is no longer supported on Windows Server 2008 (or derivatives). Please replace the device."
            } else {
                $script:CSToolReport+="! FAILURE: The Agent is no longer supported on Windows Vista. Please replace the device."
            }
        } '^7' {
            write-host "   Obsolete" -fo Red -NoNewline
            if ($varServer) {
                $script:CSToolReport+="! FAILURE: The Agent is no longer supported on Windows Server 2008 R2 (or derivatives). Please replace the device."
            } else {
                $script:CSToolReport+="! FAILURE: The Agent is no longer supported on Windows 7 (or derivatives). Please replace the device."
            }
        } '^9' {
            if ($varServer) {
                if ($([int][double]::Parse((Get-Date -UFormat %s))) -gt 1791590400) {
                    #10 october 2026
                    write-host "   Obsolete" -fo Red -NoNewline
                    $script:CSToolReport+="! FAILURE: Windows Server 2012/R2 became EOL in October 2026. This OS is no longer maintained and represents a security risk."
                } else {
                    write-host "    Caution" -fo Yellow -NoNewline
                    $script:CSToolReport+="! CAUTION: Windows Server 2012/R2 became EOL in October 2023, with extended support purchasable until 2026."
                }
            } else {
                $script:CSToolReport+="! FAILURE: Windows 8/8.1 support ran out in January 2023. This OS is no longer maintained and represents a security risk."
            }
        } default {
            write-host "   Obsolete" -fo Red -NoNewline
            $script:CSToolReport+="! FAILURE: Versions of Windows earlier than 10 are no longer maintained by Microsoft and represent a security risk."
        }
    }
} else {
    #running 10+/server 2016+; check for VC++
    if (!(getGUID2 'Visual C\+\+ 2015-20')) {
        write-host "Update VC++" -fo Red -NoNewline
        $script:CSToolReport+="! FAILURE: AEMAgent requires the latest Visual C++ Redistributable package to run."
        $script:CSToolReport+="           Ensure the packages for both architectures are installed."
        $script:CSToolReport+="           If these packages are already installed and the Agent is functioning, there may be an issue"
        $script:CSToolReport+="           with this device's Registry; please fully scrutinise this tool's log output for indicators."
    } else {
        if ($varServer) {
            $varKernelMin=14393 #server 2016
        } else {
            $varKernelMin=19045 #w10 22h2
        }

        if ($varWinVer -lt $varKernelMin) {
            write-host "   Obsolete" -fo Red -NoNewline
            $script:CSToolReport+="! FAILURE: Windows 10 pre-22H2 support has expired. This OS is no longer maintained and represents a security risk."
        } else {
            write-host "        OK!" -fo Green -NoNewline
            $script:CSToolReport+= "+ SUCCESS: This device's operating system is still maintained by Microsoft and will support Datto RMM."
        }
    }
}

write-host "   ||   " -fo DarkGray -nonewline
    
#FIPS-compliance check
write-host "Windows 'FIPS Mode'       " -nonewline
if ((Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Lsa\FIPSAlgorithmPolicy" -ea 0).Enabled -eq 1) {
    $varFIPS++
}
if ((Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Lsa\FIPSAlgorithmPolicy" -ea 0).MDMEnabled -eq 1) {
    $varFIPS++
}

if ($varFIPS) {
    write-host " Engaged" -fo Red
    $script:CSToolReport+= "! FAILURE: Endpoint enforces Windows 'FIPS mode'. This setting does not make the device any safer; rather,"
    $script:CSToolReport+= "  it can actually hinder security as it prevents newer cryptographic cyphers, like those used by Datto RMM,"
    $script:CSToolReport+= "  from functioning. Regardless of product FIPS support, Datto RMM does not support 'FIPS mode' and never"
    $script:CSToolReport+= "  will, nor will any major RMM software product; it must be disabled for the software to work properly."
    $script:CSToolReport+= "  More info: https://preview.tinyurl.com/3a9xs3b8 (Web Archive link of archived Microsoft documentation)"
} else {
    write-host "Disabled" -fo green
    $script:CSToolReport+= "+ SUCCESS: FIPS-Compliance, which can cause connectivity issues, is not mandated on this device."
}

#=============================================== new line ===============================================

#system drive: at least 1GB free
write-host "     System Drive Space       " -nonewline

try {
    if ([math]::Round((gwmi win32_logicaldisk -Filter "DeviceID='$env:SystemDrive'" -ea stop).FreeSpace /1GB) -lt 1) {
        write-host "Need >1GB" -fo Red -nonewline
        $script:CSToolReport+= "! FAILURE: Endpoint requires at least 1GB of free space on the System Drive to function properly."
    } else {
        write-host ">1GB Free" -fo Green -NoNewline
        $script:CSToolReport+= "+ SUCCESS: Endpoint has at least 1GB of free space on the System Drive."
    }
} catch {
    write-host "WMI Error" -fo Red -nonewline
    $script:CSToolReport+= "! FAILURE: Unable to ascertain disk space; WMI issues suspected"
}

write-host "   ||   " -fo DarkGray -nonewline

#event logs
write-host "RMM Service Event Logs    " -nonewline
$CSEventLogData=Get-EventLog -LogName System -Source 'Service Control Manager' -After (Get-Date).AddDays(-7)| Where-Object -FilterScript {($_.Message -match 'CentraStage') -and ($_.EventID -notmatch '^(7036|7045)$')} | Select-Object -Property EventID, Message, TimeWritten | Group-Object -Property Message
if (($CSEventLogData | measure-object).count -ge 1) {
        $script:CSToolReport+=""
        $script:CSToolReport+="= Summary of CagService-related problem events from last 7 days of Event Log:"
    if ((get-host).version.Major -ge 5) {
        #powershell 5 version
        foreach ($Event in $CSEventLogData) {
            if ($event) {
                $CSLogsPresent++
                $script:CSToolReport+="! FAILURE: Noteworthy CagService Event Log group discovered:"
                $script:CSToolReport+="Event group with IDs [$($event.Group.eventID)] logged at [$($event.group.TimeWritten)]"
                $script:CSToolReport+=": : : : : : : : : : : : : : : : : : :"
                $script:CSToolReport+=$event.Group.message
                $script:CSToolReport+="`r`n- - - - - - - - - - - - - - - - - - -"
            }
        }
    } else {
        #powershell 2-4 version
        if ($CSEventLogData) {
            $CSLogsPresent++
            $script:CSToolReport+="! FAILURE: Noteworthy CagService Event Log entries noted in attached CSV."
            if (!$script:varResultDir) {
                makeFolder
            }
            $CSEventLogData | Export-CSV -path "$script:varResultDir\AHC-$env:computername-EventLog-$(EpochTime).csv"
        }
    }
}

if (!$CSLogsPresent) {
    write-host "0 Issues" -fo Green
    $script:CSToolReport+="+ SUCCESS: No noteworthy RMM Agent Service-related Event Logs were discovered."
} else {
    $script:CSToolReport+=": No further Event Log entries of note were discovered."
    $script:CSToolReport+=""
    write-host "  Issues" -fo Red
}

#=============================================== new line ===============================================

#certificate check :: march 2026
write-host "     SSL Configuration         " -NoNewline

$arrCerts=@{
   '925A8F8D2C6D04E0665F596AFF22D863E8256F3F'=[psCustomObject]@{Subject="CN=Starfield Services Root Certificate Authority - G2, O=Starfield Technologies, Inc., L=Scottsdale, S=Arizona, C=US";Location=$false}
   'DF3C24F9BFD666761B268073FE06D1CC8D4F82A4'=[psCustomObject]@{Subject="CN=DigiCert Global Root G2, OU=www.digicert.com, O=DigiCert Inc, C=US";                                               Location=$false}
   'DDFB16CD4931C973A2037D3FC83A4D7D775D05E4'=[psCustomObject]@{Subject="CN=DigiCert Trusted Root G4, OU=www.digicert.com, O=DigiCert Inc, C=US";                                              Location=$false}
}

$arrCerts.GetEnumerator() | % {
    $varKey=$_.key
    #check root
    if (gci 'Cert:\LocalMachine\Root' -ea 0 | ? {(($_.Thumbprint -replace '\s','').ToUpper()) -eq $varKey} | select -first 1) {
        $arrCerts[$varKey].Location="Root"
    } else {
        #check authRoot
        if (gci 'Cert:\LocalMachine\AuthRoot' -ea 0 | ? {(($_.Thumbprint -replace '\s','').ToUpper()) -eq $varKey} | select -first 1) {
            $arrCerts[$varKey].Location="AuthRoot"
        }
    }
}

$arrCerts.GetEnumerator() | ? {$_.value.location} | % {
    $script:CSToolReport+="+ SUCCESS: Located Cert [$($_.key)] in $($_.value.location) store"
}

if ((($arrCerts.GetEnumerator() | ? {!($_.value.location)}).value.subject) -match 'Starfield') {
    $script:CSToolReport+="! FAILURE: The Amazon (Starfield) Root CA certificate necessary to access Datto RMM online have"
    $script:CSToolReport+="           not been installed. These will need to be installed in order to access the Datto RMM Web Portal."
    $script:CSToolReport+="           Download Amazon Root CA 1 certificate at: https://www.amazontrust.com/repository/ and install."
    $script:CSToolReport+="           Ensure certificates are installed at the machine-level and NOT the user-level."
    $CSCertFail=$true
}

if ((($arrCerts.GetEnumerator() | ? {!($_.value.location)}).value.subject) -match 'DigiCert') {
    $script:CSToolReport+="! FAILURE: The DigiCert Global Root certificates necessary for Agent connectivity are not installed."
    $script:CSToolReport+="           This will need to be installed in order to facilitate Agent-to-Platform connectivity."
    $script:CSToolReport+="           Download 'DigiCert Global Root G2' and 'DigiCert Trusted Root G4' from this site:"
    $script:CSToolReport+="           https://www.digicert.com/kb/digicert-root-certificates.htm"
    $script:CSToolReport+="           And install, ensuring certificates are installed at the machine-level and NOT the user-level."
    $CSCertFail=$true
}

if ($CSCertFail) {
    write-host "  Absent" -fo Red -NoNewline
} else {
    #since this check passed, perform the rest
    if ((gp "HKLM:\Software\Policies\Microsoft\SystemCertificates\ChainEngine\Config" -ea 0).options -eq 2) {
        write-host "  Adjust" -fo Red -NoNewline
        $script:CSToolReport+="! FAILURE: Authority Information Access (AIA) is disabled or misconfigured on this device."
        $script:CSToolReport+="  This may inhibit the building of certificate chains critical to establishing safe connections."
        $script:CSToolReport+="  More information: https://learn.microsoft.com/en-us/windows-server/security/authority-information-access-retrieval"
    } else {
        #all good
        write-host "     OK!" -fo GrEeN -NoNewline
        $script:CSToolReport+="+ SUCCESS: The relevant certificates to access Datto RMM online are installed."
        $script:CSToolReport+="           Authority Information Access (AIA) is configured properly on this device."
        $script:CSToolReport+="           This tool cannot check whether these certificates are actually enabled; in case of TLS issues, it may be"
        $script:CSToolReport+="           worth investigating whether the Amazon Root CA, Starfield, and DigiCert Global Root certificates on the"
        $script:CSToolReport+="           device have not had their capabilities malconfigured."
    }
}

write-host "   ||   " -fo DarkGray -nonewline

#------------------------------------------------ sub-section: various agent file verification checks

write-host "Agent File Validation    " -nonewline
if (!$CSAdmin) {
    write-host " No Admin" -fo Red
    $script:CSToolReport+=": UNKNOWN: Tool was unable to analyse Agent files for consistency because it was not run with Administrator-level access."
} else {

    #$arrXMLFiles used to be defined here, but it's been moved to load earlier so we can tell if the device is onDemand -- look for string "40HC89"
    if (($arrXMLFiles | measure-object).count -eq 0) {
        $script:CSXMLError++
        $script:CSToolReport+="! FAILURE: Could not locate Agent XML files. Is the Agent installed?"
    }

    $arrXMLFiles | ? {$_} | % {
        $CSXMLTest=New-Object System.Xml.XmlDocument
        try {
            $CSXMLTest.Load("$_")
            $script:CSToolReport+="+ SUCCESS: $_ passed XML verification."
        } catch [System.Xml.XmlException] {
            $script:CSXMLError++
            $script:CSToolReport+="! FAILURE: $_ is corrupt. Consider reinstalling the Agent."
        }
    }

    #check submittedpatches.json
    try {
        $CSPatchJSON=get-content "$env:ProgramData\CentraStage\SubmittedPatches.json" -ErrorAction Stop
		if ($CSPatchJSON.Substring(0,2) -notmatch "^\[\{$" -or $CSPatchJSON.Substring($CSPatchJSON.Length-2) -notmatch "^\}\]$") {
            $script:CSToolReport+="! FAILURE: $env:ProgramData\CentraStage\SubmittedPatches.json is corrupt."
		    $script:CSToolReport+="           Please delete this file or re-install the Agent."
            $script:CSXMLError++
        } else {
            $script:CSToolReport+="+ SUCCESS: $env:ProgramData\CentraStage\SubmittedPatches.json appears to be fine."
        }
    } catch {
        $script:CSToolReport+="+ SUCCESS: This device does not appear to be using Patch Management, making verification of patching JSON files unnecessary."
    }

    #check snmp.json
    if ((get-content "$env:ProgramData\CentraStage\snmp.json" -ea 0 | Select-Object -Last 1) -match '}') {
        $script:CSToolReport+="+ SUCCESS: The Agent's SNMP.json file did not contain any errors."
    } else {
        if (test-path "$env:ProgramData\CentraStage\") {
            if (test-path "$env:ProgramData\CentraStage\snmp.json" -ErrorAction SilentlyContinue) {
                Remove-Item "$env:ProgramData\CentraStage\snmp.json" -Force
            }
            set-content -Value '{
            "version": "1",
            "group": []
            }' -Path "$env:ProgramData\CentraStage\snmp.json" -Force
        } else {
            $script:CSToolReport+="! FAILURE: There is no CentraStage folder in ProgramData. Is the Agent installed?"
        }
        $script:CSToolReport+="! FAILURE: The Agent's SNMP.json file was absent or corrupt and has been remade from scratch."
        $script:CSXMLError++
    }

    #check software management
    if (Get-Childitem "$env:PROGRAMDATA\CentraStage\AEMAgent\Downloads" -Recurse | ? {$_.LastWriteTime -le (get-date).addDays(-1) }) {
        Get-Childitem "$env:PROGRAMDATA\CentraStage\AEMAgent\Downloads" -Recurse | ? {$_.LastWriteTime -le (get-date).addDays(-1) } | % {Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue}
        $script:CSToolReport+=":  NOTICE: Software Management downloads cleared. This can cause some transient download issues."
        $script:CSXMLError++
    } else {
        $script:CSToolReport+="+ SUCCESS: No need to adjust Software Management downloads folder."
    }

    #display results
    if ($script:CSXMLError) {
        write-host "Check Log" -fo Red
    } else {
        write-host " 0 Issues" -fo Green
    }
}

#=============================================== new line ===============================================

#calculate local time offset using google's http headers as a baseline
$varServerTime=([DateTimeOffset]::Parse((Get-HTTPHeaders http://www.google.com | Where-Object {$_.Key -eq "Date"}).Value)).UtcDateTime
$varServerEpoch=[int64](($varServerTime)-(get-date "1/1/1970")).TotalSeconds

#get local time
$varLocalEpoch=[int64](([datetime]::UtcNow)-(get-date "1/1/1970")).TotalSeconds

#compare
[int]$varTimeOffset=$varServerEpoch - $varLocalEpoch
if ($varTimeOffset -lt 0) {$varTimeOffset=0-$varTimeOffset}

#get to printing
write-host "     Clock Accuracy Offset  " -NoNewline
if ($varTimeOffset -ge 900) {
    write-host ">15 Min Out" -NoNewline -fo Red
    $script:CSToolReport+="! FAILURE: Device time is incorrect by more than fifteen minutes."
    $script:CSToolReport+="           This will render the device unable to communicate via SSL, precluding the Agent from connecting."
} elseif ($varTimeOffset -ge 600) {
    write-host ">10 Min Out" -NoNewline -fo Red
    $script:CSToolReport+="! FAILURE: Device time is incorrect by more than ten minutes."
    $script:CSToolReport+="           This will render the device unable to communicate via SSL, precluding the Agent from connecting."
} elseif ($varTimeOffset -ge 121) {
    write-host " >2 Min Out" -NoNewline -fo Yellow
    $script:CSToolReport+="! WARNING: Device time is incorrect by two to ten minutes."
    $script:CSToolReport+="           A device with inaccurate time may be unable to communicate via SSL, precluding the Agent from connecting."
} elseif ($varTimeOffset -le 120) {
    write-host "   Accurate" -NoNewline -fo Green
    $script:CSToolReport+="+ SUCCESS: Device time is accurate within two minutes. The device and the Agent should be able to communicate via secure channels."
}

write-host "   ||   " -fo DarkGray -nonewline

#counterproductive agent policy
write-host "Agent Policy Settings     " -NoNewline

if (!$CSAdmin) {
    write-host "No Admin" -fo Red
    $script:CSToolReport+=": UNKNOWN: Tool was unable to check for a counterproductive Agent Policy because it was not run with Administrator-level access."
} else {
    if (($arrXMLFiles | measure-object).count -eq 0) {
        write-host "  Absent" -fo Red
        $script:CSToolReport+="! FAILURE: No Policy data was present. Consider re-installing the Agent."
    } else {
        try {
            $arrXMLFiles | ? {$_} | % {
                [xml]$CSSystemXML=Get-Content "$_"
                foreach ($CSPolicySetting in ('PolicyEnableIncomingJobs','PolicyEnableIncomingSupport','PolicyEnableAudits','PolicyTrayVisible')) {
                    $CSSystemXML_Setting=($CSSystemXML.Configuration.userSettings.'CentraStage.Cag.Core.Settings'.setting | where-object {$_.Name -match "$CSPolicySetting" }).value
                    if ($CSSystemXML_Setting -eq 'false') {
                        $script:CSToolReport+="- CAUTION: Setting `"$CSPolicySetting`" is disabled via an Agent Policy. Ensure this was a deliberate action."
                        $CSPolicyAdvisories++
                    }

                }
            }
        } catch {
            $CSPolicyAdvisories++
            $script:CSToolReport+="! FAILURE: The user.config file in $env:SystemRoot\System32\config\systemProfile\appData\Local\CentraStage\{latest}\{latest} appears to be corrupt."
            $script:CSToolReport+="           Consider reinstalling the Agent."
        }

        if ($CSPolicyAdvisories -ge 1) {
            write-host "Advisory" -fo Red
        } else {
            write-host "No Issue" -fo Green
            $script:CSToolReport+="+ SUCCESS: There are no counterproductive Agent Policies disabling Audits, Support or Jobs targeting this system."
        }
    }
}

#=============================================== new line ===============================================

#web port ok
write-host "     Web Port Check              " -NoNewline
if (test-path "$varProg32\CentraStage\log.txt") {
    if ($(get-content -LiteralPath "$varProg32\CentraStage\log.txt") | select-string -Pattern 'web port ok' | Select-Object -last 1 | select-string -pattern 'false' -quiet) {
        write-host "Failed" -fo Red -NoNewline
        $script:CSToolReport+="! FAILURE: The Agent is reporting that its Web Port check is failing, meaning it cannot connect fully to the platform."
        $script:CSToolReport+="           This will cause monitors not to report data, alongside other performance issues."
        $script:CSToolReport+="           Please check that Agent connections are whitelisted properly. You are strongly advised to inform the Support team of this notice."
    } else {
        write-host "   OK!" -fo Green -NoNewline
        $script:CSToolReport+="+ SUCCESS: The Agent is reporting that it can connect fully to the platform."
    }
} else {
    write-host "Absent" -fo Red -NoNewline
    $script:CSToolReport+="! FAILURE: The Agent log is not present. Consider re-installing the Agent."
}

write-host "   ||   " -fo DarkGray -nonewline

#monitoring log
write-host "Monitoring Log" -NoNewline
if (test-path "$env:ProgramData\CentraStage\AEMAgent\DataLog\aemagent.log") {
    if ((Get-ChildItem -Path "$env:ProgramData\CentraStage\AEMAgent\DataLog\aemagent.log").LastWriteTime.Date -eq (Get-Date).Date) {
        write-host "                 OK!" -fo Green
        $script:CSToolReport+="+ SUCCESS: The Monitoring Agent's logging data is current."
    } else {
        write-host "             Stalled" -fo Red
        $script:CSToolReport+="! FAILURE: The Monitoring Agent appears to have stopped producing logging data. Please inspect AEMAgent.log manually."
    }
} else {
        write-host "              Absent" -fo Red
        $script:CSToolReport+="! FAILURE: The Monitoring Agent log is not present. Consider re-installing the Agent."
}

#=============================================== new line ===============================================

#monitoring data
write-host "     Monitoring Data" -NoNewline
if ($varOnDemand -eq 1) {
    if (test-path "$env:ProgramData\CentraStage\AEMAgent\Monitors.json") {
        if ((Get-ChildItem -Path "$env:ProgramData\CentraStage\AEMAgent\Monitors.json").LastWriteTime -gt (get-date).addHours(-24)) {
            write-host "                OK!" -NoNewline -fo Green
            $script:CSToolReport+="+ SUCCESS: The Monitoring Agent's monitor data JSON is being kept up-to-date."
        } else {
            Stop-Process -Name AEMAgent -Force -ErrorAction SilentlyContinue 2>&1>$null
            write-host "          Restarted" -NoNewline -fo Red
            $script:CSToolReport+="! FAILURE: The Monitoring Agent's monitor data JSON does not appear to be being kept up-to-date. Has the Agent been approved?"
            $script:CSToolReport+="           The Monitoring Agent process (AEMAgent.exe) has been killed. Please wait two minutes and then re-run this test."
        }
    } else {
            write-host "             Absent" -fo Red -NoNewline
            $script:CSToolReport+="! FAILURE: The Monitoring Agent's monitor data JSON is not present. Consider re-installing the Agent."
    }
} elseif ($varOnDemand -eq 2) {
    write-host "           OnDemand" -fo Yellow -NoNewline
    $script:CSToolReport+=": UNKNOWN: Monitoring Data checks skipped; the Agent is running as OnDemand, so no monitoring is occurring."
} else {
    write-host "           No Admin" -fo Red -NoNewline
    $script:CSToolReport+=": UNKNOWN: Monitoring Data checks skipped; as the script was not run as Administrator, the OnDemand check could not run."
}

write-host "   ||   " -fo DarkGray -nonewline

#alert queue
write-host "Alert Queue" -NoNewline
if (test-path "$env:ProgramData\CentraStage\AEMAgent\DataLog") {
    If (Get-ChildItem -Path $env:ProgramData\CentraStage\AEMAgent\DataLog\*.alert.dat | Where-Object {$_.LastWriteTime -le (Get-Date).AddMinutes(-5)}) {
        Stop-Process -Name AEMAgent -Force -ErrorAction SilentlyContinue 2>&1>$null
        write-host "              Restarted" -fo Red
        $script:CSToolReport+="! FAILURE: The Monitoring Agent appears to be having trouble despatching Alerts from its Alert Queue."
        $script:CSToolReport+="           The Monitoring Agent process (AEMAgent.exe) has been killed. Please wait two minutes and then re-run this test."
    } else {
        write-host "                    OK!" -fo Green
        $script:CSToolReport+="+ SUCCESS: The Monitoring Agent appears to be despatching alerts to the platform correctly."
    }
} else {
    write-host "                 Absent" -fo Red
    $script:CSToolReport+="! FAILURE: The Monitoring Agent's log repository is not present. Consider re-installing the Agent."
}

#=============================================== new line ===============================================

#PATH
write-host "     PATH                     " -NoNewline
try {
    if ((get-item "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment").GetValueKind("Path").value__ -ne 2) {
        if (!$CSAdmin) {
            $CSPathStatus=1
            $script:CSToolReport+="! FAILURE: The system's PATH variable is not set to REG_SZ_EXPAND (ExpandedString)."
            $script:CSToolReport+="           This will cause PowerShell Components to fail with 'cannot find powershell' errors."
            $script:CSToolReport+="           With Administrative privileges, the tool can attempt to fix this."
        } else {
            $CSPathStatus=2
            $script:CSToolReport+="! FAILURE: The system's PATH variable was not set to REG_SZ_EXPAND (ExpandedString)."
            $script:CSToolReport+="           This will cause PowerShell Components to fail with 'cannot find powershell' errors."
            $script:CSToolReport+="           The tool has attempted to recreate the value and fix the issue."
            #actually do it
            try {
                $CSPathContents=(get-itemproperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment").Path
                remove-itemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" -Name Path -force
                new-itemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" -Name Path -PropertyType ExpandString -Value "$CSPathContents" -Force | Out-Null
            } catch {
                $script:CSToolReport+="! FAILURE: Unable to gather PATH contents for some reason. Stopped instead of resetting with garbage data. Please scrutinise PATH in Registry,"
            }
        }
    } else {
        $CSPathStatus=4
        $script:CSToolReport+="+ SUCCESS: The system PATH is set to the right value type."
    }
} catch {
    $CSPathStatus=8
    $script:CSToolReport+="! FAILURE: The system has no PATH variable. This will cause issues running PowerShell scripts."
}

#PowerShell path
if (((Get-Process PowerShell -ea 0 | ? {$_.Id -eq $PID}).path | split-path) -ne "$env:SystemRoot\System32\WindowsPowerShell\v1.0") {
    $script:CSToolReport+="! FAILURE: PowerShell.exe is not located in $env:SystemRoot\System32\WindowsPowerShell\v1.0."
    $script:CSToolReport+="  This will stop Datto RMM from being able to run Components. Please correct this on the system."
    $CSPathStatus+=16
}

switch ($CSPathStatus) {
      1 {write-host "Corrupted" -fo Red    -NoNewline}
      2 {write-host "Recreated" -fo Yellow -NoNewline}
      4 {write-host "      OK!" -fo Green  -NoNewline}
      8 {write-host "   Absent" -fo Red    -NoNewline}
     17 {write-host "Corrupted" -fo Red    -NoNewline}
     18 {write-host "Corrupted" -fo Red    -NoNewline}
     20 {write-host "  PS PATH" -fo Red    -NoNewline}
     24 {write-host "   Issues" -fo Red    -NoNewline}
default {write-host "  Unknown" -fo Yellow -NoNewline}
}

write-host "   ||   " -fo DarkGray -NoNewline

#registry unicode :: anything outside of x00-xff, except for the trademark symbol, because that's ok somehow
write-host "Registry Validation" -NoNewline

('HKLM:\Software\Microsoft\Windows\Currentversion\Uninstall','HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall','HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall') | % {
    gci $_ | % {
        try {
            $varLoc=$_.name
            gp "Registry::$varLoc" -ea 0 | % {
                if ($_.PSPath -match '[^\x00-\xff\u2122]') {
                    #sound an alert if the registry key name contains invalid unicode
                    $script:CSToolReport+="! FAILURE: Registry key [$($_.PSPath -replace [regex]::Escape('Microsoft.PowerShell.Core\Registry::'))] name contains invalid Unicode"
                    $varRegBad=$true
                }
                
                if ($_.PSObject.Properties.Value -match '[^\x00-\xff\u2122]') {
                    #sound an alert if any values within the key contain data with invalid unicode
                    (gp $_.PSPath -ea 0).PSObject.Properties | ? {$_.name -notmatch '^PS'} | ? {$_.value -match '[^\x00-\xff\u2122]'} | % {
                        $script:CSToolReport+="! FAILURE: Registry value [$varLoc!$($_.name)] contains invalid Unicode [$($_.value)]"
                        $varRegBad=$true
                    }
                }
            }
        } catch {
            #if the key contains a value with malformed DWORD data, parsing will fail :: report the subkey name as access beyond this is denied
            $script:CSToolReport+="! FAILURE: A Registry value in [$varLoc] is invalid and should be removed."
            $varRegBad=$true
        }
    }
}

if ($varRegBad) {
    write-host "      Check Log" -fo Red
} else {
    write-host "            OK!" -fo Green
    $script:CSToolReport+="+ SUCCESS: Registry uninstall records. No unconventional Unicode found."
}

$script:CSToolReport+=": End of device checks"
$script:CSToolReport+=""

#------------------------------------------------ sub-section: post-check prompts

write-host "     ============================================================================" -fo DarkGray
write-host "     Press for NO               [" -nonewline
write-host "ENTER" -fo red -nonewline
write-host "]   " -nonewline
write-host "||" -fo DarkGray -nonewline
write-host "   Press for YES                  [" -nonewline
write-host "A" -nonewline -fo Red
write-host "]"
write-host `r

#display antivirus
if ($varServer) {
    write-host "- Antivirus check skipped: Cannot detect antivirus software on servers." -fo Yellow
} else {
    $arrAntivirus=@()
    try {
        gwmi -nameSpace root/SecurityCenter2 -Class AntivirusProduct -ea stop | % {$arrAntivirus+="$($_.displayName),"}
        if (($arrAntivirus | measure-object).count -eq 0) {
            write-host "- No Antivirus Software detected." -fo Red
            $script:CSToolReport+="! FAILURE: No Antivirus was detected. If one is installed, report this error; otherwise, install one!"
        } else {
            $varAntivirus=($arrAntivirus -as [string]).substring(0,$($arrantivirus -as [string]).length-1)
            write-host "- Antivirus Software Detected: $varAntivirus" -fo Yellow
            $script:CSToolReport+= ": Antivirus detected on device as $varAntivirus"
        }
    } catch {
        write-host "- WMI Issues prevented checking Antivirus software" -fo Red
        $script:CSToolReport+="! FAILURE: Suspected issues with the WMI stopped the script from ascertaining antivirus status"
        $varWMIIssues="Significant"
    }
}

#fix dotnet :: controlled by Datto RMM variable usrFixDotNet (default: false)
if ($varRunDotNet) {
    write-host "- Analyse/Repair .NET Framework (~5 Min)? [Datto RMM: Yes]" -fo Cyan
        (New-Object System.Net.WebClient).DownloadFile("https://download.microsoft.com/download/2/B/D/2BDE5459-2225-48B8-830C-AE19CAF038F1/NetFxRepairTool.exe", "$varScriptDir\NetFXRepairTool.exe")
        if (!$script:varResultDir) {
            makeFolder
        }

        Start-Process "$varScriptDir\NetFxRepairTool.exe" -ArgumentList "/q /n /l `"$script:varResultDir`""
        while (get-process FixDotNet,NetFXRepairTool -ea 0) {
            write-host "`r-- Waiting for .NET Repair Tool to finish [Current time is $(get-date -Format 'HH:mm.ss')]" -fo Cyan -NoNewline
            start-sleep -seconds 3
        }
        write-host "`r- DotNet Repair Tool has completed actions.                                         " -fo Green
        $script:CSToolReport+= ": MENTION: Microsoft .NET Repair tool was run on the Endpoint."
} else {
    write-host "- Skipping .NET Framework repair (usrFixDotNet not set)." -fo DarkGray
    $script:CSToolReport+=": .NET Framework repair skipped (usrFixDotNet=false)."
}

#attempt to repair WMI (october 2025; thanks to JK/datto labs)
if ($CSAdmin) {
    if ($varWMIIssues) {
        $varWMITest=start-process "winmgmt" -ArgumentList "/verifyrepository" -NoNewWindow -wait -PassThru -RedirectStandardOutput "NUL"
        if ($varWMITest.ExitCode -eq 0) {
            $varWMIIssues="Potential"
            $script:CSToolReport+="! NOTICE: Potential WMI issues were discovered"
        }
    } else {
        $varWMIIssues="No"
        $script:CSToolReport+="- No WMI issues were discovered"
    }

    #WMI repair runs automatically (non-interactive): skip if "No", otherwise attempt regardless
    write-host "- WMI status: $varWMIIssues issue(s) detected." -fo Cyan
    if ($varWMIIssues -ne 'No') {
        write-host "  Attempting WMI repair automatically..." -fo Cyan
            if ($varWMIIssues -eq 'Significant') {
                $script:CSToolReport+="! NOTICE: Significant WMI issues were discovered"
                #salvage WMI
                $script:CSToolReport+="-------------------------------------"
                $script:CSToolReport+=& winmgmt /salvagerepository
                $script:CSToolReport+="-------------------------------------"
            }

            #reregister MOFs
            if (!(test-path "$env:windir\System32\wbem")) {
                $script:CSToolReport+="! FAILURE: $env:windir\System32\WBEM is absent. The WMI will not function."
                write-host "! ERROR: WBEM Folder is absent. This device is beyond repair by this script." -fo Red
            } else {
                if ((gci "$env:windir\System32\wbem\*.mof" -ea 0).count -eq 0) {
                    $script:CSToolReport+="! FAILURE: $env:windir\System32\WBEM contains no MOF files. The WMI will not function."
                    write-host "! ERROR: WBEM Folder contains no MOF files. This device is beyond repair by this script." -fo Red
                } else {
                    #iterate through MOF files and recompile them
                    [int]$varMOFErrors=0
                    $varWMISpam=@()
                    gci "$env:windir\System32\wbem\*.mof" -ea 0 | ? {$_} | % {
                        $varWMISpam+=& mofcomp.exe $_.FullName
                        if ($LASTEXITCODE -ne 0) {
                            $script:CSToolReport+="! FAILURE: [$($_.FullName)] failed MOF compilation. This indicates an issue with this file which is causing WMI problems."
                            $varMOFErrors++
                        }
                    }
                    #put all the useful data from mofcomp into the output log
                    $script:CSToolReport+="-------------------------------------"
                    $varWMISpam | ? {$_ -notmatch 'Microsoft'} | % {
                        $script:CSToolReport+=$_
                        if ($_ -match '\!$') {
                            $script:CSToolReport+="---"
                        }
                    }
                    $script:CSToolReport+="-------------------------------------"

                    if ($varMOFErrors -eq 0) {
                        $script:CSToolReport+="+ SUCCESS: Attempts to repair WMI appear to have been successful."
                        write-host "- OK: WMI repair has completed successfully."
                    } else {
                        $script:CSToolReport+="! FAILURE: Attempts to repair WMI appear to have been unsuccessful."
                        write-host "! NOTICE: Attempts to repair WMI may not have been successful. Please check output log." -fo Yellow
                    }
                }
            }
    } else {
        write-host "- WMI is healthy; no repair needed (skipped)." -fo Green
        $script:CSToolReport+="- WMI repair skipped (no issues detected)."
    }
} else {
    write-host ": Cannot check or repair WMI (No admin access)"
    $script:CSToolReport+="- Unable to check-over or repair WMI; Admin access was not granted"
}

#certificate check (CHECK ONLY :: this tool reports problems but NEVER installs or modifies any certificate)
write-host "- Checking machine root certificates (check-only; nothing will be installed)..." -fo Cyan
try {
    $varRoots=Get-ChildItem Cert:\LocalMachine\Root -ea Stop
    $varRootCount=@($varRoots).Count
    write-host "  Trusted root certificates present: $varRootCount"
    $script:CSToolReport+=": Trusted root certificates present: $varRootCount"

    #warn on EXPIRED root certificates (not removed - reported only)
    $varExpiredRoots=@($varRoots | ? {$_.NotAfter -lt (Get-Date)})
    if ($varExpiredRoots.Count -gt 0) {
        write-host "! WARNING: $($varExpiredRoots.Count) trusted root certificate(s) are EXPIRED:" -fo Yellow
        $script:CSToolReport+="! WARNING: $($varExpiredRoots.Count) expired root certificate(s) detected (not removed):"
        $varExpiredRoots | % {
            write-host "    - $($_.Subject)  (expired $($_.NotAfter.ToString('yyyy-MM-dd')))" -fo Yellow
            $script:CSToolReport+="           $($_.Subject) [expired $($_.NotAfter)]"
        }
    } else {
        write-host "  No expired root certificates detected." -fo Green
        $script:CSToolReport+="+ No expired root certificates detected."
    }

    #warn on roots expiring within the next 30 days
    $varSoonRoots=@($varRoots | ? {$_.NotAfter -ge (Get-Date) -and $_.NotAfter -lt (Get-Date).AddDays(30)})
    if ($varSoonRoots.Count -gt 0) {
        write-host "! NOTICE: $($varSoonRoots.Count) root certificate(s) will expire within 30 days." -fo Yellow
        $script:CSToolReport+="! NOTICE: $($varSoonRoots.Count) root certificate(s) expire within 30 days."
    }

    #check (without installing anything) that Windows' automatic root-update service is reachable
    if (makeHTTPRequest "http://ctldl.windowsupdate.com/msdownload/update/v3/static/trustedr/en/authrootstl.cab" 200) {
        write-host "  Windows automatic root-certificate update service is reachable." -fo Green
        $script:CSToolReport+="+ Windows automatic root update service (ctldl.windowsupdate.com) is reachable."
    } else {
        write-host "! WARNING: Windows root-certificate update service (ctldl.windowsupdate.com) is NOT reachable;" -fo Yellow
        write-host "           automatic root certificate updates may be failing on this device." -fo Yellow
        $script:CSToolReport+="! WARNING: ctldl.windowsupdate.com unreachable; automatic root certificate updates may be failing."
    }
} catch {
    write-host "! ERROR: Unable to read the root certificate store: $($_.Exception.Message)" -fo Red
    $script:CSToolReport+="! FAILURE: Could not read root certificate store: $($_.Exception.Message)"
}
write-host "  (No certificates were installed or modified.)" -fo DarkGray

#closeout
write-host `r
write-host "Agent Health and Endpoint Checks completed." -fo Cyan
write-host "Collecting the tool's logging data..." -fo Cyan

# ==================================================================== PAGE THREE ===================================================================

write-host "Page 3: Data"
if ($CSAdmin) {
    write-host "Tool is being run as an Administrator    " -fo Cyan
} else {
    write-host "Tool is not being run as an Administrator" -fo Red
}
write-host "============================="
write-host "                               -== Data Collection ==-" -fo Green
write-host "`r"

#------------------------------------------------ sub-section: collecting log data (Datto RMM: copy to dattoATC, no 7-zip / no archiving)

#everything is written under the Datto RMM output directory created at the top of the script
$varCollectDir="$CSATCDir\AHC-$env:computername-$(get-date -f yyyyMMdd-HHmmss)"

if ($varCollectLogs) {
    if (!$CSAdmin) {
        write-host "- Copying available Agent log files (Operational files need Admin and will be skipped)." -fo Yellow
    } else {
        write-host "- Copying all Agent logging and Operational files to $varCollectDir" -fo Cyan
    }

    try {
        #make directories
        new-item "$varCollectDir\AgentLogs\Config"    -type directory -Force | out-null
        new-item "$varCollectDir\AgentLogs\AppData"   -type directory -Force | out-null
        new-item "$varCollectDir\AgentLogs\ProgFiles" -type directory -Force | out-null

        #config 1
        Copy-Item -Path "C:\Windows\System32\config\systemprofile\AppData\Local\CentraStage" -Recurse -Destination "$varCollectDir\AgentLogs\Config" -ea SilentlyContinue
        if (test-path "C:\Windows\SysWOW64\config\systemprofile\AppData\Local\CentraStage" -ea 0) {
            new-item "$varCollectDir\AgentLogs\Config64" -type directory -Force | out-null
            Copy-Item -Path "C:\Windows\SysWOW64\config\systemprofile\AppData\Local\CentraStage" -Recurse -Destination "$varCollectDir\AgentLogs\Config64" -ea SilentlyContinue
        }

        #config 2 :: get ALL programdata directories
        gci "$env:ProgramData\CentraStage*" | ? {$_.PSIsContainer} | % {
            $varName=$_.name
            new-item "$varCollectDir\AgentLogs\AppData\$varName" -type directory -Force | out-null
            gci $_ -Recurse | ? {$_.name -match '\.(xml|log|txt|config|json|dat)$'} | Copy-Item -Destination "$varCollectDir\AgentLogs\AppData\$varName" -Container -ErrorAction SilentlyContinue
        }

        #program files
        Get-ChildItem -Path "$varProg32\Centrastage" -Recurse -ea 0 | ? { $_.Name -match "^log\." } | Copy-Item -Destination "$varCollectDir\AgentLogs\ProgFiles" -ea SilentlyContinue

        write-host "- Agent log/operational files copied to $varCollectDir\AgentLogs" -fo Green
        $script:CSToolReport+="+ SUCCESS: Agent log files copied to $varCollectDir\AgentLogs"
    } catch {
        write-host "! ERROR: A problem occurred while copying log files: $($_.Exception.Message)" -fo Red
        $script:CSToolReport+="! FAILURE: Error copying log files: $($_.Exception.Message)"
    }
} else {
    write-host "- Log file collection skipped (usrCollectLogs=false)." -fo DarkGray
    $script:CSToolReport+=": Log file collection skipped (usrCollectLogs=false)."
}

#------------------------------------------------ sub-section: write report + finish

write-host `r

#conclude the verbose log
$script:CSToolReport+= ": Tool finished actions at $(Get-Date)."

#tally failures so the Quick Job result clearly reflects any problems
$varFailures=@($script:CSToolReport | ? {$_ -match '^\s*!\s*FAILURE'})
$varFailCount=$varFailures.count

#save the verbose report to the Datto RMM output directory (and into the collection dir if present)
$varReportName="AHC-$env:computername-Report-$(get-date -f yyyyMMdd-HHmmss).log"
$varReportPath="$CSATCDir\$varReportName"
try {
    $script:CSToolReport | Set-Content -Path $varReportPath -Encoding UTF8 -ea Stop
    if ($varCollectLogs -and (test-path $varCollectDir)) {
        Copy-Item -Path $varReportPath -Destination "$varCollectDir\$varReportName" -ea SilentlyContinue
    }
    write-host "- Report file written to $varReportPath" -fo Green
} catch {
    write-host "! ERROR: Could not write report file: $($_.Exception.Message)" -fo Red
}

#print the full verbose report so it appears in the console output (and therefore the saved transcript)
write-host "`r"
write-host "============================ FULL HEALTH-CHECK REPORT ============================" -fo Cyan
$script:CSToolReport | % { write-host $_ }
write-host "=================================================================================" -fo Cyan

#surface failures explicitly at the end so they are easy to spot
write-host "`r"
if ($varFailCount -gt 0) {
    write-host "! $varFailCount failure(s) were recorded during this run:" -fo Red
    $varFailures | % { write-host "    $_" -fo Red }
} else {
    write-host "+ No failures were recorded during this run." -fo Green
}

write-host "`r"
write-host "                               -== Scan Completed! ==-" -fo Green
write-host "All output has been saved under $CSATCDir" -fo Cyan
if ($CSTranscriptOn) {write-host "  Full console log : $CSTranscript" -fo Cyan}
write-host "  Report file      : $varReportPath" -fo Cyan

#stop the transcript (captures the full console output for PowerShell 5.x hosts)
if ($CSTranscriptOn) {
    try {Stop-Transcript | out-null} catch {}
}
pause
#exit code reflects health (0 = clean, 1 = failures recorded) so any wrapper/automation can flag problems
if ($varFailCount -gt 0) { 
    exit 1
} else {
    exit 0
}