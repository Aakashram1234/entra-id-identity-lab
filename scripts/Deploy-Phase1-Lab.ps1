<#
.SYNOPSIS
    Phase 1 deployment - Enterprise Identity Lab (Entra ID)
    Provisions: 15 test users across 3 departments, security groups (incl. one
    dynamic group), a break-glass emergency access account, and CA001
    (Require MFA for all users) in REPORT-ONLY mode.

.PREREQS
    - Connected to Microsoft Graph as a Global Administrator (PowerShell 7):
        Connect-MgGraph -Scopes "User.ReadWrite.All","Group.ReadWrite.All",
          "Policy.ReadWrite.ConditionalAccess","Policy.Read.All",
          "RoleManagement.ReadWrite.Directory"
    - Entra ID P2 trial active (needed for dynamic groups + Conditional Access).

.USAGE
    .\Deploy-Phase1-Lab.ps1

.NOTES
    Author: Aakash Ramamoorthy
    The break-glass password is printed ONCE at the end - store it offline.
#>

# ---------------------------------------------------------------------------
# 0. Confirm Graph connection and resolve tenant domain
# ---------------------------------------------------------------------------
$context = Get-MgContext
if (-not $context) {
    Write-Host "ERROR: Not connected to Microsoft Graph. Run Connect-MgGraph first." -ForegroundColor Red
    return
}

$tenantDomain = (Get-MgDomain | Where-Object { $_.IsInitial }).Id
Write-Host "`nConnected. Tenant domain: $tenantDomain" -ForegroundColor Cyan

# Helper: random strong password
function New-RandomPassword {
    $chars = ([char[]](48..57) + [char[]](65..90) + [char[]](97..122) + [char[]]"!@#%^*-_=+".ToCharArray())
    -join (1..24 | ForEach-Object { $chars | Get-Random })
}

# ---------------------------------------------------------------------------
# 1. Create 15 test users across IT, Finance, HR
#    The 'department' attribute drives the dynamic group later.
# ---------------------------------------------------------------------------
$users = @(
    @{ First="Priya";   Last="Sharma";    Dept="IT" },
    @{ First="Liam";    Last="OConnor";   Dept="IT" },
    @{ First="Mei";     Last="Chen";      Dept="IT" },
    @{ First="Daniel";  Last="Nguyen";    Dept="IT" },
    @{ First="Sofia";   Last="Rossi";     Dept="IT" },
    @{ First="James";   Last="Walker";    Dept="Finance" },
    @{ First="Anika";   Last="Patel";     Dept="Finance" },
    @{ First="Tom";     Last="Reilly";    Dept="Finance" },
    @{ First="Hana";    Last="Sato";      Dept="Finance" },
    @{ First="George";  Last="Iliou";     Dept="Finance" },
    @{ First="Zara";    Last="Hussain";   Dept="HR" },
    @{ First="Ben";     Last="Carter";    Dept="HR" },
    @{ First="Ling";    Last="Wang";      Dept="HR" },
    @{ First="Olivia";  Last="Brown";     Dept="HR" },
    @{ First="Marco";   Last="Silva";     Dept="HR" }
)

$createdUsers = @()
Write-Host "`n[1/4] Creating $($users.Count) test users..." -ForegroundColor Yellow

foreach ($u in $users) {
    $upn = ("{0}.{1}@{2}" -f $u.First, $u.Last, $tenantDomain).ToLower()
    $existing = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "  = Exists, skipping: $upn"
        $createdUsers += $existing
        continue
    }

    $passwordProfile = @{
        Password = New-RandomPassword
        ForceChangePasswordNextSignIn = $true
    }

    $newUser = New-MgUser `
        -DisplayName "$($u.First) $($u.Last)" `
        -GivenName $u.First `
        -Surname $u.Last `
        -UserPrincipalName $upn `
        -MailNickname ("$($u.First)$($u.Last)").ToLower() `
        -Department $u.Dept `
        -UsageLocation "AU" `
        -AccountEnabled `
        -PasswordProfile $passwordProfile

    $createdUsers += $newUser
    Write-Host "  + Created: $upn  (Dept: $($u.Dept))"
}

# ---------------------------------------------------------------------------
# 2. Create groups
#    - sg-it, sg-hr        : assigned (static) security groups
#    - sg-finance-dynamic  : DYNAMIC group, membership rule on department
# ---------------------------------------------------------------------------
Write-Host "`n[2/4] Creating security groups..." -ForegroundColor Yellow

