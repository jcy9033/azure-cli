# Please enter the file path for the CSV

$csvPath = "C:\Users\cchi9\OneDrive\Document\Azure DX Projects\CSV\Azure_ActivityLog_Alerts.csv"

$csvData = Import-Csv $csvPath -Encoding UTF8

$csvData | ForEach-Object {
  
  #----------------------------------------- Subscription check
  
  $TargetSubscription = $_.Subscription
  $ActiveSubscription = az account show --query name -o tsv
  
  if ($ActiveSubscription -eq $TargetSubscription) {
    Write-Host "---> Already on the target subscription: $TargetSubscription"
  }
  else {
    az account set --subscription $TargetSubscription
    Write-Host "---> Switched to the target subscription: $TargetSubscription"
  }
  
  #----------------------------------------- Action Group
  
  $ActionGroups = @()
  $i = 1
  while ($true) {
    $ActionGroupNameProperty = "ActionGroupName_$i"
  
    if ($_.PSObject.Properties.Name -contains $ActionGroupNameProperty) {
      $ActionGroupName = $_.$ActionGroupNameProperty
      Write-Host "---> ActionGroupName_$i is set to: $ActionGroupName"
      $ActionGroupJson = az graph query -q "Resources | where type == 'microsoft.insights/actiongroups' and name has '$ActionGroupName' | project id" | ConvertFrom-Json
  
      if ($ActionGroupJson.data -and $ActionGroupJson.data.Count -gt 0) {
        $ActionGroupId = $ActionGroupJson.data[0].id
        $ActionGroups += "$ActionGroupId"
      }
      else {
        Write-Host "---> No valid action group ID found for $ActionGroupName"
        break
      }
    }
    else {
      Write-Host "---> No more action groups to process for this object."
      break
    }
    $i++
  }

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

  Write-Host "---> Event status: $eventConditionString"

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
  Write-Host "---> Current resource status: $currentResourceConditionString"


  
  #----------------------------------------- Resource parameters

  $ResourceName = $_.ResourceName

  $ResourceType = (az resource list --query "[?name=='$ResourceName'].type" --output tsv).Trim()

  Write-Host "---> Resource type: $ResourceType"

  $ResourceId = (az resource list --query "[?name=='$ResourceName'].id" --output tsv).Trim()

  Write-Host "---> Resource scope: $ResourceId"

  #----------------------------------------- Create activity log alert
  
  az monitor activity-log alert create --name $_.AlertRuleName --resource-group $_.ResourceGroup  `
    --condition "category=ResourceHealth and $currentResourceConditionString and $eventConditionString and resourceType=$ResourceType and resourceId=$ResourceId" `
    --action-group $ActionGroups
}