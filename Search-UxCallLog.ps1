<#
    .SYNOPSIS

    This is a tool to search through Sonus/Ribbon SBC call logs and display associsated routing information

    .DESCRIPTION

    Created by James Arber. www.UcMadScientist.com
    
    .NOTES

    Version                : 1.0
    Date                   : 20/12/2021 #todo
    Author                 : James Arber
    Header stolen from     : Greig Sheridan who stole it from Pat Richard's amazing "Get-CsConnections.ps1"


    :v1.0: Initial Release

    Disclaimer: Whilst I take considerable effort to ensure this script is error free and wont harm your enviroment.
    I have no way to test every possible senario it may be used in. I provide these scripts free
    to the Lync and Skype4B community AS IS without any warranty on it's appropriateness for use in
    your environment. I disclaim all implied warranties including,
    without limitation, any implied warranties of merchantability or of fitness for a particular
    purpose. The entire risk arising out of the use or performance of the sample scripts and
    documentation remains with you. In no event shall I be liable for any damages whatsoever
    (including, without limitation, damages for loss of business profits, business interruption,
    loss of business information, or other pecuniary loss) arising out of the use of or inability
    to use the script or documentation.

    Acknowledgements 	
    : Testing and Advice
    Greig Sheridan https://greiginsydney.com/about/ @greiginsydney

    : Auto Update Code
    Pat Richard https://ucunleashed.com @patrichard

    : Proxy Detection
    Michel de Rooij	http://eightwone.com

    .LINK
    https://www.UcMadScientist.com/preparing-for-teams-export-your-on-prem-lis-data-for-cqd/

    .KNOWN ISSUES
    Check https://github.com/Atreidae/Export-LisDataForCQD/issues/

    .EXAMPLE
    Exports current LIS data as a CQD compliant CSV in the current folder.
    PS C:\> Export-LisDataForCQD.ps1

#>

[CmdletBinding(DefaultParametersetName = 'Common')]
param
(
  [switch]$SkipUpdateCheck,
  [String]$script:LogFileLocation = $null
)

If (!$script:LogFileLocation) 
{
  $script:LogFileLocation = $PSCommandPath -replace '.ps1', '.log'
}

#region config
[Net.ServicePointManager]::SecurityProtocol = 'tls12, tls11, tls'
$StartTime                          = Get-Date
$VerbosePreference                  = 'SilentlyContinue' #TODO
[String]$ScriptVersion              = '0.1.0'
[string]$GithubRepo                 = 'Search-UxCallLog'
[string]$GithubBranch               = 'master' #todo
[string]$BlogPost                   = 'https://www.UcMadScientist.com/preparing-for-teams-export-your-on-prem-lis-data-for-cqd/' #todo


