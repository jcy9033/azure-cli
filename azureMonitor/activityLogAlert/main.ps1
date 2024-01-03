# Please enter the file path for the CSV

$csvPath = "C:\Users\cchi9\OneDrive\Document\Azure DX Projects\CSV\Azure_ActivityLog_Alerts.csv"

$csvData = Import-Csv $csvPath -Encoding UTF8

$i = 1

$csvData | ForEach-Object {
  
  #----------------------------------------- Subscription check
  
  Write-Host "----------# [Create No.$i : $(Get-Date)]"

  $TargetSubscription = $_.Subscription
  
  $ActiveSubscription = az account show --query name -o tsv
  
  if ($ActiveSubscription -eq $TargetSubscription) {
    Write-Host "[Info] Already on the target subscription: $TargetSubscription"
  }
  else {
    az account set --subscription $TargetSubscription
    Write-Host "[Info] Switched to the target subscription: $TargetSubscription"
  }
  
  #----------------------------------------- Action Group

  $ActionGroupName = $_.ActionGroupName

  $ActionGroupList = $ActionGroupName -split ';'
  
  Write-Host "[Info] Action group list: $ActionGroupList"

  $ActionGroups = @()
  
  foreach ($ActionGroup in $ActionGroupList) {
    $ActionGroupJson = az graph query -q "Resources | where type == 'microsoft.insights/actiongroups' and name has '$ActionGroup' | project id" | ConvertFrom-Json
  
    if ($ActionGroupJson.data -and $ActionGroupJson.data.Count -gt 0) {
      $ActionGroupId = $ActionGroupJson.data[0].id
      $ActionGroups += "$ActionGroupId"
    }
    else {
      Write-Host "[Warning] No valid action group ID found for $ActionGroup"
    }
  }

  Write-Host "[Info] Action groups parameter: $ActionGroups"

  #----------------------------------------- Event status conditions

  $eventStatusString = $_.EventStatus
  $eventStatuses = $eventStatusString -split ';'
  
  # Initialize the condition array
  $eventConditionArray = @()

  foreach ($eventStatus in $eventStatuses) {
    if ($eventStatus -ne "") {
      $eventConditionArray += "status=$eventStatus"
    }
  }

  # Join the condition array with ' and '
  $eventConditionString = $eventConditionArray -join " and "

  Write-Host "[Info] Event status: $eventConditionString"

  #----------------------------------------- Current resource status conditions

  # The input string of current resource statuses
  $currentResourceStatus = $_.CurrentResourceStatus

  # Split the string into an array by ';'
  $currentResourceStatuses = $currentResourceStatus -split ';'

  # Initialize the condition array
  $currentResourceConditionArray = @()

  foreach ($status in $currentResourceStatuses) {
    if ($status -ne "") {
      $currentResourceConditionArray += "properties.currentHealthStatus=$status"
    }
  }

  # Join the condition array with ' and '
  $currentResourceConditionString = $currentResourceConditionArray -join " and "

  # Output the condition string
  Write-Host "[Info] Current resource status: $currentResourceConditionString"

  #----------------------------------------- Resource parameters

  $ResourceName = $_.ResourceName

  $ResourceType = (az resource list --query "[?name=='$ResourceName'].type" --output tsv).Trim()

  Write-Host "[Info] Resource type: $ResourceType"

  $ResourceId = (az resource list --query "[?name=='$ResourceName'].id" --output tsv).Trim()

  Write-Host "[Info] Resource scope: $ResourceId"

  #----------------------------------------- Create activity log alert
  
  az monitor activity-log alert create --name $_.AlertRuleName --resource-group $_.ResourceGroup  `
    --condition "category=ResourceHealth and $eventConditionString and $currentResourceConditionString and resourceType=$ResourceType and resourceId=$ResourceId" `
    --action-group $ActionGroups
  
  $i++  
}

Write-Host "----------# [All done: $(Get-Date)]"