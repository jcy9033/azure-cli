# Please enter the file path for the CSV
$csvPath = ""

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
  
  $ActionParams = @()
  $i = 1
  while ($true) {
    $ActionGroupNameProperty = "ActionGroupName_$i"
    
    if ($_.PSObject.Properties.Name -contains $ActionGroupNameProperty) {
      $ActionGroupName = $_.$ActionGroupNameProperty
      Write-Host "---> ActionGroupName_$i is set to: $ActionGroupName"
      $ActionGroupJson = az graph query -q "Resources | where type == 'microsoft.insights/actiongroups' and name has '$ActionGroupName' | project id" | ConvertFrom-Json
      
      if ($ActionGroupJson.data -and $ActionGroupJson.data.Count -gt 0) {
        $ActionGroupId = $ActionGroupJson.data[0].id
        $ActionParams += "--action", "$ActionGroupId"
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
  
  #----------------------------------------- Log query 
  
  $LogQuery = $_.LogQuery
  
  Write-Host "---> Condition Log Query: $LogQuery"

  #----------------------------------------- Conditions

  $Condition = "$($_.AggregationType) $($_.Measure) from 'LogQuery' $($_.Operator) $($_.Threshold)"

  Write-Host "---> Scheduled query alert condition: $Condition"

  #----------------------------------------- Resource parameters

  $ResourceName = $_.ResourceName
  
  $Scopes = (az resource list --query "[?name=='$ResourceName'].id" --output tsv).Trim()
    
  Write-Host "---> Resource scopes: $Scopes"
  
  #----------------------------------------- Create Scheduled query alert
  
  az monitor scheduled-query create --name $_.AlertRuleName --resource-group $_.ResourceGroup --scopes $Scopes `
    --severity $_.Severity `
    --condition "$Condition" `
    --condition-query LogQuery="$LogQuery" `
    --evaluation-frequency $_.EvaluationFrequency `
    --auto-mitigate $_.AutoMitigate `
    --window-size $_.WindowSize `
    --location $_.Location `
    $ActionParams
}

