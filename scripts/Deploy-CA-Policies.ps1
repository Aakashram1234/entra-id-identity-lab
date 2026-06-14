# ============================================================
# Deploy-CA-Policies.ps1
# Phase 1 - Conditional Access policies CA002, CA003, CA004
# All created in REPORT-ONLY mode. Break-glass account excluded.
#
# Prereq: connected to Microsoft Graph (PowerShell 7) as Global Admin with:
#   Connect-MgGraph -UseDeviceCode -Scopes "User.ReadWrite.All",`
#     "Group.ReadWrite.All","Policy.ReadWrite.ConditionalAccess",`
#     "Policy.Read.All","Policy.ReadWrite.SecurityDefaults",`
#     "RoleManagement.ReadWrite.Directory","Domain.Read.All"
#   (Security defaults must be disabled before custom CA policies will enforce.)
# ============================================================

# --- Break-glass account (excluded from every policy) ---
$breakGlassUpn = "bg-admin@aakashram588gmail.onmicrosoft.com"
try {
    $bg = Get-MgUser -Filter "userPrincipalName eq '$breakGlassUpn'" -ErrorAction Stop
    $breakGlassId = $bg.Id
    Write-Host "[OK] Break-glass account found: $breakGlassUpn ($breakGlassId)" -ForegroundColor Green
} catch {
    Write-Host "[FATAL] Could not find break-glass account. Aborting to avoid a lockout-risk policy." -ForegroundColor Red
    return
}

# ===== CA002 - Block legacy authentication =====
try {
    $ca002 = @{
        DisplayName = "CA002 - Block legacy authentication"
        State = "enabledForReportingButNotEnforced"
        Conditions = @{
            ClientAppTypes = @("exchangeActiveSync","other")
            Applications = @{ IncludeApplications = @("All") }
            Users = @{ IncludeUsers = @("All"); ExcludeUsers = @($breakGlassId) }
        }
        GrantControls = @{ Operator = "OR"; BuiltInControls = @("block") }
    }
    $r = New-MgIdentityConditionalAccessPolicy -BodyParameter $ca002
    Write-Host "[OK] CA002 created (report-only): $($r.Id)" -ForegroundColor Green
} catch { Write-Host "[ERROR] CA002 failed: $($_.Exception.Message)" -ForegroundColor Red }

# ===== CA003 - Require MFA for admin / privileged roles =====
try {
    $adminRoleIds = @(
        "62e90394-69f5-4237-9190-012177145e10", # Global Administrator
        "e8611ab8-c189-46e8-94e1-60213ab1f814", # Privileged Role Administrator
        "194ae4cb-b126-40b2-bd5b-6091b380977d", # Security Administrator
        "b1be1c3e-b65d-4f19-8427-f6fa0d97feb9", # Conditional Access Administrator
        "fe930be7-5e62-47db-91af-98c3a49a38b1", # User Administrator
        "29232cdf-9323-42fd-ade2-1d097af3e4de", # Exchange Administrator
        "f28a1f50-f6e7-4571-818b-6a12f2af6b6c", # SharePoint Administrator
        "9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3", # Application Administrator
        "158c047a-c907-4556-b7ef-446551a6b5f7", # Cloud Application Administrator
        "729827e3-9c14-49f7-bb1b-9608f156bbb8", # Helpdesk Administrator
        "966707d0-3269-4727-9be2-8c3a10f19b9d", # Password Administrator
        "c4e39bd9-1100-46d3-8c65-fb160da0071f", # Authentication Administrator
        "b0f54661-2d74-4c50-afa3-1ec803f12efe"  # Billing Administrator
    )
    $ca003 = @{
        DisplayName = "CA003 - Require MFA for admins"
        State = "enabledForReportingButNotEnforced"
        Conditions = @{
            ClientAppTypes = @("all")
            Applications = @{ IncludeApplications = @("All") }
            Users = @{ IncludeRoles = $adminRoleIds; ExcludeUsers = @($breakGlassId) }
        }
        GrantControls = @{ Operator = "OR"; BuiltInControls = @("mfa") }
    }
    $r = New-MgIdentityConditionalAccessPolicy -BodyParameter $ca003
    Write-Host "[OK] CA003 created (report-only): $($r.Id)" -ForegroundColor Green
} catch { Write-Host "[ERROR] CA003 failed: $($_.Exception.Message)" -ForegroundColor Red }

# ===== CA004 - Block sign-ins from outside Australia =====
# Step 1: ensure an "Australia" country named location exists
# Step 2: policy blocks All locations EXCEPT Australia
# Note: a freshly created named location can hit eventual-consistency lag;
# if CA004 fails with "NamedLocation ... does not exist", re-run this block.
try {
    $existingLoc = Get-MgIdentityConditionalAccessNamedLocation -All | Where-Object { $_.DisplayName -eq "Australia" }
    if ($existingLoc) {
        $ausLocationId = $existingLoc.Id
        Write-Host "[OK] Australia named location already exists: $ausLocationId" -ForegroundColor Green
    } else {
        $locParams = @{
            "@odata.type" = "#microsoft.graph.countryNamedLocation"
            DisplayName = "Australia"
            CountriesAndRegions = @("AU")
            IncludeUnknownCountriesAndRegions = $false
        }
        $loc = New-MgIdentityConditionalAccessNamedLocation -BodyParameter $locParams
        $ausLocationId = $loc.Id
        Write-Host "[OK] Australia named location created: $ausLocationId" -ForegroundColor Green
    }

    $ca004 = @{
        DisplayName = "CA004 - Block sign-ins from outside Australia"
        State = "enabledForReportingButNotEnforced"
        Conditions = @{
            ClientAppTypes = @("all")
            Applications = @{ IncludeApplications = @("All") }
            Users = @{ IncludeUsers = @("All"); ExcludeUsers = @($breakGlassId) }
            Locations = @{ IncludeLocations = @("All"); ExcludeLocations = @($ausLocationId) }
        }
        GrantControls = @{ Operator = "OR"; BuiltInControls = @("block") }
    }
    $r = New-MgIdentityConditionalAccessPolicy -BodyParameter $ca004
    Write-Host "[OK] CA004 created (report-only): $($r.Id)" -ForegroundColor Green
} catch { Write-Host "[ERROR] CA004 failed: $($_.Exception.Message)" -ForegroundColor Red }

# ===== Summary =====
Write-Host ""
Write-Host "===== Conditional Access policies in tenant =====" -ForegroundColor Cyan
Get-MgIdentityConditionalAccessPolicy -All | Select-Object DisplayName, State | Sort-Object DisplayName | Format-Table -AutoSize
