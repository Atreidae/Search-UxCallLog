<#
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

    .PARAMETER Path
    Optional path to parse when -ParseFolder is set. If omitted, the current working folder is used.


    Created by James Arber. www.UcMadScientist.com
    
    .NOTES

    Version                : 0.3.2
    Date                   : 06/05/2026
    Author                 : James Arber
    Header stolen from     : Greig Sheridan who stole it from Pat Richard's amazing "Get-CsConnections.ps1"

   : v0.3.2: Patch Release
   - Added better unroutable call handling
   - Cleaned up commented out code
   - Noted some issues with Transtable matches stemming from ambiguous log entries, added some more specific regex to try and pull the correct info, needs more testing
   - Error message fixed
   - Refactored main loop into functions
   - Fixed version reporting
   - Rewrote the Trans table entry matching to use a different method
   - Renamed "Trans Table Entries" to "Transformation Rule Entries" to more accurately reflect Ribbon terminology and avoid confusion with the "Transformation Table Entries" which are the tables that contain the entries that are being tested
   - Optimized multi file parsing to use array collection instead of += for better performance and precompiled Regex filters (thanks GitHub Copilot)
   - Updated Ucm-WriteLog to just exit if a verbose message is being written but the preference is set to silently continue
    Note: Digicert are no longer offer MVPs free code signing certificates and mine has expired, so I have removed the code signing cert until I can sort a new one out, sorry about that, if you know of a good alternative please let me know!

    :v0.3.1: Patch Release
    - Noted new Ribbon file format, added checks and logic changes to suit
    Known Bug: Line Numbers are currently reported incorrectly.
    Note: Removed Code signing Cert whilst I sort a new one

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
  [String]$Path = $null,
  [String]$script:LogFileLocation = $null,
  [String]$InputFile = './webui.log',
  [String]$OutboundSignallingGroups = ''
)

$script:LogFileLocation = 'c:\ucmadscientist\scratch\foo.log'

if (!$script:LogFileLocation) 
{
  $script:LogFileLocation = $PSCommandPath -replace '.ps1', '.log'
 
}

#region config
[Net.ServicePointManager]::SecurityProtocol = 'tls12, tls11, tls'
#$VerbosePreference                  = 'SilentlyContinue' #TODO
[String]$ScriptVersion = '0.3.2'
[string]$GithubRepo = 'Search-UxCallLog'
[string]$GithubBranch = 'master' #todo
[string]$BlogPost = 'https://www.UcMadScientist.com/preparing-for-teams-export-your-on-prem-lis-data-for-cqd/' #todo

function Write-UcmLog 
{
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
  param
  (
    [String]$Message,
    [String]$Path = $Script:LogFileLocation,
    [int]$Severity = 1,
    [string]$Component = 'Default',
    [switch]$LogOnly
  )
  
  #Early exit for verbose severity if verbose preference is off
  if ($Severity -eq 1 -and $VerbosePreference -eq 'SilentlyContinue') 
  {
    return
  }
  
  $function = 'Write-UcmLog'
  $Date = Get-Date -Format 'HH:mm:ss'
  $Date2 = Get-Date -Format 'MM-dd-yyyy'
  $MaxLogFileSizeMB = 10

  #Check to see if the file exists
  if (Test-Path -Path $Path)
  {
    if (((Get-ChildItem -Path $Path).length / 1MB) -gt $MaxLogFileSizeMB) # Check the size of the log file and archive if over the limit.
    {
      $ArchLogfile = $Path.replace('.log', "_$(Get-Date -Format dd-MM-yyy_hh-mm-ss).lo_")
      Rename-Item -Path $Path -NewName $ArchLogfile
    }
  }

  #Write to the log file
  "$env:ComputerName date=$([char]34)$Date2$([char]34) time=$([char]34)$Date$([char]34) component=$([char]34)$component$([char]34) type=$([char]34)$severity$([char]34) Message=$([char]34)$Message$([char]34)" | Out-File -FilePath $Path -Append -NoClobber -Encoding default

  #If LogOnly is not set, output the log entry to the screen
  if (!$LogOnly) 
  {
    #If the log entry is just Verbose (1), output it to write-verbose
    if ($severity -eq 1) 
    {
      "$Message" | Write-Verbose
    }
    #If the log entry is just informational (2), output it to write-host
    if ($severity -eq 2) 
    {
      "INFO: $Message" | Write-Host -ForegroundColor Green
    }
    #If the log entry has a severity of 3 assume its a warning and write it to write-warning
    if ($severity -eq 3) 
    {
      "$Date $Message" | Write-Warning
    }
    #If the log entry has a severity of 4 or higher, assume its an error and display an error message (Note, critical errors are caught by throw statements so may not appear here)
    if ($severity -ge 4) 
    {
      "$Date $Message" | Write-Error
    }
  }
}

