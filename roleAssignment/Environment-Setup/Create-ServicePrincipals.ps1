<#
Create-ServicePrincipals.ps1
- 테스트용 서비스 프린시펄 10개 생성 (역할 할당 없음)
#>

param (
  [int]$COUNT = 10,
  [string]$PREFIX = "testsp"
)

for ($i = 1; $i -le $COUNT; $i++) {
    $index = "{0:D2}" -f $i
    $spName = "$PREFIX$index"
    Write-Host "Creating Service Principal: $spName"

    az ad sp create-for-rbac `
        --name $spName
}