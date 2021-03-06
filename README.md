# Search-UxCallLog.ps1

This is a tool to search through Sonus/Ribbon SBC call logs and display associated routing information

## DESCRIPTION

This tool does it's best to display call routes from Sonus/Ribbon UX logfiles in a friendly manner without needing tools like LX installed

## Why?

I got so sick and tired of firing up LX every single time a call went "awry" when customers called only to find someone else had re-installed LX on their profile causing the installation to break on mine
For people that only support a pair of SBC's maybe you can just run LX on your PC.. but for consultants, we have to get the files off the SBC.. then out of the customers environment and thats usualy a PITA. 
Needless to say, even with LX you still need to read all the ROUTE entries by hand anyway.

So I wrote this script to give everyone a simple way to see what rules calls are bouncing off to ease troubleshooting a bit.

## Build Status

#todo

## Tests

#todo

## Parameters

'InputFile' : The file to process, will default to Webut.log if not specified or not parsing the whole folder

'ParseFolder' : Will process every log file in the current directory, useful for audits before turning off signalling groups and avoiding scream tests

'OutboundSignallingGroups' : Will only show calls that match the outbound signalling group ID specified.
To get the Signalling Group ID, in your SBC navigate to Settings > Signalling Groups and checking the Primary Key for the group you are interested in.
![image](https://user-images.githubusercontent.com/8736291/162730272-bc3449f3-b352-4691-99ce-5254e28a72f8.png)


## Neat Tricks

Looking to find a call that ends routes to a certain signalling group? Use the OutboundSignallingGroup parameter!

`'C:\UcMadScientist\Search-UxCallLog\Search-UxCallLog.ps1' -ParseFolder -OutboundSignallingGroups 2 | ft`


Looking for a simple way to filter all the logs in a folder for a call? Just pipe it to PowerShell's Grid View cmdlet.

`Search-UxCallLog.ps1 -ParseFolder | ogv`

![image](https://user-images.githubusercontent.com/8736291/165226957-892cad57-e62a-4965-b990-65f91f618fde.png)




## Terminology

A quick one to alleviate any confusion if you havent done lots of TransTable work on a Sonus

A "Translation Table Entry" is a single RegEx rule that matches a single attribute, IE a Called Number or a Calling Number. but not both

A "Translation Table" contains multiple Table Entries and can have multiple *entries* match, if all the relevant properties match (IE, both called and calling) then the *table* is deemed sucsessful

A "Route Table" contains multiple Translation Tables, each mapping to a destination *signalling group* a route table is determined by the signalling group the call arrives on and the destination signalling group is determined by what *translation table* is successful first

## Output

Search-UxCallLog will presently output any found call details on the PowerShell Pipeline, each call is an object, with the following properties

'CallID' : The SBC's internal call ID for the found invite, can be found in the X-Sonus-Diagnostics headers in the Invite

'CallTime' : The time the SBC processed the initial invite

'InviteLineNumber' : The line number in the log that the SBC logged "Handling initial invite."

'OriginalCallingNumber' : The calling party's number as logged by the SBC

'OriginalCalledNumber' : The called party's number as logged by the SBC

'TranslatedCallingNumber' : The called party's number used in the first outbound Invite for the Call ID above

'TranslatedCalledNumber' : The calling party's number used in the first outbound Invite for the Call ID above

'RouteTable' : The route table used by the SBC for the inbound Invite

'TransTableMatches' : The Translation Table that caused the SBC to send a new outbound invite

'TransTableFailures' : The Translation Tables that were tested before the sucessful table was found

'TransTableEntrySkips' : The Translation Table Entries that were skipped because they are disabled.

'FinalTranslationRule' : The Translation Table Entry that caused the Translation Table to Succeed

'OutboundSignallingGroups' : This is currently a plain text string of all the signalling groups listed in the destination route. Will be updated to an array in a later release

'CauseCodeReRoute' : Returns what if any cause code rules were matched and what table the match was on. Otherwise returns "No"

'ReRouteMatch' : Returns the Translation Table match of the re-routed call.

![image](https://user-images.githubusercontent.com/8736291/162686383-86658675-9844-45f6-a871-8d788c50798c.png)


## Known issues

Large amounts of simultaneous calls can cause the script to get confused if invites are logged out of order

Call Diversion Invites arent handled properly

If the script presently cant find an appropriate call invite, it will export a text file of that call for later viewing

Check https://github.com/Atreidae/Search-UxCallLog/issues/ for more

Signalling Group matches dont search for the whole number (yet), so seaching for calls terminating on SG 1, will return calls on SG11, 12, 13 etc.