function Get-IEProxy
{
  $function = 'Get-IEProxy'
  Write-UcmLog -component $function -Message 'Checking for IE First Run' -severity 1
  if ((Get-Item -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings').Property -notcontains 'ProxyEnable')
  {
    $null = New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name ProxyEnable -Value 0
  }
  

  Write-UcmLog -component $function -Message 'Checking for Proxy' -severity 1
  if ( (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings').ProxyEnable -ne 0)
  {
    $proxies = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings').proxyServer
    if ($proxies) 
    {
      if ($proxies -ilike '*=*')
      {
        return $proxies -replace '=', '://' -split (';') | Select-Object -First 1
      }
      
      else 
      {
        return ('http://{0}' -f $proxies)
      }
    }
    
    else 
    {
      return $null
    }
  }
  else 
  {
    return $null
  }
}

function Get-ScriptUpdate 
{
  $function = 'Get-ScriptUpdate'
  Write-UcmLog -component $function -Message 'Checking for Script Update' -severity 1
  Write-UcmLog -component $function -Message 'Checking for Proxy' -severity 1
  $ProxyURL = Get-IEProxy
  
  if ($ProxyURL)
  
  {
    Write-UcmLog -component $function -Message "Using proxy address $ProxyURL" -severity 1
  }
  
  else
  {
    Write-UcmLog -component $function -Message 'No proxy setting detected, using direct connection' -severity 1
  }

  Write-UcmLog -component $function -Message "Polling https://raw.githubusercontent.com/atreidae/$GithubRepo/$GithubBranch/version" -severity 1
  $GitHubScriptVersion = Invoke-WebRequest -Uri "https://raw.githubusercontent.com/atreidae/$GithubRepo/$GithubBranch/version" -TimeoutSec 10 -Proxy $ProxyURL -UseBasicParsing
  
  if ($GitHubScriptVersion.Content.length -eq 0) 
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
    $NeedUpdate = $false
    #Check for Major version

    if ([single]$splitgitver[0] -gt [single]$splitver[0])
    {
      $NeedUpdate = $true
      #New Major Build available, #Prompt user to download
      Write-UcmLog -component $function -Message 'New Major Version Available' -severity 3
      $title = 'Update Available'
      $Message = 'a major update to this script is available, did you want to download it?'
    }

    if (([single]$splitgitver[1] -gt [single]$splitver[1]) -and ([single]$splitgitver[0] -eq [single]$splitver[0]))
    {
      $NeedUpdate = $true
      #New Major Build available, #Prompt user to download
      Write-UcmLog -component $function -Message 'New Minor Version Available' -severity 3
      $title = 'Update Available'
      $Message = 'a minor update to this script is available, did you want to download it?'
    }

    if (([single]$splitgitver[2] -gt [single]$splitver[2]) -and ([single]$splitgitver[1] -gt [single]$splitver[1]) -and ([single]$splitgitver[0] -eq [single]$splitver[0]))
    {
      $NeedUpdate = $true
      #New Major Build available, #Prompt user to download
      Write-UcmLog -component $function -Message 'New Bugfix Available' -severity 3
      $title = 'Update Available'
      $Message = 'a bugfix update to this script is available, did you want to download it?'
    }

    if ($NeedUpdate)
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
    else
    {
      Write-UcmLog -component $function -Message 'Script is upto date' -severity 1
    }
  }
}



function Import-UXlogFiles 
{

  $function = 'Read-Logs'
  Write-Progress -Activity 'Initial Import' -Status 'Importing Raw Log File'


  if ($ParseFolder -or $PSBoundParameters.ContainsKey('Path'))
  {
    $parsePath = if ([string]::IsNullOrWhiteSpace($Path)) { '.' } else { $Path }

    if ($parsePath -eq '.')
    {
      Write-UcmLog -Message 'Parsing local folder. To use a custom path, specify the -Path parameter.' -Severity 3 -Component $function
    }

    #Import all the log files in the target folder and sort them by created date so calls bridging files line up
    $files = ((Get-ChildItem -Path $parsePath -Filter '*.log').FullName | Sort-Object -Property CreationTime)
  
    #Check for and provide feedback on no log files
    if ($files.count -eq 0)
    {
      Write-UcmLog -Message "No log files to import in $parsePath. Exiting..." -Severity 3 -Component $function
      throw "No log files to import in $parsePath. Exiting..."  
    }
    
    # Use array collection instead of += for better performance
    $LogContent = @()
    foreach ($file in $files)
    {
      Write-Progress -Activity 'Importing Log Files' -Status "Importing $file" -PercentComplete ((($LogContent.Count + 1) / $files.Count) * 100)
      $LogContent += Get-Content $File -Raw
    }
    return ($LogContent -join '')
  }

  else
  { 
    #Import the logfile
    Write-UcmLog -Message 'Importing Log File' -Severity 1 -Component $function
    $RawLogFile = (Get-Content $InputFile -Raw)
    return $RawLogFile
  }

}


#region setup
#Get Proxy Details
$ProxyURL = Get-IEProxy
if ($ProxyURL) 
{
  Write-UcmLog -Message "Using proxy address $ProxyURL" -severity 2
}
else 
{
  Write-UcmLog -Message 'No proxy setting detected, using direct connection' -severity 1
}

#Check for Script update
$SkipUpdateCheck = $true #todo
if ($SkipUpdateCheck -eq $false) 
{
  #Get-ScriptUpdate #todo
}


Write-UcmLog -Message "$GithubRepo.ps1 Version $ScriptVersion" -severity 2

#region Pre-compiled Regex Patterns (for performance, suggested by GitHub Copilot) 
$regex = @{
  'HandleInitialInvite'      = [regex]'Handling initial invite\.'
  'SendToSipUserOldFormat'   = [regex]'sendToSipUser: Handling initial invite\.'
  'SendToSipUserNewFormat'   = [regex]'sendToSipUser:Handling initial invite\.'
  'UsingTable'               = [regex]'Using table (.*) to route call'
  'TransTableSuccess'        = [regex]'Transformation table\((.*)\) is a SUCCESS'
  'TransTableFailure'        = [regex]'Transformation table\((.*)\) is a FAILURE'
  'CallID'                   = [regex]'\]\[CID:(\d*)\]'
  'CallTime'                 = [regex]'\[(.*),...\]'
  'ToNumber'                 = [regex]'To: .*<sip:(.*)@'
  'FromNumber'               = [regex]'From: .*<sip:(.*)@'
  'SkippedRule'              = [regex]'Rule (.*) skipped due to transformation entry disabled\.'
  'PerformingTransformation' = [regex]'Performing (OPTIONAL|MANDATORY) transformation using entry (.*) (\(\d\.\d\(\d\)\))\.'
  'PerformingSplit'          = [regex]'(?=Performing (?:OPTIONAL|MANDATORY) transformation using entry)'
  'ResultMatch'              = [regex]'- (Failed|Successful) regex match of "([^"]*)" field for "([^"]*)" \(updated "[^"]*"\) with input of "([^"]*)"'
  'RegexOutput'              = [regex]'Regex replacement output of "([^"]*)" field is "([^"]*)"'
  'CID'                      = [regex]'cid=(\d*)'
  'SignallingGroups'         = [regex]'Number of SGs=., SGs={(.*) }'
  'ReRouteCheck'             = [regex]'Successful cause code reroute check'
  'ReRouteWith'              = [regex]'Successful cause code reroute check with (.*)\n'
}

# Pattern strings for [regex]::Split() which requires a string pattern
$regexPatterns = @{
  'PerformingSplit' = '(?=Performing (?:OPTIONAL|MANDATORY) transformation using entry)'
}
#endregion Pre-compiled Regex Patterns

#endregion setup

#region main

#Get logs
$RawLogFile = Import-UXlogFiles

#Process data.

#Find all the calls that entered the SBC and split them into their own object
$function = 'Parse-Invites'
Write-Progress -Activity 'Initial Import' -Status 'Locating Call Markers'
Write-UcmLog -Message 'Locating Calls' -Severity 1 -Component $function


#method 1
#$CallLocations = [regex]::Matches($RawLogFile,'Handling initial invite.')

#Method 2
#$CallLocations = (Select-String -InputObject $RawLogFile -Pattern 'Handling initial invite.' -AllMatches -SimpleMatch)

#Method 3 (Return line numbers, doesnt like multi file)
#$CallLocations =  (Select-String -Path $inputfile -Pattern 'Handling initial invite.')

#Method 4 (Return line numbers)
$CallLocations = (Select-String -InputObject $RawLogFile -Pattern 'Handling initial invite.' -AllMatches)
$TotalCalls = $CallLocations.matches.count

Write-UcmLog -Message "Found $TotalCalls Invites." -Severity 2 -Component $function

#Split the log file using the "Handling Initial Invite Marker (This should work for test calls, not just real calls)
$RawCalls = $RawLogFile -split 'sendToSipUser: Handling initial invite.' -notmatch '^$'

#Text for "Handling initial invite was changed, check to see if its the new version

if ($RawCalls.count -eq 1)
{
  Write-UcmLog -Message 'Only found one call, log file may be using new format, testing' -Severity 1 -Component $function
  $NewRawCalls = $RawLogFile -split 'sendToSipUser:Handling initial invite.' -notmatch '^$'
  if ($NewRawCalls.count -ge 2)
  {
    Write-UcmLog -Message 'New invite format detected, parsing' -Severity 1 -Component $function
    $rawcalls = $NewRawCalls
    #$2025Fileformat = $true
  }

}
else
{
  if ($TotalCalls -ge 2)
  {
    Write-UcmLog -Message "Found $totalcalls 'Handling initial invite.' log messages but only found one 'sendToSipUser: Handling initial invite.' log message, Potential unsupported file format, Please raise an issue!" -Severity 3 -Component $function
  }
}

#Cleanup our lingering memory objects
Remove-Variable -Name 'RawLogFile'


#Process each Call Object
$function = 'Call-ProcessLoop'
$CurrentCallProgress = 0
$CurrentCallNum = 0

foreach ($RawCall in $RawCalls)
{
  Write-UcmLog -Message "Foreach loop, processing call $currentcallNum" -Severity 1 -Component $function
  #Skip the first "call" object as it's just whats in the log before the first detected invite
    
  if ($CurrentCallNum -eq 0)
  {
    Write-UcmLog -Message 'Skipping Prelogs' -Severity 1 -Component $function
  }
  
  #Process the actual call
  else 
  {
    $CurrentCallProgress ++
    Write-Progress -Activity 'Processing Calls' -Status "Locating Call $CurrentCallProgress of $TotalCalls details"  -PercentComplete ((($CurrentCallProgress) / $TotalCalls) * 100)
    $CurrentCall = [PSCustomObject]@{
      'CallID'                      = 'Unknown'
      'CallTime'                    = 'Unknown'
      'InviteLineNumber'            = 'Unknown'
      'OriginalCallingNumber'       = 'Unknown'
      'OriginalCalledNumber'        = 'Unknown'
      'TranslatedCallingNumber'     = 'Unknown'
      'TranslatedCalledNumber'      = 'Unknown'
      'RouteTable'                  = 'Unknown'
      'TransformationTableMatches'  = [System.Collections.ArrayList]@()
      'TransformationTableFailures' = [System.Collections.ArrayList]@()
      'TransformationRuleMatches'   = [System.Collections.ArrayList]@()
      'TransformationRuleFailures'  = [System.Collections.ArrayList]@()
      'TransformationRuleSkips'     = [System.Collections.ArrayList]@()
      'FinalTransformationRule'     = 'Unknown'
      'OutboundSignallingGroups'    = 'Unknown'
      'CauseCodeReRoute'            = 'No'
      'ReRouteMatch'                = 'NA'
      'Unroutable'                  = $False
      #'RouteFound' = $False
    }

    #Setup for Progress Bars
    $ProgressSteps = 16
    $currentStep = 1
    
    #region call details

    #Find the Call ID
    Write-Progress -Activity "Step $currentStep/$ProgressSteps" -Id 1 -Status 'Call ID' -PercentComplete ((($currentStep) / $ProgressSteps) * 100) ; $currentStep ++
    $CallID = ($regex['CallID'].Matches($RawCall)[0].groups[1].value)
    Write-UcmLog -Message "# Call ID $CallID" -Severity 1 -Component $function
    $CurrentCall.CallID = $callID
    
    #Greig Asked for time of invite, that goes here
    Write-Progress -Activity "Step $currentStep/$ProgressSteps" -Id 1 -Status 'Call Time' -PercentComplete ((($currentStep) / $ProgressSteps) * 100) ; $currentStep ++
    $CallTime = ($regex['CallTime'].Matches($RawCall)[0].groups[1].value)
    Write-UcmLog -Message "# Call ID $CallID" -Severity 1 -Component $function
    $CurrentCall.CallTime = $CallTime
    
    #Calculate the LineNumber of the invite (buggy)
    Write-Progress -Activity "Step $currentStep/$ProgressSteps" -Id 1 -Status 'Call Line Number' -PercentComplete ((($currentStep) / $ProgressSteps) * 100) ; $currentStep ++

    #this match no longer appears to work
    #$InviteLineNumber = ($CallLocations[($CurrentCallNum -1)].LineNumber)

    #Todo this is returning incorrect results.
    $InviteLineNumber = ($CallLocations.matches.captures[($CurrentCallNum - 1)].Index)
    
    if ($InviteLineNumber -eq '')
    { 
      Write-UcmLog -Message 'Error finding invite line number' -Severity 1 -Component $function
      $CurrentCall.InviteLineNumber = $InviteLineNumber
    }
    else
    {
      Write-UcmLog -Message "Found an Invite on line $InviteLineNumber" -Severity 1 -Component $function
      $CurrentCall.InviteLineNumber = $InviteLineNumber
    }

    #Find the Called Number Details
    Write-Progress -Activity "Step $currentStep/$ProgressSteps" -Id 1 -Status 'Original Called Number' -PercentComplete ((($currentStep) / $ProgressSteps) * 100) ; $currentStep ++
    
    #Old logs removed from 9.x 
    #$OriginalCalledNumber = ([regex]::Matches($RawCall,'Received MSG_CC_SETUP message with called#\[(.*)\]').groups[1].value)

    #use the invite instead
    $OriginalCalledNumber = ($regex['ToNumber'].Matches($RawCall)[0].groups[1].value) 
    
    if ($OriginalCalledNumber -eq '')
    { 
      Write-UcmLog -Message 'Error finding called number' -Severity 3 -Component $function
    }
    else
    {

      Write-UcmLog -Message "Original Called Number (Digits Dialled) $OriginalCalledNumber" -Severity 1 -Component $function
      $CurrentCall.OriginalCalledNumber = $OriginalCalledNumber
    }



    #Find the Calling Number Details
    Write-Progress -Activity "Step $currentStep/$ProgressSteps" -Id 1 -Status 'Original Calling Number' -PercentComplete ((($currentStep) / $ProgressSteps) * 100) ; $currentStep ++
    $OriginalCallingNumber = ($regex['FromNumber'].Matches($RawCall)[0].groups[1].value) 
 

    if ($OriginalCallingNumber -eq '')
    { 
      Write-UcmLog -Message 'Error finding calling number' -Severity 3 -Component $function
    }
    else
    {

      Write-UcmLog -Message "Original Calling Number (Caller ID) $OriginalCallingNumber" -Severity 1 -Component $function
      $CurrentCall.OriginalCallingNumber = $OriginalCallingNumber
    }

    #endregion call details

    #region call routing
    #Find the input Route Table
    Write-Progress -Activity "Step $currentStep/$ProgressSteps" -Id 1 -Status 'Call Route Table' -PercentComplete ((($currentStep) / $ProgressSteps) * 100) ; $currentStep ++
    $RouteTable = ($regex['UsingTable'].Matches($RawCall)[0].groups[1].value)
    Write-UcmLog -Message "Call using Route Table $RouteTable" -Severity 1 -Component $function
    $CurrentCall.RouteTable = $RouteTable
    
    # Find Trans Table Matches (ie the tables that had entries that matched the call, not the actual entries, that comes later)
    Write-Progress -Activity "Step $currentStep/$ProgressSteps" -Id 1 -Status 'Transformation Table Matches' -PercentComplete ((($currentStep) / $ProgressSteps) * 100) ; $currentStep ++
    $TransTableMatches = $regex['TransTableSuccess'].Matches($RawCall)
    
    if ($TransTableMatches.Count -eq 0)
    {
      Write-UcmLog -Message 'No Transformation Table Match in Current call. Call is unroutable?' -Severity 3 -Component $function
      $currentCall.unroutable = $true
    }
    else 
    {  
      #Get all transformation table matches
      $TransTableMatch = $TransTableMatches | ForEach-Object { $_.groups[1].value }
      $CurrentCall.TransformationTableMatches = $TransTableMatch
    
      #Check for Multiple Trans table matches
      $MultiMatchCheck = $regex['TransTableSuccess'].Matches($RawCall)
      if ($MultiMatchCheck.count -gt 1)
      {
        Write-UcmLog -Message "Multiple Trans Table Matches found. Call $callid might have been Rerouted" -Severity 3 -Component $function
        Write-UcmLog -Message 'ReRouted calls require further testing/development' -Severity 3 -Component $function
        Write-UcmLog -Message 'Please use LX to check findings!' -Severity 3 -Component $function
      }
    
      Write-UcmLog -Message "Call Matched Transformation Table $TransTableMatch" -Severity 1 -Component $function
      $CurrentCall.TransformationTableMatches = $TransTableMatch
    }

    #Now we find all the Transformation Table failures

    Write-Progress -Activity "Step $currentStep/$ProgressSteps" -Id 1 -Status 'Transformation Table Failures' -PercentComplete ((($currentStep) / $ProgressSteps) * 100) ; $currentStep ++


    $TransTableFailuresRegexMatch = $regex['TransTableFailure'].Matches($RawCall)
    
    if ($TransTableFailuresRegexMatch.Count -eq 0)
    {
      Write-UcmLog -Message 'no failures, moving on' -Severity 1 -Component $function
    }
    else 
    {  
      $TransTableFailures = $TransTableFailuresRegexMatch | ForEach-Object { $_.groups[1].value }
    
      Write-UcmLog -Message "Transformation Table $TransTableFailures Failed" -Severity 1 -Component $function
      $CurrentCall.TransformationTableFailures = $TransTableFailures
    }
   
    #endregion call routing

    #region Transformation Rules
  
    #Transformation Rule Entries
    Write-Progress -Activity "Step $currentStep/$ProgressSteps" -Id 1 -Status 'Transformation Rule Entries' -PercentComplete ((($currentStep) / $ProgressSteps) * 100) ; $currentStep ++
    Write-UcmLog -Message '## Call Matched Transformation Rule Entries' -Severity 1 -Component $function
  
    
    #Transformation Rule Matches
    Write-Progress -Activity "Step $currentStep/$ProgressSteps" -Id 1 -Status 'Transformation Rule Matches' -PercentComplete ((($currentStep) / $ProgressSteps) * 100) ; $currentStep ++


    #Split the call by each route request attempt (both successful and failed)
    $RouteRequests = $RawCall -split 'Handling route request\.'
    Write-UcmLog -Message "Found $($RouteRequests.Count) route request attempts" -Severity 1 -Component $function
    
    #Process each route request
    foreach ($RouteRequest in $RouteRequests)
    {
      #Skip if this route request doesn't contain valid routing data
      if ($RouteRequest -notmatch 'Using table .* to route call\.') { continue }
      
      Write-UcmLog -Message 'Processing route request' -Severity 1 -Component $function
      
      #Extract transformation rule tests from this route request
      #Split before each "Performing" line so the line stays in the result
      $TransformationRuleTests = [regex]::Split($RouteRequest, $regexPatterns['PerformingSplit'])
      Write-UcmLog -Message "Found $($TransformationRuleTests.Count) Transformation Rule Tests" -Severity 1 -Component $function

      #Pull enabled transformation rule details
      foreach ($TransformationRuleTest in ($TransformationRuleTests))
      {
        #check to see if this is actually a transformation rule. look for "regex match"
        if ($TransformationRuleTest -notmatch 'regex match')
        {
          Write-UcmLog -Message "Skipping transformation rule test as it doesn't appear to contain a regex match result" -Severity 1 -Component $function
          continue
        } 

        Write-UcmLog -Message "Transformation Rule Test: $($TransformationRuleTest)" -Severity 1 -Component $function

        #Declare object
        $TransformationRule = [PSCustomObject]@{
          'Rule Name'   = 'Unknown'
          'Rule ID'     = 'Unknown' 
          'Test Type'   = 'Unknown'   #Mandatory or Optional
          'InputField'  = 'Unknown'   #Example: tfCalledNumber / tfCallingNumber
          'OutputField' = 'Unknown'   #Example: tfCalledNumber / tfCallingNumber
          'Input'       = 'Unknown'   #Example: +61370105555
          'Output'      = 'Unknown'   #Example: 0370105555
          'RegexTest'   = 'Unknown'   #Example: ^\+61(37010\d{3}$)
          'RegexManip'  = 'Unknown'   #Example: 0\1
          'Result'      = 'Unknown'   #Successful, Failed
      
        }
        #find the rule type, name and ID
        $FirstlineMatches = ($regex['PerformingTransformation'].Matches($TransformationRuleTest)[0].groups)
        $TransformationRule.'Test Type' = $FirstlineMatches[1].value
        $TransformationRule.'Rule Name' = $FirstlineMatches[2].value
        $TransformationRule.'Rule ID' = $FirstlineMatches[3].value

        #find the Result, Field, test and input
        $SecondLineMatches = ($regex['ResultMatch'].Matches($TransformationRuleTest)[0].groups)
        $TransformationRule.'Result' = $SecondLineMatches[1].value
        $TransformationRule.'InputField' = $SecondLineMatches[2].value
        $TransformationRule.'RegexTest' = $SecondLineMatches[3].value
        $TransformationRule.'Input' = $SecondLineMatches[4].value

        #If the rule was a successful match, capture the resulting manipulation
        if ($TransformationRule.'Result' -eq 'Successful')
        {
          $ThirdLineMatches = ($regex['RegexOutput'].Matches($TransformationRuleTest)[0].groups)
          $TransformationRule.'Output' = $ThirdLineMatches[0].value
          $TransformationRule.'OutputField' = $ThirdLineMatches[1].value
        }

        #Now determine which of those were matches, failures or skips and add them to the object
        if ($TransformationRule.'Result' -eq 'Successful')
        {
          $CurrentCall.TransformationRuleMatches.Add($TransformationRule.'Rule Name' + ' ' + $TransformationRule.'Rule ID') | Out-Null
        }
        elseif ($TransformationRule.'Result' -eq 'Failed')
        {
          $CurrentCall.TransformationRuleFailures.Add($TransformationRule.'Rule Name' + ' ' + $TransformationRule.'Rule ID') | Out-Null
        }
        else
        {
          Write-UcmLog -Message 'Error determining result of transformation rule test' -Severity 3 -Component $function
        }

      }
    
      #Set the current match as the "last"
      $CurrentCall.FinalTransformationRule = ($TransformationRule.'Rule Name') + ' ' + ($TransformationRule.'Rule ID')
    }
    
    #The log files show skipped rules differently, so we just write those to the object without trying to break them down
    #Skipped Transformation Rule
    Write-Progress -Activity "Step $currentStep/$ProgressSteps" -Id 1 -Status 'Skipped Transformation Rule Entries' -PercentComplete ((($currentStep) / $ProgressSteps) * 100) ; $currentStep ++

    $SkippedTransTableTests = (Select-String -InputObject $RawCall -Pattern 'Rule (.*) skipped due to transformation entry disabled.' -AllMatches)
    
    #Run through each match and add it to the object
    foreach ($SkippedTransTableTest in ($SkippedTransTableTests.Matches))
    {
      Write-UcmLog -Message "$($SkippedTransTableTest.groups[1].value)" -Severity 1 -Component $function
      $CurrentCall.TransformationRuleSkips = ($CurrentCall.TransformationRuleSkips + $SkippedTransTableTest.groups[1].value)
    }
    






    <#

        #Below this line is shit
        Write-UcmLog -Message "## Transformation Rule Entries Tested" -Severity 1 -Component $function
        $MatchedTransTableTests = (Select-String -InputObject $RawCall -Pattern 'Transformation table\((.*)\) is a SUCCESS' -AllMatches)
        ForEach($MatchedTransTableTests in ($MatchedTransTableTests.Matches))  
        {
        $CurrentCall.TransformationTableMatches = ($CurrentCall.TransformationTableMatches + $MatchedTransTableTests.groups[1].value)
        Write-UcmLog -Message "$($MatchedTransTableTests.groups[1].value)" -Severity 1 -Component $function
        }
        #select the last match and inject it into the main object as the final matched entry, 
        $CurrentCall.FinalTranslationRule = $CurrentCall.TransformationTableMatches[-1]

 
        #Failed Transformation TABLEs
        Write-Progress -Activity "Step $currentStep/$ProgressSteps" -id 1 -Status "Failed Trans Table Entries" -PercentComplete ((($currentStep) / $ProgressSteps) * 100) ;$currentStep ++

        Write-UcmLog -Message "## Failed Transformation Table Tests" -Severity 1 -Component $function
        $FailedTransTableTests = (Select-String -InputObject $RawCall -Pattern 'Transformation table\((.*)\) is a FAILURE' -AllMatches)
        ForEach($FailedTransTableTest in ($FailedTransTableTests.Matches))   #This is fucked todo
        {
        $CurrentCall.TransformationTableFailures = ($CurrentCall.TransformationTableFailures + $FailedTransTableTest.groups[1].value)
        Write-UcmLog -Message "$($FailedTransTableTest.groups[1].value)" -Severity 1 -Component $function
        }
     


        Foreach ($TransTableRouteTest in ($TransTableRouteTests.Matches))
        {
        Write-UcmLog -Message "Translation Rule Tested: $($TransTableRouteTest.groups[1].value)" -Severity 1 -Component $function

        #Break up into Trans Table ENTRIES
        $TransTableEntryTests = (Select-String -InputObject $RawCall -Pattern "Performing \((.*)\) transformation using entry" -AllMatches)
      
        ForEach($TransTableEntryTest in ($TransTableEntryTests.Matches))  
        {
        Write-UcmLog -Message "Translation Rule Tested: $($TransTableEntryTest.groups[1].value)" -Severity 1 -Component $function
        $CurrentCall.TransTableEntryTests = ($CurrentCall.TransTableEntryTests + $TransTableEntryTest.groups[1].value)
        }

        }

        #break down the rule test into individual tests based on "Performing OPTIONAL transformation using entry CN-ShortDial 9 (3.1(1))."
        Foreach ($TransTableEntryTest in ($TransTableEntryTests.Matches))
        {
        $CurrentCall.TransTableEntryTests = ($CurrentCall.TransTableEntryTests + $TransTableEntryTest.groups[1].value)
        Write-UcmLog -Message "Translation Rule Tested: $($TransTableEntryTest.groups[1].value)" -Severity 1 -Component $function
        }
    #>
    #end transformation rules


    #region outbound call details
    
    
    #Find the Outbound Invite to grab the translated numbers
    #Split the raw call using the invite
    Write-Progress -Activity "Step $currentStep/$ProgressSteps" -Id 1 -Status 'Enumerating Invites' -PercentComplete ((($currentStep) / $ProgressSteps) * 100) ; $currentStep ++

    $RawInvites = $RawCall -split 'INVITE sip:' -notmatch '^$'
    
    #Set a flag to ensure we actually find the relevant invite
    $InviteFound = $False
    
    foreach ($rawInvite in $RawInvites) 
    {
      $currentStep = 12
      #Check the invite matches the known CallID
      #Check we actually have an invite
      if ($regex['CID'].Matches($rawInvite).count -ne 0)
      {
        #Great, now lets get that Invite's CID and see if it matches the call we care about
        $InviteCID = ($regex['CID'].Matches($rawInvite)[0].groups[1].value) 
        Write-UcmLog -Message "Found Invite with the CID of $inviteCID" -Severity 1 -Component $function
        
        #Found the Invite we care about, lets grab the translated numbers (because they arent logged for some goddamn reason)
        if ($inviteCID -eq $CallID)
        {
          Write-UcmLog -Message 'Invite Matches Current Call' -Severity 1 -Component $function
          $InviteFound = $true
          Write-UcmLog -Message '## Translated Numbers' -Severity 1 -Component $function
          
          #Note, we arent looking for the "Invite SIP:" as we used that to split the content
          Write-Progress -Activity "Step $currentStep/$ProgressSteps" -Id 1 -Status 'Translated Calling Number' -PercentComplete ((($currentStep) / $ProgressSteps) * 100) ; $currentStep ++
      
          
          #This regex is really slow, I assume its parsing the entire invite instead of stopping as soon as a match is found
          #$TranslatedCallingNumber = ([regex]::Matches($rawInvite,'(.*)@').groups[1].value)
          
          #Faster Version
          $TranslatedCalledNumber = ((Select-String -InputObject $rawInvite -Pattern '(.*)@').matches.groups[1].value)
          
          Write-Progress -Activity "Step $currentStep/$ProgressSteps" -Id 1 -Status 'Translated Called Number' -PercentComplete ((($currentStep) / $ProgressSteps) * 100) ; $currentStep ++
      
          $TranslatedCallingNumber = ($regex['FromNumber'].Matches($rawInvite)[0].groups[1].value)
          Write-UcmLog -Message "Translated Called Number $TranslatedCalledNumber" -Severity 1 -Component $function
          Write-UcmLog -Message "Translated Calling Number $TranslatedCallingNumber" -Severity 1 -Component $function   
          $CurrentCall.TranslatedCallingNumber = $TranslatedCallingNumber
          $CurrentCall.TranslatedCalledNumber = $TranslatedCalledNumber
          
          #Find the Outbound Signalling Group
          Write-Progress -Activity "Step $currentStep/$ProgressSteps" -Id 1 -Status 'Locate Outbound Signaling Group' -PercentComplete ((($currentStep) / $ProgressSteps) * 100) ; $currentStep ++
          
          $OutboundSignallingGroup = ((Select-String -InputObject $RawCall -Pattern 'Number of SGs=., SGs={(.*) }').matches.groups[1].value)
          $CurrentCall.OutboundSignallingGroups = $OutboundSignallingGroup
          
          #Find if the call is re-routed
          Write-Progress -Activity "Step $currentStep/$ProgressSteps" -Id 1 -Status 'Re-Route Check' -PercentComplete ((($currentStep) / $ProgressSteps) * 100) ; $currentStep ++
          if ($RawCall -match 'Successful cause code reroute check')
          { 
            $Reroute = ((Select-String -InputObject $RawCall -Pattern 'Successful cause code reroute check with (.*)\n').matches.groups[1].value)
            $CurrentCall.CauseCodeReroute = $Reroute
            $ReRouteMatch = ($regex['TransTableSuccess'].Matches($RawCall)[1].groups[1].value)
            $CurrentCall.ReRouteMatch = $ReRouteMatch
            $Reroute = ''
            $ReRouteMatch = ''
          }

        }

        else
        {
          Write-UcmLog -Message 'Invite Doesnt Match Current Call, ignoring' -Severity 1 -Component $function
        }
      }
      
      #Handle any split objects before the first invite
      else
      {
        Write-UcmLog -Message 'RegEx result not an invite, ignoring' -Severity 1 -Component $function
      }
    }
    
    if ($InviteFound)
    {
      Write-UcmLog -Message "Found the Invite for $callID" -Severity 1 -Component $function  
    }
    
    else
    {
      Write-UcmLog -Message "Could not locate invite for CID $callID - Check $CallID.txt for call details" -Severity 3 -Component $function
      $RawCall | Out-File -FilePath "./$callid.txt"
      #pause
    }
    
    
    
    #Filtering Section
    
    # This needs to be cleaned up, but for now
    
    if ($OutboundSignallingGroups -ne '')
    {
     
      #check to see if the current call has the right signalling group
      if ($CurrentCall.outboundsignallinggroups -match $OutboundSignallingGroups)
      { 
        #Output the call details to the pipeline
        $CurrentCall
      }
    
    
    }
    else
    {
      #Output the call details to the pipeline
      $CurrentCall
    
    }
    
    
    
  }
  $CurrentCallNum ++
  
}
