param(
  [Parameter(Mandatory = $true)]
  [string]$CsvFilePath,   # 처리할 CSV 파일 경로 (필수, SubscriptionId/PrincipalObjectId/RoleDefinitionName/Scope 필수)

  [switch]$EnableWhatIf   # WhatIf 모드 스위치 (true면 실제 실행하지 않고 시뮬레이션만 수행)
)

# =====================================================================
# 일본 표준시(JST) 타임존 정보 준비
# =====================================================================
$jpTimeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById("Tokyo Standard Time")

# =====================================================================
# 타임스탬프 생성 및 로그/CSV 파일 경로 정의 (JST 기준)
# =====================================================================
$stamp = [System.TimeZoneInfo]::ConvertTime((Get-Date), $jpTimeZone).ToString("yyyyMMdd-HHmmss")
$logFilePath = "RoleAssignments.backout.$stamp.log"

# =====================================================================
# 로그 메시지 작성 함수 (JST 기준 시간)
# =====================================================================
function Write-LogMessage {
  param ([string]$Message)
  $jpTimeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById("Tokyo Standard Time")
  $timestamp = [System.TimeZoneInfo]::ConvertTime((Get-Date), $jpTimeZone).ToString("yyyy-MM-dd HH:mm:ss")
  $entry = "$timestamp - $Message"
  Write-Host $entry
  Add-Content -Path $logFilePath -Value $entry
}

# =====================================================================
# 결과 CSV 경로 생성 함수 (전체/실패 전용, JST 타임스탬프 사용)
# =====================================================================
function Get-ResultCsvPath {
  param([string]$SourceCsvPath)
  $jpTimeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById("Tokyo Standard Time")
  $dir = Split-Path -Parent $SourceCsvPath
  if (-not $dir -or $dir -eq "") {
    $dir = $PSScriptRoot
  }
  $base = Split-Path -Leaf  $SourceCsvPath
  $name = [System.IO.Path]::GetFileNameWithoutExtension($base)
  $ext = [System.IO.Path]::GetExtension($base)
  $stamp = [System.TimeZoneInfo]::ConvertTime((Get-Date), $jpTimeZone).ToString("yyyyMMdd-HHmmss")
  return (Join-Path $dir "$name.backout.with-results.$stamp$ext")
}
function Get-FailedCsvPath {
  param([string]$SourceCsvPath)
  $jpTimeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById("Tokyo Standard Time")
  $dir = Split-Path -Parent $SourceCsvPath
  if (-not $dir -or $dir -eq "") {
    $dir = $PSScriptRoot
  }
  $base = Split-Path -Leaf  $SourceCsvPath
  $name = [System.IO.Path]::GetFileNameWithoutExtension($base)
  $ext = [System.IO.Path]::GetExtension($base)
  $stamp = [System.TimeZoneInfo]::ConvertTime((Get-Date), $jpTimeZone).ToString("yyyyMMdd-HHmmss")
  return (Join-Path $dir "$name.backout.failed-only.$stamp$ext")
}

# =====================================================================
# 입력 CSV 로드
# =====================================================================
# 파일명에 "for-compare"가 포함되어 있으면 스크립트 즉시 종료
if ($CsvFilePath -match "for-compare") {
  Write-LogMessage "CsvFilePath contains 'for-compare'. Script terminated: $CsvFilePath"
  exit 1
}

# CsvFilePath 인자가 단순 파일명일 경우, 스크립트 폴더 기준으로 보정
if (-not (Split-Path -Parent $CsvFilePath)) {
  $CsvFilePath = Join-Path $PSScriptRoot $CsvFilePath
}
if (-not (Test-Path $CsvFilePath)) {
  throw "CSV file not found: $CsvFilePath"
}
$inputRows = Import-Csv -Path $CsvFilePath
if (-not $inputRows -or $inputRows.Count -eq 0) {
  throw "No rows to process in CSV: $CsvFilePath"
}

# [ADD] ----------------------------------------------------------------
# 실행별 보관 디렉토리 생성 (홈 디렉터리 하위에 run.backout.<stamp>)
$RunOutputDir = Join-Path $HOME ("run.backout." + $stamp)
New-Item -ItemType Directory -Path $RunOutputDir -Force | Out-Null

# 로그 파일을 보관 디렉토리로 이동(경로만 재지정; 기존 변수명/함수 변경 없음)
$logFilePath = Join-Path $RunOutputDir (Split-Path -Leaf $logFilePath)
# ---------------------------------------------------------------------

# 필수 컬럼 체크
$required = @('SubscriptionId', 'PrincipalObjectId', 'RoleDefinitionName', 'Scope')
$missing = $required | Where-Object { $inputRows[0].PSObject.Properties.Name -notcontains $_ }
if ($missing.Count -gt 0) {
  throw "Missing required columns in CSV: $($missing -join ', ')"
}

# =====================================================================
# 결과 CSV 경로 준비
# =====================================================================
$resultCsvPath = Get-ResultCsvPath -SourceCsvPath $CsvFilePath
$failedCsvPath = Get-FailedCsvPath -SourceCsvPath $CsvFilePath

