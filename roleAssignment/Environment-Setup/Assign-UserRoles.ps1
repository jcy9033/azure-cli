<# 
Assign-Roles.ps1
- 방금 만든 사용자들에게 구독 단위로 서로 다른 역할을 할당
- 기본은 10명의 유저에 대해 라운드로빈으로 역할 배분
- 필요 시 RoleMap으로 개별 매핑 가능 (예: 01은 Reader, 02는 Contributor ...)
#>

param (
  [int]$COUNT = 10,
  [string]$PREFIX = "testuser",
  [string]$DOMAIN = "jcy9033gmail489.onmicrosoft.com",
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

  # 개별 매핑(선택): 키는 "01","02" 처럼 2자리 인덱스, 값은 역할명
  # 비워두면 위의 $Roles 라운드로빈 적용
  [hashtable]$RoleMap = @{}
)

# 구독 컨텍스트 고정
az account set --subscription $SUBSCRIPTION_ID | Out-Null

for ($i = 1; $i -le $COUNT; $i++) {
  $index = $i.ToString("D2")                      # 01, 02, ...
  $UPN = "$PREFIX$index@$DOMAIN"

  # 사용자 Object ID 조회 (UPN 기준)
  $objectId = az ad user show `
    --id $UPN `
    --query id -o tsv 2>$null

  if (-not $objectId) {
    Write-Warning "사용자 조회 실패: $UPN (생성 전이거나 디렉터리 전파 지연 가능)"
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
    Write-Output "SKIP (이미 할당됨): $UPN -> $roleName @ $SUBSCRIPTION_ID"
    continue
  }

  # 역할 할당 (결과 활용)
  $ra = az role assignment create `
    --assignee-object-id $objectId `
    --role "$roleName" `
    --scope $scope `
    --query "{principalName:principalName, role:roleDefinitionName, scope:scope}" -o json 2>$null

  if ($LASTEXITCODE -eq 0) {
    $info = $ra | ConvertFrom-Json
    Write-Output "ASSIGNED: $UPN -> $($info.role) @ $SUBSCRIPTION_ID (scope: $($info.scope))"
  }
  else {
    Write-Warning "실패: $UPN -> $roleName @ $SUBSCRIPTION_ID"
  }
}
