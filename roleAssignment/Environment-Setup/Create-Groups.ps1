<#
Create-Groups.ps1
- 테스트용 그룹 10개 생성
#>

param (
  [int]$COUNT = 10,
  [string]$PREFIX = "testgroup",
  [string]$DOMAIN = "jcy9033gmail489.onmicrosoft.com"
)

for ($i = 1; $i -le $COUNT; $i++) {
    $index = "{0:D2}" -f $i
    $groupName = "$PREFIX$index"
    Write-Host "Creating Group: $groupName"

    az ad group create `
        --display-name $groupName `
        --mail-nickname $groupName `
        --description "Test group $index created via script"
}