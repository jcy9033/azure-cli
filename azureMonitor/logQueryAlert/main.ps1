# Please enter the file path for the CSV
$csvPath = "C:\Users\cchi9\OneDrive\Document\Azure DX Projects\CSV\Azure_LogQuery_Alerts.csv"

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
  
  
  #----------------------------------------- Log query 
  
  $LogQuery = $_.LogQuery
  
  Write-Host "[Info] Condition Log Query: $LogQuery"

  #----------------------------------------- Conditions

  $Condition = "$($_.Aggregation) $($_.Measure) from 'LogQuery' $($_.Operator) $($_.Threshold)"

  Write-Host "[Info] Scheduled query alert condition: $Condition"

  #----------------------------------------- Resource parameters

  $ResourceName = $_.ResourceName
  
  $Scopes = (az resource list --query "[?name=='$ResourceName'].id" --output tsv).Trim()
    
  Write-Host "[Info] Resource scopes: $Scopes"
  
  #----------------------------------------- Create Scheduled query alert
  
  az monitor scheduled-query create --name $_.AlertRuleName --resource-group $_.ResourceGroup --scopes $Scopes `
    --severity $_.Severity `
    --condition "$Condition" `
    --condition-query LogQuery="$LogQuery" `
    --evaluation-frequency $_.EvaluationFrequency `
    --auto-mitigate $_.AutoMitigate `
    --window-size $_.WindowSize `
    --action-group $ActionGroups

  $i++  
}

Write-Host "----------# [All done: $(Get-Date)]"

