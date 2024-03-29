﻿<#
    .SYNOPSIS

    This is a tool to search through Sonus/Ribbon SBC call logs and display associated routing information

    .DESCRIPTION
    This tool does it's best to display call routes from Sonus/Ribbon UX logfiles in a friendly manner without needing tools like LX installed

    Why?
    I got so sick and tired of firing up LX every single time a call went "awry" when customers called only to find someone else had re-installed LX on their profile causing the installation to break on mine
    For people that only support a pair of SBC's maybe you can just run LX on your PC.. but for consultants, we have to get the files off the SBC.. then out of the customers environment and thats usualy a PITA. 
    Needless to say, even with LX you still need to read all the ROUTE entries by hand anyway.

    So I wrote this script to give everyone a simple way to see what rules calls are bouncing off to ease troubleshooting a bit.

    .PARAMETER InputFile
    The Logfile to check for call logs. Defaults to WebUI.log in the current directory.

    .PARAMETER OutboundSignalingGroups
    Used to find calls that were sent to a particular signalling group.
    Specify the signaling group number to filter down the list

    .PARAMETER ParseFolder
    If specified, Search-UxLogFile will ignore the InputFile parameter and instead will attempt to parse every *.log file in the current folder.
    Handy for checking a whole bunch of log files for a specific call when piped to some filtering or when using the OutboundSignalingGroups parameter.
    A word of warning, this can be slow and CPU intensive, dont run this on a FrontEnd Server!


    Created by James Arber. www.UcMadScientist.com
    
    .NOTES

    Version                : 0.3.0
    Date                   : 07/03/2023
    Author                 : James Arber
    Header stolen from     : Greig Sheridan who stole it from Pat Richard's amazing "Get-CsConnections.ps1"


    :v0.3: Beta Release
    - Added Code Signing Certificate (Thanks DigiCert)


    :v0.2: Beta Release
    - Added Cause Code Reroute Flag Property
    - Added Destination Signalling Group Property
    - Added Destination Signalling Group Filtering
    - Added Folder Parsing
    - Better Error checking for folders

    :v0.1: Beta Release

    Disclaimer: Whilst I take considerable effort to ensure this script is error free and wont harm your enviroment.
    I have no way to test every possible senario it may be used in. I provide these scripts free
    to the Skype4B and Teams community AS IS without any warranty on it's appropriateness for use in
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
    https://www.UcMadScientist.com/preparing-for-teams-export-your-on-prem-lis-data-for-cqd/ #todo

    .KNOWN ISSUES
    Large amounts of simultaneous calls can cause the script to get confused if invites are logged out of order
    Call Diversion Invites arent handled properly
    If the script presently cant find an appropriate call invite, it will export a text file of that call for later viewing
    Check https://github.com/Atreidae/Search-UxCallLog/issues/ for more
    Signalling Group matches dont search for the whole number (yet), so seaching for calls terminating on SG 1, will return calls on SG11, 12, 13 etc.

    .EXAMPLE
    Enumerates calls in WebUi.log and outputs each call to the pipeline
    PS C:\> Search-UxCallLog.ps1 -InputFile Webui.log

#>

[CmdletBinding(DefaultParametersetName = 'Common')]
param
(
  [switch]$SkipUpdateCheck,
  [switch]$ParseFolder,
  [String]$script:LogFileLocation = $null,
  [String]$InputFile = "./webui.log",
  [String]$OutboundSignallingGroups = ""
)

If (!$script:LogFileLocation) 
{
  $script:LogFileLocation = $PSCommandPath -replace '.ps1', '.log'
}