Function Write-UcmLog {
  <#
      .SYNOPSIS
      Function to output messages to the console based on their severity and create log files

      .DESCRIPTION
      It's a logger.

      .PARAMETER Message
      The message to write

      .PARAMETER Path
      The location of the logfile.

      .PARAMETER Severity
      Sets the severity of the log message, Higher severities will call Write-Warning or Write-Error

      .PARAMETER Component
      Used to track the module or function that called "Write-Log" 

      .PARAMETER LogOnly
      Forces Write-Log to not display anything to the user

      .EXAMPLE
      Write-Log -Message 'This is a log message' -Severity 3 -component 'Example Component'
      Writes a log file message and displays a warning to the user

      .REQUIRED FUNCTIONS
      None

      .LINK
      http://www.UcMadScientist.com
      https://github.com/Atreidae/UcmPsTools

      .INPUTS
      This function does not accept pipelined input

      .OUTPUTS
      This function does not create pipelined output

      .NOTES
      Version:		1.2
      Date:			18/11/2021

      .VERSION HISTORY
      1.1: Updated to "Ucm" naming convention
      Better inline documentation

      1.1: Bug Fix
      Resolved an issue where large logfiles would attempt to rename themselves to the same name causing errors when logs grew above 10MB

      1.0: Initial Public Release
  #>
  [CmdletBinding()]
  PARAM
  (
    [String]$Message,
    [String]$Path = $Script:LogFileLocation,
    [int]$Severity = 1,
    [string]$Component = 'Default',
    [switch]$LogOnly
  )
  $function = 'Write-UcmLog'
  $Date = Get-Date -Format 'HH:mm:ss'
  $Date2 = Get-Date -Format 'MM-dd-yyyy'
  $MaxLogFileSizeMB = 10

  #Check to see if the file exists
  If(Test-Path -Path $Path)
  {
    if(((Get-ChildItem -Path $Path).length/1MB) -gt $MaxLogFileSizeMB) # Check the size of the log file and archive if over the limit.
    {
      $ArchLogfile = $Path.replace('.log', "_$(Get-Date -Format dd-MM-yyy_hh-mm-ss).lo_")
      Rename-Item -Path $Path -NewName $ArchLogfile
    }
  }

  #Write to the log file
  "$env:ComputerName date=$([char]34)$Date2$([char]34) time=$([char]34)$Date$([char]34) component=$([char]34)$component$([char]34) type=$([char]34)$severity$([char]34) Message=$([char]34)$Message$([char]34)"| Out-File -FilePath $Path -Append -NoClobber -Encoding default

  #If LogOnly is not set, output the log entry to the screen
  If (!$LogOnly) 
  {
    #If the log entry is just Verbose (1), output it to write-verbose
    if ($severity -eq 1) 
    {
      "$Message"| Write-verbose
    }
    #If the log entry is just informational (2), output it to write-host
    if ($severity -eq 2) 
    {
      "INFO: $Message"| Write-Host -ForegroundColor Green
    }
    #If the log entry has a severity of 3 assume its a warning and write it to write-warning
    if ($severity -eq 3) 
    {
      "$Date $Message"| Write-Warning
    }
    #If the log entry has a severity of 4 or higher, assume its an error and display an error message (Note, critical errors are caught by throw statements so may not appear here)
    if ($severity -ge 4) 
    {
      "$Date $Message"| Write-Error
    }
  }
}

