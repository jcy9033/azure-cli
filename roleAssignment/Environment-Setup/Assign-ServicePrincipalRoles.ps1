<#
Create-ServicePrincipals.ps1
- 테스트용 서비스 프린시펄 10개 생성 후 구독 단위 역할 할당
- 라운드로빈 또는 RoleMap으로 역할 배분
- 이미 존재하는 SP/역할은 건너뜀(아이돔포턴시)
#>

param (
  [int]$COUNT = 10,
  [string]$PREFIX = "testsp",
  [string]$SUBSCRIPTION_ID = "611a7ed8-17fa-480a-901d-d7084803c376",

  # 라운드로빈용 역할 목록 (원하는 대로 수정 가능)
  [string[]]$Roles = @(
    "Owner",
    "Contributor",
    "Virtual Machine Contributor",
    "Storage Blob Data Reader",
    "Network Contributor",
    "Monitoring Reader",
    "Billing Reader",
    "Security Reader",
    "Tag Contributor",
    "User Access Administrator"
  ),

  # 개별 매핑(선택): 키는 "01","02" (2자리 인덱스), 값은 역할명
  # 비워두면 위 $Roles 라운드로빈 적용
  [hashtable]$RoleMap = @{}
)

# 구독 컨텍스트 고정
az account set --subscription $SUBSCRIPTION_ID | Out-Null

function Get-SpObjectId {
  param([string]$AppId)
  # 전파 지연을 고려한 재시도
  for ($try = 1; $try -le 10; $try++) {
    $oid = az ad sp show --id $AppId --query id -o tsv 2>$null
    if ($oid) { return $oid }
    Start-Sleep -Seconds 3
  }
  return $null
}

for ($i = 1; $i -le $COUNT; $i++) {
  $index = "{0:D2}" -f $i
  $spName = "$PREFIX$index"
  Write-Host "Processing Service Principal: $spName"

  # SP 존재 여부 확인 (이름 기준 조회 → appId 추출)
  $existingAppId = az ad sp list `
    --display-name $spName `
    --query "[0].appId" -o tsv 2>$null

  if (-not $existingAppId) {
    Write-Host "  - Creating Service Principal (no role assignment yet): $spName"
    # 기본 역할 자동 부여를 방지하기 위해 --skip-assignment 사용
    $createJson = az ad sp create-for-rbac `
      --name $spName `
      --skip-assignment `
      -o json 2>$null

    if ($LASTEXITCODE -ne 0 -or -not $createJson) {
      Write-Warning "  ! 생성 실패: $spName"
      continue
    }

    $existingAppId = ($createJson | ConvertFrom-Json).appId
  }
  else {
    Write-Host "  - Exists: $spName (appId=$existingAppId)"
  }

  # Object ID 조회 (권한 할당에 필요)
  $objectId = Get-SpObjectId -AppId $existingAppId
  if (-not $objectId) {
    Write-Warning "  ! Object ID 조회 실패: $spName (appId=$existingAppId)"
    continue
  }

  # 역할 결정: RoleMap 우선, 없으면 라운드로빈
  if ($RoleMap.ContainsKey($index)) {
    $roleName = [string]$RoleMap[$index]
  }
  else {
    $roleName = $Roles[($i - 1) % $Roles.Count]
  }

  $scope = "/subscriptions/$SUBSCRIPTION_ID"

  # 이미 동일 역할이 있는지 확인(아이돔포턴시)
  $hasRole = az role assignment list `
    --assignee-object-id $objectId `
    --scope $scope `
    --query "[?roleDefinitionName=='$roleName'] | length(@)" -o tsv

  if ([int]$hasRole -gt 0) {
    Write-Output "  - SKIP (이미 할당됨): $spName -> $roleName @ $SUBSCRIPTION_ID"
    continue
  }

  # 역할 할당
  $ra = az role assignment create `
    --assignee-object-id $objectId `
    --role "$roleName" `
    --scope $scope `
    --query "{principalName:principalName, role:roleDefinitionName, scope:scope}" -o json 2>$null

  if ($LASTEXITCODE -eq 0) {
    $info = $ra | ConvertFrom-Json
    Write-Output "  - ASSIGNED: $spName ($($info.principalName)) -> $($info.role) @ $SUBSCRIPTION_ID"
  }
  else {
    Write-Warning "  ! 할당 실패: $spName -> $roleName @ $SUBSCRIPTION_ID"
  }
}