#region config
[Net.ServicePointManager]::SecurityProtocol = 'tls12, tls11, tls'
$StartTime                          = Get-Date
$VerbosePreference                  = 'SilentlyContinue' #TODO
[String]$ScriptVersion              = '0.2.2'
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
      Used to track the module or function that called "Write-UcmLog" 

      .PARAMETER LogOnly
      Forces Write-UcmLog to not display anything to the user

      .EXAMPLE
      Write-UcmLog -Message 'This is a log message' -Severity 3 -component 'Example Component'
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
  Write-UcmLog -component $function -Message 'Checking for IE First Run' -severity 1
  if ((Get-Item -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings').Property -NotContains 'ProxyEnable')
  {
    $null = New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name ProxyEnable -Value 0
  }
  

  Write-UcmLog -component $function -Message 'Checking for Proxy' -severity 1
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
  Write-UcmLog -component $function -Message 'Checking for Script Update' -severity 1
  Write-UcmLog -component $function -Message 'Checking for Proxy' -severity 1
  $ProxyURL = Get-IEProxy
  
  If ($ProxyURL)
  
  {
    Write-UcmLog -component $function -Message "Using proxy address $ProxyURL" -severity 1
  }
  
  Else
  {
    Write-UcmLog -component $function -Message 'No proxy setting detected, using direct connection' -severity 1
  }

  Write-UcmLog -component $function -Message "Polling https://raw.githubusercontent.com/atreidae/$GithubRepo/$GithubBranch/version" -severity 1
  $GitHubScriptVersion = Invoke-WebRequest -Uri "https://raw.githubusercontent.com/atreidae/$GithubRepo/$GithubBranch/version" -TimeoutSec 10 -Proxy $ProxyURL -UseBasicParsing
  
  If ($GitHubScriptVersion.Content.length -eq 0) 
  {
    #Empty data, throw an error
    Write-UcmLog -component $function -Message 'Error checking for new version. You can check manually using the url below' -severity 3
    Write-UcmLog -component $function -Message $BlogPost -severity 3 
    Write-UcmLog -component $function -Message 'Pausing for 5 seconds' -severity 1
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
      Write-UcmLog -component $function -Message 'New Major Version Available' -severity 3
      $title = 'Update Available'
      $Message = 'a major update to this script is available, did you want to download it?'
    }

    if (([single]$splitgitver[1] -gt [single]$splitver[1]) -and ([single]$splitgitver[0] -eq [single]$splitver[0]))
    {
      $Needupdate = $true
      #New Major Build available, #Prompt user to download
      Write-UcmLog -component $function -Message 'New Minor Version Available' -severity 3
      $title = 'Update Available'
      $Message = 'a minor update to this script is available, did you want to download it?'
    }

    if (([single]$splitgitver[2] -gt [single]$splitver[2]) -and ([single]$splitgitver[1] -gt [single]$splitver[1]) -and ([single]$splitgitver[0] -eq [single]$splitver[0]))
    {
      $Needupdate = $true
      #New Major Build available, #Prompt user to download
      Write-UcmLog -component $function -Message 'New Bugfix Available' -severity 3
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
          Write-UcmLog -component $function -Message 'User opted to download update' -severity 1
          #start $BlogPost
          Repair-BsInstalledModules -ModuleName 'BounShell' -Operation 'Update'
          Write-UcmLog -component $function -Message 'Exiting Script' -severity 3
          Pause
          exit
        }
        #User said no
        1 
        {
          Write-UcmLog -component $function -Message 'User opted to skip update' -severity 1
        }
      }
    }
    
    #We already have the lastest version
    Else
    {
      Write-UcmLog -component $function -Message 'Script is upto date' -severity 1
    }
  }
}

Write-UcmLog -Message "$GithubRepo.ps1 Version $ScriptVersion" -severity 2


#Get Proxy Details
$ProxyURL = Get-IEProxy
If ($ProxyURL) 
{
  Write-UcmLog -Message "Using proxy address $ProxyURL" -severity 2
}
Else 
{
  Write-UcmLog -Message 'No proxy setting detected, using direct connection' -severity 1
}

#Check for Script update
$SkipUpdateCheck = $true #todo
if ($SkipUpdateCheck -eq $false) 
{
  #Get-ScriptUpdate #todo
}

$function = "Read-Logs"
Write-Progress -Activity "Initial Import" -Status 'Importing Raw Log File'


If ($ParseFolder)
{
  #Import all the log files in the current folder and sort them by created date so calls bridging files line up
  $files = ((Get-ChildItem -Path "." -filter '*.log').FullName|Sort-Object -Property CreationTime)
  
  #Check for and provide feedback on no log files
  If ($files.count -eq 0)
  {
    Write-UcmLog -Message "No log files to import. Exiting..." -Severity 3 -Component $function
    Return  
  }
  Foreach ($file in $files)
  {
    $RawLogFile += (Get-Content $File -raw)
  }
}

Else
{ 
  #Import the logfile
  Write-UcmLog -Message "Importing Log File" -Severity 1 -Component $function
  $RawLogFile = (Get-Content $InputFile -raw)
}

#Process data.

#Find all the calls that entered the SBC and split them into their own object
$function = "Parse-Invites"
Write-Progress -Activity "Initial Import" -Status 'Locating Call Markers'
Write-UcmLog -Message "Locating Calls" -Severity 1 -Component $function


#method 1
#$CallLocations = [regex]::Matches($RawLogFile,'Handling initial invite.')

#Method 2
#$CallLocations = (Select-String -InputObject $RawLogFile -Pattern 'Handling initial invite.' -AllMatches -SimpleMatch)

#Method 3 (Return line numbers, doesnt like multi file)
#$CallLocations =  (Select-String -Path $inputfile -Pattern 'Handling initial invite.')

#Method 4 (Return line numbers)
$CallLocations =  (Select-String -InputObject $RawLogFile -Pattern 'Handling initial invite.' -AllMatches)
$TotalCalls = $CallLocations.matches.count

