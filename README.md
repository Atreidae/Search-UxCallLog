# 🔎 Search-UxCallLog.ps1

Search-UxCallLog.ps1 parses Sonus/Ribbon SBC UX logs and outputs call routing details to the PowerShell pipeline. It is designed to provide a lightweight alternative to LX for day-to-day troubleshooting.

## ❓ Why this exists

Pulling logs out of customer environments and opening LX just to inspect routing is a pain. This script makes it easy to understand which route/translation rules a call hit without extra tooling.

## ✅ Requirements

- Windows PowerShell or PowerShell 7
- Access to SBC WebUI.log files (or exported log bundles)

## 🧠 Terminology

Ribbon/Sonus routing typically flows in this order:

1. A call arrives on an inbound signalling group.
2. The SBC selects the associated Route Table.
3. Each **Route Table** entry references a **Translation Table**.
4. A **Translation Table** contains multiple **Translation Entries** (typically regex rules).
5. If all relevant entries match (e.g., called and calling), the **Translation Table** succeeds.
6. The first successful Translation Table determines the outbound route/signalling group.

**Remember:** It's very possible to have a **Translation Table Entry** match, but the **Translation Table** as a whole fails because not all the tests have passed (both called and calling for example)

In short:

Inbound Call → Route Table → Translation Table(s) → Translation Entry matches → Outbound route

- Translation Table Entry: A single regex rule that matches one attribute (e.g., called or calling).
- Translation Table: A set of entries; the table succeeds when all relevant entries match.
- Route Table: Maps inbound signalling groups to destination routes based on translation table results.

_I have tottally never ever gotten confused by this whilst writing this script /s_

## 🚀 Usage

### Parse a single log file (default is ./webui.log):

> Search-UxCallLog.ps1 -InputFile .\WebUI.log

### Parse all .log files in the current folder:

> Search-UxCallLog.ps1 -ParseFolder

### Parse all .log files in a specific folder:

> Search-UxCallLog.ps1 -ParseFolder -Path C:\Logs\SBC01

### Filter to calls routed to a specific signalling group and view in grid:

> Search-UxCallLog.ps1 -ParseFolder -OutboundSignallingGroups 2 | ogv

## ⚙️ Parameters

- InputFile
  The log file to process. Defaults to ./webui.log when not using -ParseFolder.

- ParseFolder
  When set, process all .log files in a folder (current folder by default).

- Path
  Optional path to parse when -ParseFolder is set. If omitted, the current working folder is used.

- OutboundSignallingGroups
  Filters output to calls routed to a specific signalling group ID.

## 🧾 Output

Each call is emitted as a PowerShell object with these properties:

### Call Details

- **CallID:** The SBC internal call ID (also visible in X-Sonus-Diagnostics headers).
- **CallTime:** Timestamp of the initial invite processing.
- **InviteLineNumber:** The line number where the SBC logged “Handling initial invite.” (can be inaccurate).

### Call Routing

- **RouteTable:** Route table used by the SBC for the inbound invite.
- **Unroutable:** Set to True if the SBC couldnt find a route for this call
- **OutboundSignallingGroups:** Destination signalling group selected for the call.
- **CauseCodeReRoute:** Cause code reroute result (or “No” if none).
- **ReRouteMatch:** Transformation table match for the re-routed call.
- **OriginalCallingNumber:** Calling party number as logged by the SBC.
- **OriginalCalledNumber:** Called party number as logged by the SBC.
- **TranslatedCallingNumber:** Calling party number used in the first outbound invite for this call.
- **TranslatedCalledNumber:** Called party number used in the first outbound invite for this call.

### Transformation Table Related

- **TransformationTableMatches:** Transformation tables that matched for the call.
- **TransformationTableFailures:** Transformation tables tested before the successful match.
- **TransformationRuleMatches:** Transformation rule entries that matched.
- **TransformationRuleFailures:** Transformation rule entries that were tested, but failed.
- **TransformationRuleSkips:** Transformation rule entries skipped because they’re disabled.
- **FinalTransformationRule:** The rule entry that caused the translation to succeed.



## ⚠️ Known issues

- Large volumes of simultaneous calls can confuse invite ordering.
- Call diversion invites are not handled correctly yet.
- If an invite cannot be found, the script exports that call to a text file for later review.
- Signalling Group filtering currently uses partial matches (IE: SG 1 may match SG11/12/13).
- Invite line numbers can be inaccurate.

## 🆘 Support

Issues and requests: [github.com/Atreidae/Search-UxCallLog/issues](https://github.com/Atreidae/Search-UxCallLog/issues/)