Function Get-IEProxy
{
  $function = 'Get-IEProxy'
  Write-Log -component $function -Message 'Checking for IE First Run' -severity 1
  if ((Get-Item -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings').Property -NotContains 'ProxyEnable')
  {
    $null = New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name ProxyEnable -Value 0
  }
  

  Write-Log -component $function -Message 'Checking for Proxy' -severity 1
  If ( (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings').ProxyEnable -ne 0)
  {
    $proxies = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings').proxyServer
    if ($proxies) 
    {
      if ($proxies -ilike '*=*')
      {
        return $proxies -replace '=', '://' -split (';') | Select-Object -First 1
      }
      
      Else 
      {
        return ('http://{0}' -f $proxies)
      }
    }
    
    Else 
    {
      return $null
    }
  }
  Else 
  {
    return $null
  }
}

Function Get-ScriptUpdate 
{
  $function = 'Get-ScriptUpdate'
  Write-Log -component $function -Message 'Checking for Script Update' -severity 1
  Write-Log -component $function -Message 'Checking for Proxy' -severity 1
  $ProxyURL = Get-IEProxy
  
  If ($ProxyURL)
  
  {
    Write-Log -component $function -Message "Using proxy address $ProxyURL" -severity 1
  }
  
  Else
  {
    Write-Log -component $function -Message 'No proxy setting detected, using direct connection' -severity 1
  }

  Write-Log -component $function -Message "Polling https://raw.githubusercontent.com/atreidae/$GithubRepo/$GithubBranch/version" -severity 1
  $GitHubScriptVersion = Invoke-WebRequest -Uri "https://raw.githubusercontent.com/atreidae/$GithubRepo/$GithubBranch/version" -TimeoutSec 10 -Proxy $ProxyURL -UseBasicParsing
  
  If ($GitHubScriptVersion.Content.length -eq 0) 
  {
    #Empty data, throw an error
    Write-Log -component $function -Message 'Error checking for new version. You can check manually using the url below' -severity 3
    Write-Log -component $function -Message $BlogPost -severity 3 
    Write-Log -component $function -Message 'Pausing for 5 seconds' -severity 1
    Start-Sleep -Seconds 5
  }
  else
  {
    #Process the returned data
    #Symver support!
    [string]$Symver = ($GitHubScriptVersion.Content)
    $splitgitver = $Symver.split('.') 
    $splitver = $ScriptVersion.split('.')
    $needsupdate = $false
    #Check for Major version

    if ([single]$splitgitver[0] -gt [single]$splitver[0])
    {
      $Needupdate = $true
      #New Major Build available, #Prompt user to download
      Write-Log -component $function -Message 'New Major Version Available' -severity 3
      $title = 'Update Available'
      $Message = 'a major update to this script is available, did you want to download it?'
    }

    if (([single]$splitgitver[1] -gt [single]$splitver[1]) -and ([single]$splitgitver[0] -eq [single]$splitver[0]))
    {
      $Needupdate = $true
      #New Major Build available, #Prompt user to download
      Write-Log -component $function -Message 'New Minor Version Available' -severity 3
      $title = 'Update Available'
      $Message = 'a minor update to this script is available, did you want to download it?'
    }

    if (([single]$splitgitver[2] -gt [single]$splitver[2]) -and ([single]$splitgitver[1] -gt [single]$splitver[1]) -and ([single]$splitgitver[0] -eq [single]$splitver[0]))
    {
      $Needupdate = $true
      #New Major Build available, #Prompt user to download
      Write-Log -component $function -Message 'New Bugfix Available' -severity 3
      $title = 'Update Available'
      $Message = 'a bugfix update to this script is available, did you want to download it?'
    }

    If($Needupdate)
    {
      $yes = New-Object -TypeName System.Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes', `
      'Update the installed PowerShell Module'

      $no = New-Object -TypeName System.Management.Automation.Host.ChoiceDescription -ArgumentList '&No', `
      'No thanks.'

      $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)

      $result = $host.ui.PromptForChoice($title, $Message, $options, 0) 

      switch ($result)
      {
        0 
        {
          #User said yes
          Write-Log -component $function -Message 'User opted to download update' -severity 1
          #start $BlogPost
          Repair-BsInstalledModules -ModuleName 'BounShell' -Operation 'Update'
          Write-Log -component $function -Message 'Exiting Script' -severity 3
          Pause
          exit
        }
        #User said no
        1 
        {
          Write-Log -component $function -Message 'User opted to skip update' -severity 1
        }
      }
    }
    
    #We already have the lastest version
    Else
    {
      Write-Log -component $function -Message 'Script is upto date' -severity 1
    }
  }
}

Write-Log -Message "$GithubRepo.ps1 Version $ScriptVersion" -severity 2


#Get Proxy Details
$ProxyURL = Get-IEProxy
If ($ProxyURL) 
{
  Write-Log -Message "Using proxy address $ProxyURL" -severity 2
}
Else 
{
  Write-Log -Message 'No proxy setting detected, using direct connection' -severity 1
}

#Check for Script update
$SkipUpdateCheck = $true #todo
if ($SkipUpdateCheck -eq $false) 
{
  #Get-ScriptUpdate #todo
}

$function = "Read-Logs"
Write-Progress -Activity "Initial Import" -Status 'Importing Raw Log File'
Write-UcmLog -Message "Importing Log File" -Severity 1 -Component $function
$RawLogFile = (Get-Content ./webui.log -raw)


#Process data.

#Find all the calls that entered the SBC and split them into their own object

Write-Progress -Activity "Initial Import" -Status 'Locating Call Markers'
Write-UcmLog -Message "Locating Calls" -Severity 1 -Component $function


#method 1
#$CallLocations = [regex]::Matches($RawLogFile,'Handling initial invite.')

#Method 2
#$CallLocations = (Select-String -InputObject $RawLogFile -Pattern 'Handling initial invite.' -AllMatches -SimpleMatch)

#Method 3 (Return line numbers)
$CallLocations =  (Select-String -Path ./webui.log -Pattern 'Handling initial invite.')

Write-UcmLog -Message "Found $($CallLocations.count) Invites." -Severity 2 -Component $function

#Split the log file using the "Handling Initial Invite Marker (This should work for test calls, not just real calls)
$RawCalls = $RawLogFile -split 'sendToSipUser: Handling initial invite.' -notmatch '^$'


#Process each Call Object

$CurrentCallProgress = 0
$CurrentCallNum = 0

Foreach ($RawCall in $RawCalls)
{
 
 
  $CurrentCallProgress ++
  
  
  Write-Progress -Activity "Processing Calls" -Status "Locating Call $CurrentCallProgress of $($CallLocations.count) details"
    
  #Skip the first "call" object as it's just whats in the log before the first detected invite
    
  If ($CurrentCallNum -eq 0)
  {
    Write-UcmLog -Message "Skipping Prelogs" -Severity 1 -Component $function
  }
  #ElseIF ($CurrentCallNum -eq 1) #Todo, only processing one call at the moment
  Else
  {
    $CurrentCall = [PSCustomObject]@{
      'CallID' = 'Unknown'
      'CallTime' = 'Unknown'
      'OriginalCallingNumber' = 'Unknown'
      'OriginalCalledNumber' = 'Unknown'
      'TranslatedCallingNumber' = 'Unknown'
      'TranslatedCalledNumber' = 'Unknown'
      'RouteTable' = 'Unknown'
      'TransTableMatches' = @()
      'FinalTranslationRule' = 'Unknown'
      'AllTransMatches' = 'Unknown'
    }
    
    
    #Greig Asked for time of invite, that goes here
  
  
    #Calculate the LineNumber of the invite
    $InviteLine = ($CallLocations[($CurrentCallNum -1)].LineNumber)
    Write-UcmLog -Message "Found an Invite on line $InviteLine" -Severity 1 -Component $function
    
    #Call ID
    $CallID = ([regex]::Matches($RawCall,'\]\[CID:(\d*)\]').groups[1].value)
    Write-UcmLog -Message "# Call ID $CallID" -Severity 1 -Component $function
    $CurrentCall.CallID = $callID
    
    #Find the Called Details
    $OriginalCalledNumber = ([regex]::Matches($RawCall,'Received MSG_CC_SETUP message with called#\[(.*)\]').groups[1].value)
    Write-UcmLog -Message "Original Called Number (Digits Dialled) $OriginalCalledNumber" -Severity 1 -Component $function
    $CurrentCall.OriginalCalledNumber = $OriginalCalledNumber

    #Find the Calling Details
    $OriginalCallingNumber = ([regex]::Matches($RawCall,'From: .* <sip:(.*)@').groups[1].value)
    Write-UcmLog -Message "Original Calling Number (Caller ID) $OriginalCallingNumber" -Severity 1 -Component $function
    $CurrentCall.OriginalCallingNumber = $OriginalCallingNumber

    #Find the input Route Table
    $RouteTable = ([regex]::Matches($RawCall,'Using table (.*) to route call').groups[1].value)
    Write-UcmLog -Message "Call using Route Table $RouteTable" -Severity 1 -Component $function
    $CurrentCall.RouteTable = $RouteTable
    
    # Find TransTable Match #ToDo
    $TransTableMatch = ([regex]::Matches($RawCall,'Transformation table(.*) is a SUCCESS').groups[1].value)

    Write-UcmLog -Message "Call Matched Transformation Table $TransTableMatch" -Severity 1 -Component $function
  
    Write-UcmLog -Message "## Call Matched Transformation Table Entries" -Severity 1 -Component $function
    #Matched Trans Entries
    #$TransTableTests = (Select-String -InputObject $RawCall -Pattern 'Rule (.*) being tested for selection.' -AllMatches)
    ForEach($TransTableTestMatch in ($TransTableTests.Matches))   #This is fucked todo
    {
      #$TransTableTestMatch.groups[1].value
      Write-UcmLog -Message "$($TransTableTestMatch.groups[1].value)" -Severity 1 -Component $function
    }
 
    #Skipped Trans Entries
    Write-UcmLog -Message "## Disabled Translation Entries Tested" -Severity 1 -Component $function
    $SkippedTransTableTests = (Select-String -InputObject $RawCall -Pattern 'Rule (.*) skipped due to transformation entry disabled.' -AllMatches)
    ForEach($SkippedTransTableTest in ($SkippedTransTableTests.Matches))   #This is fucked todo
    {
      #$SkippedTransTableTest.groups[1].value
      Write-UcmLog -Message "$($SkippedTransTableTest.groups[1].value)" -Severity 1 -Component $function
    }
 
    #Failed Trans Entries
    Write-UcmLog -Message "## Failed Translation Entries Tested" -Severity 1 -Component $function
    $FailedTransTableTests = (Select-String -InputObject $RawCall -Pattern 'Transformation table\((.*)\) is a FAILURE' -AllMatches)
    ForEach($FailedTransTableTest in ($FailedTransTableTests.Matches))   #This is fucked todo
    {
      #$FailedTransTableTest.groups[1].value
      Write-UcmLog -Message "$($FailedTransTableTest.groups[1].value)" -Severity 1 -Component $function
    }
    #Find all Trans Table Tests 
      
    #$TransTableTests = ([regex]::Matches($RawCall,'Rule (.*) being tested for selection').groups.value) #Need to get this to return all calls
  
    #Return all tested rules, disabled for now
    #$TransTableTests = (Select-String -InputObject $RawCall -Pattern 'Rule (.*) being tested for selection.' -AllMatches)
    
    
    #Find the Outbound Invite to grab the translated numbers
    #Split the raw call using the invite
    $RawInvites = $RawCall -split 'INVITE sip:' -notmatch '^$'
    
    #Set a flag to ensure we actually find the relevant invite
    $InviteFound = $False
    
    ForEach ($rawInvite in $RawInvites) 
    {
      #Check the invite matches the known CallID
      #Check we actually have an invite
      if ([regex]::Matches($rawInvite,'cid=(\d*)').count -ne 0)
      {
        #Great, now lets get that Invite's CID and see if it matches the call we care about
        $InviteCID = ([regex]::Matches($rawInvite,'cid=(\d*)').groups[1].value) 
        Write-UcmLog -Message "Found Invite with the CID of $inviteCID" -Severity 1 -Component $function
        
        #Found the Invite we care about, lets grab the translated numbers (because they arent logged for some god damn reason)
        If ($inviteCID -eq $CallID)
        {
          Write-UcmLog -Message "Invite Matches Current Call" -Severity 1 -Component $function
          $InviteFound = $true
          Write-UcmLog -Message "## Translated Numbers" -Severity 1 -Component $function
          
          #Note, we arent looking for the "Invite SIP:" as we used that to split the content
          $TranslatedCallingNumber = ([regex]::Matches($rawInvite,'(.*)@').groups[1].value)
          $TranslatedCalledNumber = ([regex]::Matches($rawInvite,'From: .* <sip:(.*)@').groups[1].value)
          Write-UcmLog -Message "Translated Called Number $TranslatedCalledNumber" -Severity 1 -Component $function
          Write-UcmLog -Message "Translated Calling Number $TranslatedCallingNumber" -Severity 1 -Component $function   
          $CurrentCall.TranslatedCallingNumber = $TranslatedCallingNumber
          $CurrentCall.TranslatedCalledNumber = $TranslatedCalledNumber
        }
        
        Else
        {
          Write-UcmLog -Message "Invite Doesnt Match Current Call, ignoring" -Severity 1 -Component $function
        }
      }
      
      #Handle any split objects before the first invite
      Else
      {
        Write-UcmLog -Message "RegEx result not an invite, ignoring" -Severity 1 -Component $function
      }
    }
    
    If ($InviteFound)
    {
      Write-UcmLog -Message "Found the Invite for $callID" -Severity 1 -Component $function
      
      
    }
    Else
     {
      Write-UcmLog -Message "Could not locate invite for $callID" -Severity 3 -Component $function
    }
    
    
    

    
  }
  $CurrentCallNum ++
  $CurrentCall
}





<#

    Route table
    Using table NML: From Registrar (7) to route call.

    #Failed Trans Table
    Rule NML: Route calls to NMLCAUX02 (7.1(32)) being tested for selection.
    (Transformation Entry Tests)
    Transformation table(NML: Route to NMLCAUX02:64) is a FAILURE



    #Sucsess Trans Table
    Rule Internal 6392 to Core (7.12(19)) being tested for selection.
    (Transformation Entry Tests)
    Transformation table(NML: internal 6392:2) is a SUCCESS



#>









#End of a good call route.
#'SIP/2.0 100 Trying'


#call found, find its orginal numbers

#Original dialled number
#[30203][CID:42135] Requesting call route for route table 7, called# [1370]


#Route Table
#(callrouter.cpp:2378) - Using table NML: From Registrar (7) to route call.


#Now find all rules that match

#
#Transformation table(Analog to Telstra:4) is a SUCCESS
#RegEx 'Transformation table\((.*)\) is a SUCCESS'

#Find the final rule that matches
#Successful route request with entry NML: Analogue To Telstra (7.14(10))
#Successful route request with entry Internal 6392 to Core (7.12(19))