param(
  [Parameter(Mandatory = $true)]
  [string]$CsvFilePath  # 対象のSubscriptionIdリストが含まれるCSVパス（ヘッダーにSubscriptionId必須）
)

# =====================================================================
# タイムスタンプ生成（CSV/LOG共通で使用）
# =====================================================================
$jpTimeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById("Tokyo Standard Time")
$stamp = [System.TimeZoneInfo]::ConvertTime((Get-Date), $jpTimeZone).ToString("yyyyMMdd-HHmmss")

# =====================================================================
# ログファイルパス（タイムスタンプ付き）
# =====================================================================
$logFilePath = "RoleAssignments.for-compare.$stamp.log"

# =====================================================================
# ログメッセージ作成関数（JST基準時間）
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
# 入力CSVの検証およびロード（SubscriptionIdを基準に収集）
# =====================================================================
if (-not (Test-Path $CsvFilePath)) {
  Write-LogMessage "CSV not found: $CsvFilePath"
  return
}
try {
  $csvRows = Import-Csv -Path $CsvFilePath
}
catch {
  Write-LogMessage "Failed to import CSV: $($_.Exception.Message)"
  return
}

if (-not $csvRows -or -not ($csvRows | Get-Member -Name SubscriptionId -MemberType NoteProperty)) {
  Write-LogMessage "CSV must contain a 'SubscriptionId' column."
  return
}

# CSVからSubscriptionIdのみを抽出（重複排除、空白/NULLを除外）
$azureSubscriptionIdList = $csvRows |
Where-Object { $_.SubscriptionId -and $_.SubscriptionId.Trim() -ne "" } |
ForEach-Object { $_.SubscriptionId.Trim() } |
Select-Object -Unique

if (-not $azureSubscriptionIdList -or $azureSubscriptionIdList.Count -eq 0) {
  Write-LogMessage "No SubscriptionId values found in CSV."
  return
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

$azureSubscriptionIdToNameMap = @{}
foreach ($subscriptionObject in $azureSubscriptionObjects) {
  $azureSubscriptionIdToNameMap[$subscriptionObject.Id] = $subscriptionObject.Name
}

# =====================================================================
# 役割割り当て結果を保存する配列を初期化
# =====================================================================
$allRoleAssignments = @()

foreach ($azureSubscriptionId in $azureSubscriptionIdList) {
  Write-LogMessage "Processing subscription from CSV: $azureSubscriptionId"

  try {
    # サブスクリプションのコンテキスト（アクティブサブスクリプション）を設定
    Set-AzContext -SubscriptionId $azureSubscriptionId -ErrorAction Stop | Out-Null
    
    # ロール割り当てを全件取得（継承分も含む）
    # ロール割り当てIDを取得するために Get-AzRoleAssignment を使用
    $roleAssignments = Get-AzRoleAssignment -IncludeClassicAdministrators -ErrorAction Stop
  }
  catch {
    Write-LogMessage "Failed processing subscription: $azureSubscriptionId - $($_.Exception.Message)"
    continue
  }

  if ($roleAssignments) {
    $enrichedRoleAssignments = $roleAssignments | ForEach-Object {
      [pscustomobject]@{
        RoleAssignmentId   = $_.RoleAssignmentName
        SubscriptionName   = if ($azureSubscriptionIdToNameMap.ContainsKey($azureSubscriptionId)) { 
          $azureSubscriptionIdToNameMap[$azureSubscriptionId] 
        }
        else { 
          "" 
        }
        SubscriptionId     = $azureSubscriptionId
        PrincipalName      = $_.DisplayName
        PrincipalObjectId  = $_.ObjectId
        RoleDefinitionName = $_.RoleDefinitionName
        Scope              = $_.Scope
        PrincipalType      = $_.ObjectType
      }
    }

    $tableOutputForLog = $enrichedRoleAssignments |
    Format-Table SubscriptionId, PrincipalName, RoleDefinitionName, Scope, PrincipalType -AutoSize | Out-String
    Write-LogMessage "Role assignments:`n$tableOutputForLog"

    $allRoleAssignments += $enrichedRoleAssignments
  }
  else {
    Write-LogMessage "No role assignments: $azureSubscriptionId"
  }
}

# =====================================================================
# CSVファイル出力
# =====================================================================
$exportCsvFilePath = "RoleAssignments.for-compare.$stamp.csv"
if ($allRoleAssignments.Count -gt 0) {
  $allRoleAssignments |
  Select-Object RoleAssignmentId, SubscriptionName, SubscriptionId, PrincipalName, PrincipalObjectId, RoleDefinitionName, Scope, PrincipalType |
  Export-Csv -Path $exportCsvFilePath -NoTypeInformation -Encoding UTF8

  Write-LogMessage "Exported to CSV: $exportCsvFilePath"
}
else {
  Write-LogMessage "No role assignments to export."
}
