param(
  [Parameter(Mandatory = $true)]
  [string]$CsvFilePath  # 대상 SubscriptionId 목록이 포함된 CSV 경로 (헤더에 SubscriptionId 필수)
)

# =====================================================================
# 타임스탬프 생성 (CSV/LOG 공통으로 사용)
# =====================================================================
$jpTimeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById("Tokyo Standard Time")
$stamp = [System.TimeZoneInfo]::ConvertTime((Get-Date), $jpTimeZone).ToString("yyyyMMdd-HHmmss")

# =====================================================================
# 로그 파일 경로 (타임스탬프 포함)
# =====================================================================
$logFilePath = "RoleAssignments.for-compare.$stamp.log"

# =====================================================================
# 로그 메시지 작성 함수 (JST 기준 시간)
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
# 입력 CSV 검증 및 로드 (SubscriptionId 기준 수집)
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

# CSV에서 SubscriptionId만 추출 (중복 제거, 공백/NULL 제외)
$azureSubscriptionIdList = $csvRows |
Where-Object { $_.SubscriptionId -and $_.SubscriptionId.Trim() -ne "" } |
ForEach-Object { $_.SubscriptionId.Trim() } |
Select-Object -Unique

if (-not $azureSubscriptionIdList -or $azureSubscriptionIdList.Count -eq 0) {
  Write-LogMessage "No SubscriptionId values found in CSV."
  return
}

# =====================================================================
# 구독 목록 (Id & Name) 조회 및 매핑 테이블 생성
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
# 역할 할당 결과를 저장할 배열 초기화
# =====================================================================
$allRoleAssignments = @()

foreach ($azureSubscriptionId in $azureSubscriptionIdList) {
  Write-LogMessage "Processing subscription from CSV: $azureSubscriptionId"

  try {
    # 구독 컨텍스트(Active Subscription) 설정
    Set-AzContext -SubscriptionId $azureSubscriptionId | Out-Null

    # 역할 할당 전체 조회 (상속 포함)
    # 역할 할당 ID를 가져오기 위해 Get-AzRoleAssignment 사용
    $roleAssignments = Get-AzRoleAssignment -IncludeClassicAdministrators
  }
  catch {
    Write-LogMessage "Failed to retrieve role assignments for: $azureSubscriptionId - $($_.Exception.Message)"
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
# CSV 파일 출력
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