Write-UcmLog -Message "Found $TotalCalls Invites." -Severity 2 -Component $function

#Split the log file using the "Handling Initial Invite Marker (This should work for test calls, not just real calls)
$RawCalls = $RawLogFile -split 'sendToSipUser: Handling initial invite.' -notmatch '^$'

#Cleanup our lingering memory objects
Remove-Variable -name "RawLogFile"


#Process each Call Object
$function = "Call-ProcessLoop"
$CurrentCallProgress = 0
$CurrentCallNum = 0

Foreach ($RawCall in $RawCalls)
{
  #Skip the first "call" object as it's just whats in the log before the first detected invite
    
  If ($CurrentCallNum -eq 0)
  {
    Write-UcmLog -Message "Skipping Prelogs" -Severity 1 -Component $function
  }
  
  #Process the actual call
  Else 
  {
    $CurrentCallProgress ++
    Write-Progress -Activity "Processing Calls" -Status "Locating Call $CurrentCallProgress of $TotalCalls details"  -PercentComplete ((($CurrentCallProgress) / $TotalCalls) * 100)
    $CurrentCall = [PSCustomObject]@{
      'CallID' = 'Unknown'
      'CallTime' = 'Unknown'
      'InviteLineNumber' = 'Unknown'
      'OriginalCallingNumber' = 'Unknown'
      'OriginalCalledNumber' = 'Unknown'
      'TranslatedCallingNumber' = 'Unknown'
      'TranslatedCalledNumber' = 'Unknown'
      'RouteTable' = 'Unknown'
      'TransTableMatches' = @()
      'TransTableFailures' = @()
      'TransTableEntrySkips' = @()
      'FinalTranslationRule' = 'Unknown'
      'OutboundSignallingGroups' = 'Unknown'
      'CauseCodeReRoute' = 'No'
      'ReRouteMatch' = 'NA'
      #'RouteFound' = $False
    }

    #Setup for Progress Bars
    $ProgressSteps = 16
    $currentStep = 1
    
    
    #Find the Call ID
    Write-Progress -Activity "Step $currentStep/$ProgressSteps" -id 1 -Status "Call ID" -PercentComplete ((($currentStep) / $ProgressSteps) * 100) ;$currentStep ++
    $CallID = ([regex]::Matches($RawCall,'\]\[CID:(\d*)\]').groups[1].value)
    Write-UcmLog -Message "# Call ID $CallID" -Severity 1 -Component $function
    $CurrentCall.CallID = $callID
    
    #Greig Asked for time of invite, that goes here
    Write-Progress -Activity "Step $currentStep/$ProgressSteps" -id 1 -Status "Call Time" -PercentComplete ((($currentStep) / $ProgressSteps) * 100) ;$currentStep ++
    $CallTime = ([regex]::Matches($RawCall,'\[(.*),...\]').groups[1].value)
    Write-UcmLog -Message "# Call ID $CallID" -Severity 1 -Component $function
    $CurrentCall.CallTime = $CallTime
    
    #Calculate the LineNumber of the invite (buggy)
    Write-Progress -Activity "Step $currentStep/$ProgressSteps" -id 1 -Status "Call Line Number" -PercentComplete ((($currentStep) / $ProgressSteps) * 100) ;$currentStep ++
    $InviteLineNumber = ($CallLocations[($CurrentCallNum -1)].LineNumber)
    Write-UcmLog -Message "Found an Invite on line $InviteLineNumber" -Severity 1 -Component $function
    $CurrentCall.InviteLineNumber = $InviteLineNumber
    
    #Find the Called Number Details
    Write-Progress -Activity "Step $currentStep/$ProgressSteps" -id 1 -Status "Original Called Number" -PercentComplete ((($currentStep) / $ProgressSteps) * 100) ;$currentStep ++
    $OriginalCalledNumber = ([regex]::Matches($RawCall,'Received MSG_CC_SETUP message with called#\[(.*)\]').groups[1].value)
    Write-UcmLog -Message "Original Called Number (Digits Dialled) $OriginalCalledNumber" -Severity 1 -Component $function
    $CurrentCall.OriginalCalledNumber = $OriginalCalledNumber

    #Find the Calling Number Details
    Write-Progress -Activity "Step $currentStep/$ProgressSteps" -id 1 -Status "Original Calling Number" -PercentComplete ((($currentStep) / $ProgressSteps) * 100) ;$currentStep ++
    $OriginalCallingNumber = ([regex]::Matches($RawCall,'From: .* <sip:(.*)@').groups[1].value)
    Write-UcmLog -Message "Original Calling Number (Caller ID) $OriginalCallingNumber" -Severity 1 -Component $function
    $CurrentCall.OriginalCallingNumber = $OriginalCallingNumber

    #Find the input Route Table
    Write-Progress -Activity "Step $currentStep/$ProgressSteps" -id 1 -Status "Call Route Table" -PercentComplete ((($currentStep) / $ProgressSteps) * 100) ;$currentStep ++
    $RouteTable = ([regex]::Matches($RawCall,'Using table (.*) to route call').groups[1].value)
    Write-UcmLog -Message "Call using Route Table $RouteTable" -Severity 1 -Component $function
    $CurrentCall.RouteTable = $RouteTable
    
    # Find Trans Table Matches  TODO This can match more than once?
    Write-Progress -Activity "Step $currentStep/$ProgressSteps" -id 1 -Status "Trans Table Match" -PercentComplete ((($currentStep) / $ProgressSteps) * 100) ;$currentStep ++
    $TransTableMatch = ([regex]::Matches($RawCall,'Transformation table\((.*)\) is a SUCCESS').groups[1].value)
    
    #Check for Multiple Trans table matches
    $MultiMatchCheck = [regex]::Matches($RawCall,'Transformation table\((.*)\) is a SUCCESS')
    If ($MultiMatchCheck.count -gt 1)
    {
      Write-UcmLog -Message "Multiple Trans Table Matches found. Call $callid might have been Rerouted" -Severity 3 -Component $function
      Write-UcmLog -Message "ReRouted calls require further testing/development" -Severity 3 -Component $function
      Write-UcmLog -Message "Please use LX to check findings!" -Severity 3 -Component $function
    }
    
    Write-UcmLog -Message "Call Matched Transformation Table $TransTableMatch" -Severity 1 -Component $function
    $CurrentCall.TransTableMatches = $TransTableMatch
  
    #Trans Table Entries
    Write-Progress -Activity "Step $currentStep/$ProgressSteps" -id 1 -Status "Trans Table Entries" -PercentComplete ((($currentStep) / $ProgressSteps) * 100) ;$currentStep ++
    Write-UcmLog -Message "## Call Matched Transformation Table Entries" -Severity 1 -Component $function
    
    #$TransTableTests = (Select-String -InputObject $RawCall -Pattern 'Rule (.*) being tested for selection.' -AllMatches)
    #ForEach($TransTableTestMatch in ($TransTableTests.Matches))   #This is fucked todo
    #{
    #  #$TransTableTestMatch.groups[1].value
    #  Write-UcmLog -Message "$($TransTableTestMatch.groups[1].value)" -Severity 1 -Component $function
    #}
    
    #Final Trans Table Entry
    Write-Progress -Activity "Step $currentStep/$ProgressSteps" -id 1 -Status "Matching Trans Table Entry" -PercentComplete ((($currentStep) / $ProgressSteps) * 100) ;$currentStep ++
    $FinalTransTableMatch = ([regex]::Matches($RawCall,'Successful route request with entry (.*)').groups[1].value)
    Write-UcmLog -Message "Call Matched Transformation Table Entry $TransTableMatch" -Severity 1 -Component $function
    $CurrentCall.FinalTranslationRule = $FinalTransTableMatch
    
 
    #Skipped Trans Entries
    Write-Progress -Activity "Step $currentStep/$ProgressSteps" -id 1 -Status "Skipped Trans Table Entries" -PercentComplete ((($currentStep) / $ProgressSteps) * 100) ;$currentStep ++

    Write-UcmLog -Message "## Disabled Translation Entries Tested" -Severity 1 -Component $function
    $SkippedTransTableTests = (Select-String -InputObject $RawCall -Pattern 'Rule (.*) skipped due to transformation entry disabled.' -AllMatches)
    
    #Run through each match and add it to the object
    ForEach($SkippedTransTableTest in ($SkippedTransTableTests.Matches))
    {
      Write-UcmLog -Message "$($SkippedTransTableTest.groups[1].value)" -Severity 1 -Component $function
      $CurrentCall.TransTableEntrySkips = ($CurrentCall.TransTableEntrySkips + $SkippedTransTableTest.groups[1].value)
    }
 
    #Failed Trans Entries
    Write-Progress -Activity "Step $currentStep/$ProgressSteps" -id 1 -Status "Failed Trans Table Entries" -PercentComplete ((($currentStep) / $ProgressSteps) * 100) ;$currentStep ++

    Write-UcmLog -Message "## Failed Translation Entries Tested" -Severity 1 -Component $function
    $FailedTransTableTests = (Select-String -InputObject $RawCall -Pattern 'Transformation table\((.*)\) is a FAILURE' -AllMatches)
    ForEach($FailedTransTableTest in ($FailedTransTableTests.Matches))   #This is fucked todo
    {
      $CurrentCall.TransTableFailures = ($CurrentCall.TransTableFailures + $FailedTransTableTest.groups[1].value)
      Write-UcmLog -Message "$($FailedTransTableTest.groups[1].value)" -Severity 1 -Component $function
    }
    #Find all Trans Table Tests 
  
    #Return all tested rules, disabled for now
    #$TransTableTests = (Select-String -InputObject $RawCall -Pattern 'Rule (.*) being tested for selection.' -AllMatches)
    
    
    #Find the Outbound Invite to grab the translated numbers
    #Split the raw call using the invite
    Write-Progress -Activity "Step $currentStep/$ProgressSteps" -id 1 -Status "Enumerating Invites" -PercentComplete ((($currentStep) / $ProgressSteps) * 100) ;$currentStep ++

    $RawInvites = $RawCall -split 'INVITE sip:' -notmatch '^$'
    
    #Set a flag to ensure we actually find the relevant invite
    $InviteFound = $False
    
    ForEach ($rawInvite in $RawInvites) 
    {
      $currentStep = 12
      #Check the invite matches the known CallID
      #Check we actually have an invite
      if ([regex]::Matches($rawInvite,'cid=(\d*)').count -ne 0)
      {
        #Great, now lets get that Invite's CID and see if it matches the call we care about
        $InviteCID = ([regex]::Matches($rawInvite,'cid=(\d*)').groups[1].value) 
        Write-UcmLog -Message "Found Invite with the CID of $inviteCID" -Severity 1 -Component $function
        
        #Found the Invite we care about, lets grab the translated numbers (because they arent logged for some goddamn reason)
        If ($inviteCID -eq $CallID)
        {
          Write-UcmLog -Message "Invite Matches Current Call" -Severity 1 -Component $function
          $InviteFound = $true
          Write-UcmLog -Message "## Translated Numbers" -Severity 1 -Component $function
          
          #Note, we arent looking for the "Invite SIP:" as we used that to split the content
          Write-Progress -Activity "Step $currentStep/$ProgressSteps" -id 1 -Status "Translated Calling Number" -PercentComplete ((($currentStep) / $ProgressSteps) * 100) ;$currentStep ++
      
          
          #This regex is really slow, I assume its parsing the entire invite instead of stopping as soon as a match is found
          #$TranslatedCallingNumber = ([regex]::Matches($rawInvite,'(.*)@').groups[1].value)
          
          #Faster Version
          $TranslatedCalledNumber = ((Select-String -InputObject $rawInvite -Pattern '(.*)@').matches.groups[1].value)
          
          Write-Progress -Activity "Step $currentStep/$ProgressSteps" -id 1 -Status "Translated Called Number" -PercentComplete ((($currentStep) / $ProgressSteps) * 100) ;$currentStep ++
      
          $TranslatedCallingNumber = ([regex]::Matches($rawInvite,'From: .* <sip:(.*)@').groups[1].value)
          Write-UcmLog -Message "Translated Called Number $TranslatedCalledNumber" -Severity 1 -Component $function
          Write-UcmLog -Message "Translated Calling Number $TranslatedCallingNumber" -Severity 1 -Component $function   
          $CurrentCall.TranslatedCallingNumber = $TranslatedCallingNumber
          $CurrentCall.TranslatedCalledNumber = $TranslatedCalledNumber
          
          #Find the Outbound Signalling Group
          Write-Progress -Activity "Step $currentStep/$ProgressSteps" -id 1 -Status "Locate Outbound Signaling Group" -PercentComplete ((($currentStep) / $ProgressSteps) * 100) ;$currentStep ++
          
          $OutboundSignallingGroup = ((Select-String -InputObject $RawCall -Pattern 'Number of SGs=., SGs={(.*) }').matches.groups[1].value)
          $CurrentCall.OutboundSignallingGroups = $OutboundSignallingGroup
          
          #Find if the call is re-routed
          Write-Progress -Activity "Step $currentStep/$ProgressSteps" -id 1 -Status "Re-Route Check" -PercentComplete ((($currentStep) / $ProgressSteps) * 100) ;$currentStep ++
          If ($RawCall -match 'Successful cause code reroute check')
          { 
            $Reroute = ((Select-String -InputObject $RawCall -Pattern 'Successful cause code reroute check with (.*)\n').matches.groups[1].value)
            $CurrentCall.CauseCodeReroute = $Reroute
            $ReRouteMatch = ([regex]::Matches($RawCall,'Transformation table\((.*)\) is a SUCCESS')[1].groups[1].value)
            $CurrentCall.ReRouteMatch = $ReRouteMatch
            $Reroute = ""
            $ReRouteMatch = ""
          }

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
      Write-UcmLog -Message "Could not locate invite for CID $callID - Check $CallID.txt for call details" -Severity 3 -Component $function
      $RawCall | Out-File -filepath "./$callid.txt"
      #pause
    }
    
    
    
    #Filtering Section
    
    # This needs to be cleaned up, but for now
    
    If ($OutboundSignallingGroups -ne "")
    {
     
      #check to see if the current call has the right signalling group
      If ($CurrentCall.outboundsignallinggroups -match $OutboundSignallingGroups)
      { 
        #Output the call details to the pipeline
        $CurrentCall
      }
    
    
    }
    Else
    {
      #Output the call details to the pipeline
      $CurrentCall
    
    }
    
    
    
  }
  $CurrentCallNum ++
  
}

# SIG # Begin signature block
# MIIRwgYJKoZIhvcNAQcCoIIRszCCEa8CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU0Qyd9sa3l17giIWTB+NKvBc6
# f6+ggg4OMIIGsDCCBJigAwIBAgIQCK1AsmDSnEyfXs2pvZOu2TANBgkqhkiG9w0B
# AQwFADBiMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYD
# VQQLExB3d3cuZGlnaWNlcnQuY29tMSEwHwYDVQQDExhEaWdpQ2VydCBUcnVzdGVk
# IFJvb3QgRzQwHhcNMjEwNDI5MDAwMDAwWhcNMzYwNDI4MjM1OTU5WjBpMQswCQYD
# VQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4xQTA/BgNVBAMTOERpZ2lD
# ZXJ0IFRydXN0ZWQgRzQgQ29kZSBTaWduaW5nIFJTQTQwOTYgU0hBMzg0IDIwMjEg
# Q0ExMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA1bQvQtAorXi3XdU5
# WRuxiEL1M4zrPYGXcMW7xIUmMJ+kjmjYXPXrNCQH4UtP03hD9BfXHtr50tVnGlJP
# DqFX/IiZwZHMgQM+TXAkZLON4gh9NH1MgFcSa0OamfLFOx/y78tHWhOmTLMBICXz
# ENOLsvsI8IrgnQnAZaf6mIBJNYc9URnokCF4RS6hnyzhGMIazMXuk0lwQjKP+8bq
# HPNlaJGiTUyCEUhSaN4QvRRXXegYE2XFf7JPhSxIpFaENdb5LpyqABXRN/4aBpTC
# fMjqGzLmysL0p6MDDnSlrzm2q2AS4+jWufcx4dyt5Big2MEjR0ezoQ9uo6ttmAaD
# G7dqZy3SvUQakhCBj7A7CdfHmzJawv9qYFSLScGT7eG0XOBv6yb5jNWy+TgQ5urO
# kfW+0/tvk2E0XLyTRSiDNipmKF+wc86LJiUGsoPUXPYVGUztYuBeM/Lo6OwKp7AD
# K5GyNnm+960IHnWmZcy740hQ83eRGv7bUKJGyGFYmPV8AhY8gyitOYbs1LcNU9D4
# R+Z1MI3sMJN2FKZbS110YU0/EpF23r9Yy3IQKUHw1cVtJnZoEUETWJrcJisB9IlN
# Wdt4z4FKPkBHX8mBUHOFECMhWWCKZFTBzCEa6DgZfGYczXg4RTCZT/9jT0y7qg0I
# U0F8WD1Hs/q27IwyCQLMbDwMVhECAwEAAaOCAVkwggFVMBIGA1UdEwEB/wQIMAYB
# Af8CAQAwHQYDVR0OBBYEFGg34Ou2O/hfEYb7/mF7CIhl9E5CMB8GA1UdIwQYMBaA
# FOzX44LScV1kTN8uZz/nupiuHA9PMA4GA1UdDwEB/wQEAwIBhjATBgNVHSUEDDAK
# BggrBgEFBQcDAzB3BggrBgEFBQcBAQRrMGkwJAYIKwYBBQUHMAGGGGh0dHA6Ly9v
# Y3NwLmRpZ2ljZXJ0LmNvbTBBBggrBgEFBQcwAoY1aHR0cDovL2NhY2VydHMuZGln
# aWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZFJvb3RHNC5jcnQwQwYDVR0fBDwwOjA4
# oDagNIYyaHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZFJv
# b3RHNC5jcmwwHAYDVR0gBBUwEzAHBgVngQwBAzAIBgZngQwBBAEwDQYJKoZIhvcN
# AQEMBQADggIBADojRD2NCHbuj7w6mdNW4AIapfhINPMstuZ0ZveUcrEAyq9sMCcT
# Ep6QRJ9L/Z6jfCbVN7w6XUhtldU/SfQnuxaBRVD9nL22heB2fjdxyyL3WqqQz/WT
# auPrINHVUHmImoqKwba9oUgYftzYgBoRGRjNYZmBVvbJ43bnxOQbX0P4PpT/djk9
# ntSZz0rdKOtfJqGVWEjVGv7XJz/9kNF2ht0csGBc8w2o7uCJob054ThO2m67Np37
# 5SFTWsPK6Wrxoj7bQ7gzyE84FJKZ9d3OVG3ZXQIUH0AzfAPilbLCIXVzUstG2MQ0
# HKKlS43Nb3Y3LIU/Gs4m6Ri+kAewQ3+ViCCCcPDMyu/9KTVcH4k4Vfc3iosJocsL
# 6TEa/y4ZXDlx4b6cpwoG1iZnt5LmTl/eeqxJzy6kdJKt2zyknIYf48FWGysj/4+1
# 6oh7cGvmoLr9Oj9FpsToFpFSi0HASIRLlk2rREDjjfAVKM7t8RhWByovEMQMCGQ8
# M4+uKIw8y4+ICw2/O/TOHnuO77Xry7fwdxPm5yg/rBKupS8ibEH5glwVZsxsDsrF
# hsP2JjMMB0ug0wcCampAMEhLNKhRILutG4UI4lkNbcoFUCvqShyepf2gpx8GdOfy
# 1lKQ/a+FSCH5Vzu0nAPthkX0tGFuv2jiJmCG6sivqf6UHedjGzqGVnhOMIIHVjCC
# BT6gAwIBAgIQDyLHeeRvkUFg5QtSFTT8FjANBgkqhkiG9w0BAQsFADBpMQswCQYD
# VQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4xQTA/BgNVBAMTOERpZ2lD
# ZXJ0IFRydXN0ZWQgRzQgQ29kZSBTaWduaW5nIFJTQTQwOTYgU0hBMzg0IDIwMjEg
# Q0ExMB4XDTIzMDIyMzAwMDAwMFoXDTI2MDIyMzIzNTk1OVowXjELMAkGA1UEBhMC
# QVUxETAPBgNVBAgTCFZpY3RvcmlhMRAwDgYDVQQHEwdCZXJ3aWNrMRQwEgYDVQQK
# EwtKYW1lcyBBcmJlcjEUMBIGA1UEAxMLSmFtZXMgQXJiZXIwggIiMA0GCSqGSIb3
# DQEBAQUAA4ICDwAwggIKAoICAQC47oExh25TrxvApIYdMRYvjOdZCb8WwgeTemm3
# ZY7BElIWu6+gzRGqQe8RFsN7oIgin5pvjTYIToxt1CCag2A5o8L0NtULmxJEegc+
# VaF24DZQqI4qGQGH/Qnglqys6+yPkwLnfeSxpeWe4u49HUUGDFIxHCh42MlCLp/f
# fHT49QhhpO+LyeLnDoUs6DmahyIb6NeE2cW5AYRXEesW7GRNfXzygBSlVWJOgvcy
# V5Y4IvAZVx2hKKMTjYFIz4/RYMg7fwYZEJ2LRJ/GnVazobKAvh6ZBet5KwVNI9EI
# 29DtWQyK/RoPOguTRcB5VuiZVlv0xjBYM7iJuH2Soa3StQYVxL/5gjZCC9WOs4NR
# EIGU3XmHoogFDvoT1vf1izMPFQzdZfgPvy/XXsbgTVo5ncesJ6WtZwqwCXG1K0XW
# IPZqTHolc1MyU6K1bEHO+7YWLpKgM9THl644G7PEhcKpNDsHlfvLVQdYhI55UJtc
# iyMrTw11CNECvk3GK1mrluvKsrxdaH6G3Sp9VVHRtef6OZ5SlzkM5ID4egB2bXRb
# R/69bEuZr5hhm+v2lBSWIbZj/Mva6i/a/TAvy4vvPLo3DRcASkYZDC4T8gDMzmpG
# Xs4jAc9sfTL9z+o5u1PLJHFGRjJ+Wa2CgSftCdbKLjn+AY9m8ipc8jmOBKNY9yGI
# pQWapQIDAQABo4ICAzCCAf8wHwYDVR0jBBgwFoAUaDfg67Y7+F8Rhvv+YXsIiGX0
# TkIwHQYDVR0OBBYEFOBsg1xudlbXVSql8pWbiHoTyZS/MA4GA1UdDwEB/wQEAwIH
# gDATBgNVHSUEDDAKBggrBgEFBQcDAzCBtQYDVR0fBIGtMIGqMFOgUaBPhk1odHRw
# Oi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkRzRDb2RlU2lnbmlu
# Z1JTQTQwOTZTSEEzODQyMDIxQ0ExLmNybDBToFGgT4ZNaHR0cDovL2NybDQuZGln
# aWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZEc0Q29kZVNpZ25pbmdSU0E0MDk2U0hB
# Mzg0MjAyMUNBMS5jcmwwPgYDVR0gBDcwNTAzBgZngQwBBAEwKTAnBggrBgEFBQcC
# ARYbaHR0cDovL3d3dy5kaWdpY2VydC5jb20vQ1BTMIGUBggrBgEFBQcBAQSBhzCB
# hDAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMFwGCCsGAQUF
# BzAChlBodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVk
# RzRDb2RlU2lnbmluZ1JTQTQwOTZTSEEzODQyMDIxQ0ExLmNydDAJBgNVHRMEAjAA
# MA0GCSqGSIb3DQEBCwUAA4ICAQBOh5vRXqTCQzv0T1F2EgDkq5VnljlHsa7Ov/d/
# lpOvr8NebBiatxbhfhPCnToY7BD2f7YVsUuQ+VDdcIYsskcU5spBHcFYidg2jGu4
# 59FGMaS765XStDwGGTN/360gEsNYSnKWYL4+8jYWHlzRO0jHloyWz+gF5dYWzdDJ
# u1dudLIJ0RgrEVJeLSgIBWygLL5EyIzOPlrxztsILMSbdPTQLeBIm7ipOk4EACx1
# hhBVUsUoCAlASH+yCKDU4v2HFd7SzrkRUrf7XJ2Na2YsiHjiTGqHIE86KyvxGDhT
# 3n2/jX23Nh/bkWHurHwTfaTCOQ44ZlAbnZQjBlmrFn5hPMXRpciiQFmrKTPD/nuo
# 9MVnCciHEpHJ63/JZNF/eno1122/wVkL7MuRlCVHN7L/wuNQxQk3ARdIju6OD/Gi
# Mwg0Qih6HVWJtkHK3ExoUKKKUZCOvIeHxzp+K6FWUupPZKUgWzn4AHMxm6zr+Sde
# laIAACqAkxYsDYKbM7WlNi3uIH2HeXqU9uSDt5tgPpImrog/ab4HrhpDfITRgT1c
# cxaWQezpJEPC+kqVD41T3wlEie1Qm4vYWg+oBVEMBxVLh6CYbeppCRTEXRGnAiCH
# /Ma1uwyWnNCWxrhd1uSi6sj4ISzgnFyGCvsI0gavKpS5AQhapJgk6/fULTFeS+Ee
# kRH9FDGCAx4wggMaAgEBMH0waTELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lD
# ZXJ0LCBJbmMuMUEwPwYDVQQDEzhEaWdpQ2VydCBUcnVzdGVkIEc0IENvZGUgU2ln
# bmluZyBSU0E0MDk2IFNIQTM4NCAyMDIxIENBMQIQDyLHeeRvkUFg5QtSFTT8FjAJ
# BgUrDgMCGgUAoHgwGAYKKwYBBAGCNwIBDDEKMAigAoAAoQKAADAZBgkqhkiG9w0B
# CQMxDAYKKwYBBAGCNwIBBDAcBgorBgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAj
# BgkqhkiG9w0BCQQxFgQUxe4tZO0VkNXJDBv+fYqCK1JRBWYwDQYJKoZIhvcNAQEB
# BQAEggIAP+avQ2xxSTn3+zEKHayWF43GLGkA1TQmlofXJYRlQGtWPpJ6ypxqQpen
# 1rKQxiIHx5vPYgwFQXIVIw5OVCd7TkkKvxyqJB1O26Muu6YuWQ+Tgpfeu+czEjJ6
# X0t1cjwURONFUazh4hckNkRoL2d2CGA1dGVUJiDMuGRAKpJBzPm8x4SEFSqu/oBu
# VX2/dVtk2M9woyGdlsObTlbGimsSiMdULYChOcvSwuL41xB22KnX3cs1lB2DZ7Ge
# avWmc3BlVWZ39U93ulxhOky97LJJRLvzNmlNxONnNeDmahrrbT4PiYGvAWiFDYQ2
# wsR0BRbPHRxMlLC+Ej9isnXHn8mN5P8s5U+1z/DCCkr2dVUt5WyNNVQC8zllYRPp
# C00fB7i/YfyZoC3WZW1nRmZUemZeSGTTr4U6ldim4y0VcDuw/WMFMuw/M0C8Gqx4
# vUtzVgSc1+1pUeDcvfmH06haijSAADTBVch85rI4mZ+hPisGnzjfmjlClVY7jg3f
# WlukGuaooYG65QVV5/d3bRO5u1lmEoRaxVHrIsj6ebcNrAdMSd9sRL9eJZPMVreK
# hCEYtcIFn7FbHRN/3A514/9qU4qyl4MCEMW3sbg4lv1p0wedGyVQiH7IAMqKfPsP
# A3w8/Ao+i7V7Bj/AawbzRvBT3vc8RmU32B4LlI024OtvJOBUhYU=
# SIG # End signature block