# [ADD] ----------------------------------------------------------------
# 결과 CSV들도 보관 디렉토리로 위치 재지정 (파일명은 기존 로직 그대로 유지)
$resultCsvPath = Join-Path $RunOutputDir (Split-Path -Leaf $resultCsvPath)
$failedCsvPath = Join-Path $RunOutputDir (Split-Path -Leaf $failedCsvPath)

Write-LogMessage "Run output directory: $RunOutputDir"
# ---------------------------------------------------------------------

Write-LogMessage "Result CSV (all): $resultCsvPath"
Write-LogMessage "Result CSV (failed-only): $failedCsvPath"

# 결과 누적 배열 (원본 컬럼 + 실행 결과 컬럼)
$rowsWithResults = @()

# 진행도 계산용
$totalRows = $inputRows.Count

# =====================================================================
# 메인 처리 루프 (CSV 순서대로) — 진행도 + RG 스코프 분기
# =====================================================================
for ($i = 0; $i -lt $totalRows; $i++) {
  $row = $inputRows[$i]
  $rowIndex = $i + 1

  # 원본 컬럼
  $subscriptionId = $row.SubscriptionId
  $PrincipalObjectId = $row.PrincipalObjectId
  $PrincipalName = $row.PrincipalName
  $roleDefinitionName = $row.RoleDefinitionName
  $scope = $row.Scope

  # 실행 메타데이터
  $executedAt = [System.TimeZoneInfo]::ConvertTime((Get-Date), $jpTimeZone).ToString("o")  # JST, ISO8601
  $startTime = Get-Date  # 경과 시간 계산용
  $stdAll = $null
  $exitCode = $null
  $result = $null

  # 실행할 Azure CLI 명령어 (삭제 스크립트와 동일한 스코프 분기/형식)
  $commandToRun = "az role assignment create --assignee `"$PrincipalObjectId`" --role `"$roleDefinitionName`" --scope `"$scope`" --subscription $subscriptionId"

  if ($EnableWhatIf) {
    # WhatIf 모드: 실제 실행하지 않음
    $result = "WhatIf"
    $exitCode = ""
    $stdAll = "[WhatIf] Command not executed."
    Write-LogMessage "[WhatIf] $commandToRun"
  }
  else {
    # 실제 실행: 표준출력+에러 모두 캡처
    $stdAll = Invoke-Expression "$commandToRun 2>&1"
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
      $result = "Success"
      Write-LogMessage "Processing Row [$rowIndex/$totalRows] CREATE succeeded: $PrincipalName | $roleDefinitionName | $scope"
    }
    else {
      $result = "Failed"
      Write-LogMessage "Processing Row [$rowIndex/$totalRows] CREATE failed (ExitCode=$exitCode): $PrincipalName | $roleDefinitionName | $scope"
    }
  }

  # 실행 시간(ms)
  $durationMs = [int]((Get-Date) - $startTime).TotalMilliseconds

  # 원본 행 + 실행 결과 컬럼 합쳐서 새 객체 생성
  $rowWithResult = [pscustomobject]@{}
  foreach ($col in $row.PSObject.Properties.Name) {
    $rowWithResult | Add-Member -NotePropertyName $col -NotePropertyValue $row.$col
  }

  # 추가할 결과 컬럼 정의 (항상 덮어쓰기)
  $extraColumns = @(
    @{ Name = "ExecutedAt"; Value = $executedAt },
    @{ Name = "DurationMs"; Value = $durationMs },
    @{ Name = "Result"; Value = $result },
    @{ Name = "ExitCode"; Value = $exitCode },
    @{ Name = "CommandLine"; Value = $commandToRun },
    @{ Name = "StdAll"; Value = ($stdAll -join "`n") }
  )

  foreach ($colDef in $extraColumns) {
    # 덮어쓰기 모드: 기존 속성이 있든 없든 무조건 갱신
    $rowWithResult | Add-Member -NotePropertyName $colDef.Name -NotePropertyValue $colDef.Value -Force
  }

  # 누적
  $rowsWithResults += $rowWithResult
}

# =====================================================================
# 결과 CSV 저장 (전체 + 실패만)
# =====================================================================
# 1) 전체 결과
$rowsWithResults | Export-Csv -Path $resultCsvPath -NoTypeInformation -Encoding UTF8
Write-LogMessage "Saved result CSV (all): $resultCsvPath"

# 2) 실패만
$failedRows = $rowsWithResults | Where-Object { $_.Result -eq 'Failed' }
if ($failedRows -and $failedRows.Count -gt 0) {
  $failedRows | Export-Csv -Path $failedCsvPath -NoTypeInformation -Encoding UTF8
  Write-LogMessage "Saved result CSV (failed-only): $failedCsvPath (count: $($failedRows.Count))"
}
else {
  Write-LogMessage "No failed rows. Skipping failed-only CSV."
}
