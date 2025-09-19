<#
Assign-Roles-To-Groups.ps1
- Create-Groups.ps1로 만든 그룹들에 구독 단위 역할 할당
- 라운드로빈 또는 RoleMap으로 역할 배분
- 이미 동일 역할이 있으면 건너뜀(아이돔포턴시)
#>

param (
  [int]$COUNT = 10,
  [string]$PREFIX = "testgroup",
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

function Get-GroupObjectId {
  param([string]$GroupName)

  # 전파 지연 대비 최대 10회 재시도(3초 간격)
  for ($try = 1; $try -le 10; $try++) {
    # 방법 1: show
    $oid = az ad group show --group $GroupName --query id -o tsv 2>$null
    if ($oid) { return $oid }

    # 방법 2: list (display-name 기준)
    $oid = az ad group list --display-name $GroupName --query "[0].id" -o tsv 2>$null
    if ($oid) { return $oid }

    Start-Sleep -Seconds 3
  }
  return $null
}

for ($i = 1; $i -le $COUNT; $i++) {
  $index = "{0:D2}" -f $i
  $groupName = "$PREFIX$index"
  Write-Host "Processing Group: $groupName"

  $objectId = Get-GroupObjectId -GroupName $groupName
  if (-not $objectId) {
    Write-Warning "  ! 그룹 조회 실패(전파 지연/미생성 가능): $groupName"
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
    Write-Output "  - SKIP (이미 할당됨): $groupName -> $roleName @ $SUBSCRIPTION_ID"
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
    Write-Output "  - ASSIGNED: $($info.principalName) -> $($info.role) @ $SUBSCRIPTION_ID"
  }
  else {
    Write-Warning "  ! 할당 실패: $groupName -> $roleName @ $SUBSCRIPTION_ID"
  }
}