function Get-OrCreateStaticGroup {
    param($Name, $Description)
    $g = Get-MgGroup -Filter "displayName eq '$Name'" -ErrorAction SilentlyContinue
    if ($g) { Write-Host "  = Exists, skipping: $Name"; return $g }
    $g = New-MgGroup -DisplayName $Name -Description $Description `
        -MailEnabled:$false -MailNickname $Name -SecurityEnabled:$true
    Write-Host "  + Created static group: $Name"
    return $g
}

$sgIT = Get-OrCreateStaticGroup -Name "sg-it" -Description "IT department staff"
$sgHR = Get-OrCreateStaticGroup -Name "sg-hr" -Description "HR department staff"

# Populate static groups from the department attribute
foreach ($user in $createdUsers) {
    $detail = Get-MgUser -UserId $user.Id -Property "id,department"
    switch ($detail.Department) {
        "IT" { try { New-MgGroupMember -GroupId $sgIT.Id -DirectoryObjectId $user.Id -ErrorAction Stop } catch {} }
        "HR" { try { New-MgGroupMember -GroupId $sgHR.Id -DirectoryObjectId $user.Id -ErrorAction Stop } catch {} }
    }
}
Write-Host "  + Populated sg-it and sg-hr from department attribute"

# Dynamic group - requires Entra ID P1/P2. Membership maintained automatically.
$dynName = "sg-finance-dynamic"
$dynGroup = Get-MgGroup -Filter "displayName eq '$dynName'" -ErrorAction SilentlyContinue
if (-not $dynGroup) {
    $dynGroup = New-MgGroup -DisplayName $dynName `
        -Description "Dynamic membership: all users with department = Finance" `
        -MailEnabled:$false -MailNickname $dynName -SecurityEnabled:$true `
        -GroupTypes @("DynamicMembership") `
        -MembershipRule 'user.department -eq "Finance"' `
        -MembershipRuleProcessingState "On"
    Write-Host "  + Created DYNAMIC group: $dynName"
} else {
    Write-Host "  = Exists, skipping: $dynName"
}

# ---------------------------------------------------------------------------
# 3. Break-glass emergency access account
#    Excluded from all CA policies. Global Administrator. Password printed
#    once - store offline (e.g. password manager vault).
# ---------------------------------------------------------------------------
Write-Host "`n[3/4] Creating break-glass account..." -ForegroundColor Yellow

$bgUpn = "bg-admin@$tenantDomain"
$bgPassword = New-RandomPassword
$bgUser = Get-MgUser -Filter "userPrincipalName eq '$bgUpn'" -ErrorAction SilentlyContinue

if (-not $bgUser) {
    $bgPasswordProfile = @{
        Password = $bgPassword
        ForceChangePasswordNextSignIn = $false
    }

    $bgUser = New-MgUser `
        -DisplayName "Break-Glass Emergency Access" `
        -UserPrincipalName $bgUpn `
        -MailNickname "bg-admin" `
        -UsageLocation "AU" `
        -AccountEnabled `
        -PasswordProfile $bgPasswordProfile
    Write-Host "  + Created: $bgUpn"

    $gaRole = Get-MgDirectoryRole -Filter "displayName eq 'Global Administrator'" -ErrorAction SilentlyContinue
    if (-not $gaRole) {
        $template = Get-MgDirectoryRoleTemplate | Where-Object { $_.DisplayName -eq "Global Administrator" }
        $gaRole = New-MgDirectoryRole -RoleTemplateId $template.Id
    }
    $memberRef = @{ "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($bgUser.Id)" }
    New-MgDirectoryRoleMemberByRef -DirectoryRoleId $gaRole.Id -BodyParameter $memberRef
    Write-Host "  + Assigned Global Administrator to break-glass account"
} else {
    Write-Host "  = Exists, skipping: $bgUpn"
    $bgPassword = "(unchanged - existing account)"
}

# ---------------------------------------------------------------------------
# 4. CA001 - Require MFA for all users (REPORT-ONLY)
#    Break-glass account is EXCLUDED.
# ---------------------------------------------------------------------------
Write-Host "`n[4/4] Creating Conditional Access policy CA001 (report-only)..." -ForegroundColor Yellow

$caName = "CA001 - Require MFA for all users"
$existingCA = Get-MgIdentityConditionalAccessPolicy -Filter "displayName eq '$caName'" -ErrorAction SilentlyContinue

if (-not $existingCA) {
    $caParams = @{
        DisplayName = $caName
        State       = "enabledForReportingButNotEnforced"
        Conditions  = @{
            Users = @{
                IncludeUsers = @("All")
                ExcludeUsers = @($bgUser.Id)
            }
            Applications = @{ IncludeApplications = @("All") }
        }
        GrantControls = @{
            Operator        = "OR"
            BuiltInControls = @("mfa")
        }
    }
    New-MgIdentityConditionalAccessPolicy -BodyParameter $caParams | Out-Null
    Write-Host "  + Created '$caName' in REPORT-ONLY mode (break-glass excluded)"
} else {
    Write-Host "  = Exists, skipping: $caName"
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host "`n========================= DEPLOYMENT COMPLETE =========================" -ForegroundColor Green
Write-Host " Users created/verified : $($createdUsers.Count)"
Write-Host " Groups                 : sg-it, sg-hr (static), sg-finance-dynamic (dynamic)"
Write-Host " Break-glass account    : $bgUpn"
Write-Host " Break-glass password   : $bgPassword"
Write-Host "                          ^^^ SHOWN ONCE. Store offline NOW. ^^^"
Write-Host " CA001                  : Require MFA for all users - REPORT-ONLY"
Write-Host ""
Write-Host " Next steps:"
Write-Host "   1. Sign in as a test user, then review Entra > Sign-in logs >"
Write-Host "      'Report-only' tab to see what CA001 would have done."
Write-Host "   2. Once validated, set CA001 to Enabled."
Write-Host "   3. Screenshot everything for docs/phase1-access-management.md."
Write-Host "========================================================================"
