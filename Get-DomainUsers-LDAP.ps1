<#
.SYNOPSIS
    Retrieves ALL user accounts from the current Active Directory domain
    using a native LDAP query (System.DirectoryServices.DirectorySearcher).
    Does NOT require the RSAT / ActiveDirectory PowerShell module.

.DESCRIPTION
    Run on a domain-joined machine. Uses the current logged-on user's
    credentials by default.
#>

# Optional: limit the search to a specific OU. Leave $null for the whole domain.
# Example: $searchBase = "OU=Employees,DC=contoso,DC=com"
$searchBase = $null

# Auto-detect the domain root DN (works on any domain, nothing to hardcode)
$rootDSE  = [ADSI]"LDAP://RootDSE"
$domainDN = $rootDSE.defaultNamingContext
if (-not $searchBase) { $searchBase = $domainDN }

# Build the LDAP searcher
$searcher = New-Object System.DirectoryServices.DirectorySearcher
$searcher.SearchRoot = [ADSI]"LDAP://$searchBase"

# LDAP filter for real user accounts (excludes computers and contacts).
# objectCategory=person is indexed -> faster than objectClass=user alone.
$searcher.Filter = "(&(objectCategory=person)(objectClass=user))"

# CRITICAL: without PageSize the query is capped at 1000 results.
# Setting it turns on paged search so every user is returned.
$searcher.PageSize = 1000

# Attributes to load (add or remove as you like)
"samAccountName","displayName","mail","distinguishedName","whenCreated","userAccountControl" |
    ForEach-Object { [void]$searcher.PropertiesToLoad.Add($_) }

# Run the query
$results = $searcher.FindAll()

# Shape each result into a clean object
$users = foreach ($r in $results) {
    $p = $r.Properties
    [PSCustomObject]@{
        SamAccountName    = $p["samaccountname"][0]
        DisplayName       = $p["displayname"][0]
        Email             = $p["mail"][0]
        WhenCreated       = $p["whencreated"][0]
        # userAccountControl bit 0x2 = ACCOUNTDISABLE
        Enabled           = -not ( [int]($p["useraccountcontrol"][0]) -band 2 )
        DistinguishedName = $p["distinguishedname"][0]
    }
}

# Release resources
$results.Dispose()
$searcher.Dispose()

# Show a quick table (full data is kept in $users)
$users | Sort-Object SamAccountName |
    Format-Table SamAccountName, DisplayName, Email, Enabled -AutoSize

Write-Host ("`nTotal users found: {0}" -f $users.Count) -ForegroundColor Cyan

# Optional: export everything to CSV on your Desktop
# $users | Sort-Object SamAccountName |
#     Export-Csv "$env:USERPROFILE\Desktop\DomainUsers.csv" -NoTypeInformation -Encoding UTF8
