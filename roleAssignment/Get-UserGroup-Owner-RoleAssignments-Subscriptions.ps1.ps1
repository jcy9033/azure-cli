# =====================================================================
# 타임스탬프 생성 (CSV/LOG 공통으로 사용)
# =====================================================================
$jpTimeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById("Tokyo Standard Time")
$stamp = [System.TimeZoneInfo]::ConvertTime((Get-Date), $jpTimeZone).ToString("yyyyMMdd-HHmmss")

# =====================================================================
# 로그 파일 경로 (타임스탬프 포함)
# =====================================================================
$logFilePath = "RoleAssignments.$stamp.log"

# =====================================================================
# 로그 메시지 작성 함수
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
# 구독 목록 조회 (Id & Name) 및 매핑 테이블 생성
# =====================================================================
$azureSubscriptionsJsonString = az account list --query "[].{Id:id,Name:name}" -o json
if ($LASTEXITCODE -ne 0) {
  Write-LogMessage "Failed to retrieve subscription list."
  return
}
$azureSubscriptionObjects = $azureSubscriptionsJsonString | ConvertFrom-Json
$azureSubscriptionIdList = $azureSubscriptionObjects.Id

# 구독 ID → 구독명 매핑 테이블 생성
$azureSubscriptionIdToNameMap = @{}
foreach ($subscriptionObject in $azureSubscriptionObjects) {
  $azureSubscriptionIdToNameMap[$subscriptionObject.Id] = $subscriptionObject.Name
}

# =====================================================================
# 역할 할당 결과를 저장할 배열 초기화
# =====================================================================
$allUserGroupRoleAssignments = @()

foreach ($azureSubscriptionId in $azureSubscriptionIdList) {
  Write-LogMessage "Processing subscription: $azureSubscriptionId"

  # 역할 할당 조회 (JSON)
  $roleAssignmentsJsonString = az role assignment list --all --subscription $azureSubscriptionId --output json
  if ($LASTEXITCODE -ne 0) {
    Write-LogMessage "Failed to retrieve role assignments: $azureSubscriptionId"
    continue
  }

  # JSON → 객체 변환 및 User/Group만 필터링 (Owner 제외, 관리 그룹 상속 제외)
  $filteredUserGroupRoleAssignments = $roleAssignmentsJsonString | ConvertFrom-Json | Where-Object {
    $_.principalType -in @("User", "Group") -and
    $_.roleDefinitionName -ne "Owner" -and
    $_.scope -like "/subscriptions/*"
  }

  if ($filteredUserGroupRoleAssignments) {
    # SubscriptionId/Name 및 PrincipalObjectId 정보 추가
    $enrichedUserGroupRoleAssignments = $filteredUserGroupRoleAssignments | ForEach-Object {
      # Scope에서 SubscriptionId 추출: /subscriptions/<id>/...
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

    # 로그 출력용 테이블 포맷
    $tableOutputForLog = $enrichedUserGroupRoleAssignments |
    Format-Table SubscriptionName, SubscriptionId, PrincipalObjectId, PrincipalName, RoleDefinitionName, Scope, PrincipalType -AutoSize |
    Out-String
    Write-LogMessage "User/Group role assignments:`n$tableOutputForLog"

    # CSV 내보내기용 누적
    $allUserGroupRoleAssignments += $enrichedUserGroupRoleAssignments
  }
  else {
    Write-LogMessage "No User/Group role assignments: $azureSubscriptionId"
  }
}

# =====================================================================
# CSV 파일 경로 정의 (로그와 동일한 타임스탬프 사용)
# =====================================================================
$exportCsvFilePath = "RoleAssignments.$stamp.csv"

# =====================================================================
# 결과 CSV 내보내기
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
