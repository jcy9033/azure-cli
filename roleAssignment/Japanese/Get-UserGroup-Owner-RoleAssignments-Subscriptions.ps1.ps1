# =====================================================================
# タイムスタンプ生成（CSV/LOG共通で使用）
# =====================================================================
$jpTimeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById("Tokyo Standard Time")
$stamp = [System.TimeZoneInfo]::ConvertTime((Get-Date), $jpTimeZone).ToString("yyyyMMdd-HHmmss")

# =====================================================================
# ログファイルパス（タイムスタンプ付き）
# =====================================================================
$logFilePath = "RoleAssignments.$stamp.log"

# =====================================================================
# ログメッセージ作成関数
# =====================================================================
function Write-LogMessage {
  param ([string]$logMessage)
  $jpTimeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById("Tokyo Standard Time")
  $timestamp = [System.TimeZoneInfo]::ConvertTime((Get-Date), $jpTimeZone).ToString("yyyy-MM-dd HH:mm:ss")
  $logEntry = "$timestamp - $logMessage"
  Write-Host $logEntry
  Add-Content -Path $logFilePath -Value $logEntry
}

# =====================================================================
# サブスクリプション一覧の取得（Id & Name）およびマッピングテーブル作成
# =====================================================================
$azureSubscriptionsJsonString = az account list --query "[].{Id:id,Name:name}" -o json
if ($LASTEXITCODE -ne 0) {
  Write-LogMessage "Failed to retrieve subscription list."
  return
}
$azureSubscriptionObjects = $azureSubscriptionsJsonString | ConvertFrom-Json
$azureSubscriptionIdList = $azureSubscriptionObjects.Id

# サブスクリプションID → サブスクリプション名のマッピングテーブルを作成
$azureSubscriptionIdToNameMap = @{}
foreach ($subscriptionObject in $azureSubscriptionObjects) {
  $azureSubscriptionIdToNameMap[$subscriptionObject.Id] = $subscriptionObject.Name
}

# =====================================================================
# 役割割り当て結果を保存する配列を初期化
# =====================================================================
$allUserGroupRoleAssignments = @()

foreach ($azureSubscriptionId in $azureSubscriptionIdList) {
  Write-LogMessage "Processing subscription: $azureSubscriptionId"

  # 役割割り当てを取得（JSON）
  $roleAssignmentsJsonString = az role assignment list --all --subscription $azureSubscriptionId --output json
  if ($LASTEXITCODE -ne 0) {
    Write-LogMessage "Failed to retrieve role assignments: $azureSubscriptionId"
    continue
  }

  # JSON → オブジェクト変換 & User/Groupのみフィルタリング（Owner除外、管理グループ継承除外）
  $filteredUserGroupRoleAssignments = $roleAssignmentsJsonString | ConvertFrom-Json | Where-Object {
    $_.principalType -in @("User", "Group") -and
    $_.roleDefinitionName -ne "Owner" -and
    $_.scope -like "/subscriptions/*"
  }

  if ($filteredUserGroupRoleAssignments) {
    # SubscriptionId/NameおよびPrincipalObjectId情報を追加
    $enrichedUserGroupRoleAssignments = $filteredUserGroupRoleAssignments | ForEach-Object {
      # ScopeからSubscriptionIdを抽出: /subscriptions/<id>/...
      $regexMatch = [regex]::Match($_.scope, '^/subscriptions/([^/]+)')
      $subscriptionIdFromScope = if ($regexMatch.Success) { $regexMatch.Groups[1].Value } else { $null }

      [pscustomobject]@{
        SubscriptionName   = $azureSubscriptionIdToNameMap[$subscriptionIdFromScope]
        SubscriptionId     = $subscriptionIdFromScope
        PrincipalName      = $_.principalName
        PrincipalObjectId  = $_.principalId
        RoleDefinitionName = $_.roleDefinitionName
        Scope              = $_.scope
        PrincipalType      = $_.principalType
      }
    }

    # ログ出力用テーブルフォーマット
    $tableOutputForLog = $enrichedUserGroupRoleAssignments |
    Format-Table SubscriptionName, SubscriptionId, PrincipalObjectId, PrincipalName, RoleDefinitionName, Scope, PrincipalType -AutoSize |
    Out-String
    Write-LogMessage "User/Group role assignments:`n$tableOutputForLog"

    # CSV出力用に累積
    $allUserGroupRoleAssignments += $enrichedUserGroupRoleAssignments
  }
  else {
    Write-LogMessage "No User/Group role assignments: $azureSubscriptionId"
  }
}

# =====================================================================
# CSVファイルパス定義（ログと同じタイムスタンプを使用）
# =====================================================================
$exportCsvFilePath = "RoleAssignments.$stamp.csv"

# =====================================================================
# 結果CSVのエクスポート
# =====================================================================
if ($allUserGroupRoleAssignments.Count -gt 0) {
  $allUserGroupRoleAssignments |
  Select-Object SubscriptionName, SubscriptionId, PrincipalName, PrincipalObjectId, RoleDefinitionName, Scope, PrincipalType |
  Export-Csv -Path $exportCsvFilePath -NoTypeInformation -Encoding UTF8

  Write-LogMessage "Exported to CSV: $exportCsvFilePath"
}
else {
  Write-LogMessage "No User/Group role assignments to export."
}
