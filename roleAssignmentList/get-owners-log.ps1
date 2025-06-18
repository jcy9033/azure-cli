# 로그 파일 경로
$logFile = "RoleAssignments.log"

# 로그 작성 함수
function Write-Log {
    param (
        [string]$message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "$timestamp - $message"
    Write-Host $entry
    Add-Content -Path $logFile -Value $entry
}

# 기존 로그 파일 삭제(옵션)
if (Test-Path $logFile) {
    Remove-Item $logFile
}

# Retrieve the list of subscription IDs
$subscriptionIds = az account list --query "[].id" -o tsv
if ($LASTEXITCODE -ne 0) {
    Write-Log "Failed to retrieve subscriptionIds."
    return
}

$allAssignments = @()  # Array to store all role assignments

foreach ($subscriptionId in $subscriptionIds) {
    Write-Log "Subscription: $subscriptionId"

    # Get role assignments in JSON for parsing
    $roleAssignmentsJson = az role assignment list --role "Owner" --subscription $subscriptionId --output json
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Failed to retrieve role assignments for subscription: $subscriptionId"
        continue
    }

    $assignments = $roleAssignmentsJson | ConvertFrom-Json
    if ($assignments) {
        $tableOutput = $assignments | Format-Table principalName, roleDefinitionName, scope -AutoSize | Out-String
        Write-Log "Role Assignments:`n$tableOutput"

        # Add to allAssignments for CSV export
        $allAssignments += $assignments
    } else {
        Write-Log "No 'Owner' role assignments found for subscription: $subscriptionId"
    }
}

# Export all results to CSV
if ($allAssignments.Count -gt 0) {
    $allAssignments |
        Select-Object principalName, roleDefinitionName, scope, principalType |
        Export-Csv -Path "RoleAssignments.csv" -NoTypeInformation -Encoding UTF8
    Write-Log "CSV exported to RoleAssignments.csv"
} else {
    Write-Log "No role assignments found to export."
}
