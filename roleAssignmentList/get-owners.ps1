# Retrieve the list of subscription IDs
$subscriptionIds = az account list --query "[].id" -o tsv
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to retrieve subscriptionIds."
    return
}

$allAssignments = @()  # Array to store all role assignments

foreach ($subscriptionId in $subscriptionIds) {
    Write-Host "Subscription: $subscriptionId"

    # Get role assignments in JSON for parsing
    $roleAssignmentsJson = az role assignment list --role "Owner" --subscription $subscriptionId --output json
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed: $subscriptionId."
        continue
    }

    $assignments = $roleAssignmentsJson | ConvertFrom-Json
    if ($assignments) {
        $assignments | Format-Table principalName, roleDefinitionName, scope

        # Add to allAssignments for CSV export
        $allAssignments += $assignments
    }
}

# Export all results to CSV
if ($allAssignments.Count -gt 0) {
    $allAssignments |
        Select-Object principalName, roleDefinitionName, scope, principalType |
        Export-Csv -Path "RoleAssignments.csv" -NoTypeInformation -Encoding UTF8
    Write-Host "`nCSV exported to RoleAssignments.csv"
} else {
    Write-Host "No role assignments found to export."
}
