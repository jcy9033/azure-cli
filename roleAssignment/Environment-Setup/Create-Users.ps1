param (
  [int]$COUNT = 10,
  [string]$PREFIX = "testuser",
  [string]$DOMAIN = "jcy9033gmail489.onmicrosoft.com",
  [string]$TEMP_PWD = "P@ssw0rd!"
)

for ($i = 1; $i -le $COUNT; $i++) {
  $index = $i.ToString("D2")  # 01, 02 형식
  $UPN = "$PREFIX$index@$DOMAIN"
  $DISPLAY = "Test User $index"
  $MAILNICK = "$PREFIX$index"

  az ad user create `
    --display-name $DISPLAY `
    --user-principal-name $UPN `
    --password $TEMP_PWD `
    --force-change-password-next-sign-in true `
    --mail-nickname $MAILNICK

  Write-Output "Created: $UPN"
}