# Please enter the file path for the CSV
$csvPath = "C:\Users\cchi9\OneDrive\Document\Azure DX Projects\CSV\Azure_Metric_Alerts.csv"

$csvData = Import-Csv $csvPath -Encoding UTF8

$i = 1

$csvData | ForEach-Object {
  
  #----------------------------------------- Subscription Check
  
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
  
  $first = $true

  foreach ($ActionGroup in $ActionGroupList) {
    $ActionGroupJson = az graph query -q "Resources | where type == 'microsoft.insights/actiongroups' and name has '$ActionGroup' | project id" | ConvertFrom-Json
  
    if ($ActionGroupJson.data -and $ActionGroupJson.data.Count -gt 0) {
      $ActionGroupId = $ActionGroupJson.data[0].id
    
      if ($first) {
        $ActionGroups += "$ActionGroupId"
        $first = $false
      }
      else {
        $ActionGroups += "--action", "$ActionGroupId"
      }
    }
    else {
      Write-Host "[Warning] No valid action group ID found for $ActionGroup"
    }
  }

  Write-Host "[Info] Action groups parameter: $ActionGroups"
  
  #----------------------------------------- Resource parameters

  $ResourceName = $_.ResourceName
  
  $Scopes = (az resource list --query "[?name=='$ResourceName'].id" --output tsv).Trim()
  
  Write-Host "[Info] Resource scopes: $Scopes"
  
  #----------------------------------------- Metric conditions
  
  $Condition = (az monitor metrics alert condition create --output tsv `
      --aggregation $_.Aggregation `
      --metric $_.Metric `
      --operator $_.Operator `
      --type $_.Type `
      --threshold $_.Threshold  2>$null | Out-String).Trim() 
      
  Write-Host "[Info] Metric alert condition: $Condition"

  #----------------------------------------- Create metric alert
  
  az monitor metrics alert create --name $_.AlertRuleName --resource-group $_.ResourceGroup --scopes $Scopes `
    --severity $_.Severity `
    --condition $Condition `
    --action $ActionGroups `
    --auto-mitigate true `
    --evaluation-frequency $_.EvaluationFrequency `
    --window-size $_.WindowSize

  $i++  
}

Write-Host "----------# [All done: $(Get-Date)]"