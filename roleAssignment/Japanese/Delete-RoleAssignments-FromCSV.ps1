param(
  [Parameter(Mandatory = $true)]
  [string]$CsvFilePath,   # 処理するCSVファイルのパス（必須、SubscriptionId/PrincipalObjectId/RoleDefinitionName/Scope 必須）

  [switch]$EnableWhatIf   # WhatIfモードスイッチ（trueの場合、実際には実行せずシミュレーションのみ）
)

# =====================================================================
# 日本標準時（JST）タイムゾーン情報の準備
# =====================================================================
$jpTimeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById("Tokyo Standard Time")

# =====================================================================
# タイムスタンプ生成およびログ/CSVファイルパス定義（JST基準）
# =====================================================================
$stamp = [System.TimeZoneInfo]::ConvertTime((Get-Date), $jpTimeZone).ToString("yyyyMMdd-HHmmss")
$logFilePath = "RoleAssignments.delete.$stamp.log"

# =====================================================================
# ログメッセージ作成関数（JST基準時間）
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
# 結果CSVパス生成関数（全体/失敗専用、JSTタイムスタンプ使用）
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
  return (Join-Path $dir "$name.delete.with-results.$stamp$ext")
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
  return (Join-Path $dir "$name.delete.failed-only.$stamp$ext")
}

# =====================================================================
# 入力CSVのロード
# =====================================================================
# CsvFilePath引数に「for-compare」が含まれている場合、スクリプトを即時終了する
if ($CsvFilePath -match "for-compare") {
  Write-LogMessage "CsvFilePath contains 'for-compare'. Script terminated: $CsvFilePath"
  exit 1
}

# CsvFilePath引数が単純なファイル名の場合、スクリプトフォルダ基準で補正
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
# 実行ごとに保存ディレクトリを作成（CSVと同じフォルダ下に run.delete.<stamp>）
# 既存の変数/ロジックを変更せず、作成とパス再割り当てのみ実施
$__baseDir = Split-Path -Parent $CsvFilePath
if (-not $__baseDir -or $__baseDir -eq "") { $__baseDir = $PSScriptRoot }
$RunOutputDir = Join-Path $__baseDir ("run.delete." + $stamp)
New-Item -ItemType Directory -Path $RunOutputDir -Force | Out-Null

# ログファイルを保存ディレクトリに移動（パスのみ再指定、変数名/関数は変更なし）
$logFilePath = Join-Path $RunOutputDir (Split-Path -Leaf $logFilePath)
# ---------------------------------------------------------------------

# 必須カラムチェック
$required = @('SubscriptionId', 'PrincipalObjectId', 'RoleDefinitionName', 'Scope')
$missing = $required | Where-Object { $inputRows[0].PSObject.Properties.Name -notcontains $_ }
if ($missing.Count -gt 0) {
  throw "Missing required columns in CSV: $($missing -join ', ')"
}

# =====================================================================
# 結果CSVパスの準備
# =====================================================================
$resultCsvPath = Get-ResultCsvPath -SourceCsvPath $CsvFilePath
$failedCsvPath = Get-FailedCsvPath -SourceCsvPath $CsvFilePath

# [ADD] ----------------------------------------------------------------
# 結果CSVも保存ディレクトリに配置（ファイル名は既存ロジックを維持）
$resultCsvPath = Join-Path $RunOutputDir (Split-Path -Leaf $resultCsvPath)
$failedCsvPath = Join-Path $RunOutputDir (Split-Path -Leaf $failedCsvPath)

Write-LogMessage "Run output directory: $RunOutputDir"
# ---------------------------------------------------------------------

Write-LogMessage "Result CSV (all): $resultCsvPath"
Write-LogMessage "Result CSV (failed-only): $failedCsvPath"

# 結果累積配列（元のカラム＋実行結果カラム）
$rowsWithResults = @()

# 進行度計算用
$totalRows = $inputRows.Count

# =====================================================================
# メイン処理ループ（CSV順に処理）— 進行度＋リソースグループスコープ分岐
# =====================================================================
for ($i = 0; $i -lt $totalRows; $i++) {
  $row = $inputRows[$i]
  $rowIndex = $i + 1

  # 元のカラム
  $subscriptionId = $row.SubscriptionId
  $PrincipalObjectId = $row.PrincipalObjectId
  $PrincipalName = $row.PrincipalName
  $roleDefinitionName = $row.RoleDefinitionName
  $scope = $row.Scope

  # 実行メタデータ
  $executedAt = [System.TimeZoneInfo]::ConvertTime((Get-Date), $jpTimeZone).ToString("o")  # JST, ISO8601
  $startTime = Get-Date  # 経過時間計算用（UTC/JSTは不問）

  # スコープがリソースグループの場合 --resource-group を使用
  # 例: /subscriptions/<subId>/resourceGroups/<rgName>
  $useRgParam = $false
  $rgName = $null
  if ($scope -match '^/subscriptions/[^/]+/resourceGroups/([^/]+)/*$') {
    $useRgParam = $true
    $rgName = $Matches[1]
  }

  # 実行するAzure CLIコマンド
  if ($useRgParam -and $rgName) {
    # リソースグループ範囲
    $commandToRun = "az role assignment delete --assignee `"$PrincipalObjectId`" --role `"$roleDefinitionName`" --resource-group `"$rgName`" --subscription $subscriptionId"
  }
  else {
    # サブスクリプション/リソース範囲（既存方式）
    $commandToRun = "az role assignment delete --assignee `"$PrincipalObjectId`" --role `"$roleDefinitionName`" --scope `"$scope`" --subscription $subscriptionId"
  }

  $stdAll = $null
  $exitCode = $null
  $result = $null

  if ($EnableWhatIf) {
    # WhatIfモード：実際には実行しない
    $result = "WhatIf"
    $exitCode = ""
    $stdAll = "[WhatIf] Command not executed."
    Write-LogMessage "[WhatIf] $commandToRun"
  }
  else {
    # 実際に実行：標準出力＋エラーをすべてキャプチャ
    $stdAll = Invoke-Expression "$commandToRun 2>&1"
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
      $result = "Success"
      Write-LogMessage "Processing Row [$rowIndex/$totalRows] DELETE succeeded: $PrincipalName | $roleDefinitionName | $scope"
    }
    else {
      $result = "Failed"
      Write-LogMessage "Processing Row [$rowIndex/$totalRows] DELETE failed (ExitCode=$exitCode): $PrincipalName | $roleDefinitionName | $scope"
    }
  }

  # 実行時間（ms）
  $durationMs = [int]((Get-Date) - $startTime).TotalMilliseconds

  # 元の行＋実行結果カラムを結合した新しいオブジェクトを作成
  $rowWithResult = [pscustomobject]@{}
  foreach ($col in $row.PSObject.Properties.Name) {
    $rowWithResult | Add-Member -NotePropertyName $col -NotePropertyValue $row.$col
  }
  $rowWithResult | Add-Member -NotePropertyName ExecutedAt  -NotePropertyValue $executedAt
  $rowWithResult | Add-Member -NotePropertyName DurationMs  -NotePropertyValue $durationMs
  $rowWithResult | Add-Member -NotePropertyName Result      -NotePropertyValue $result
  $rowWithResult | Add-Member -NotePropertyName ExitCode    -NotePropertyValue $exitCode
  $rowWithResult | Add-Member -NotePropertyName CommandLine -NotePropertyValue $commandToRun
  $rowWithResult | Add-Member -NotePropertyName StdAll      -NotePropertyValue ($stdAll -join "`n")

  # 蓄積
  $rowsWithResults += $rowWithResult
}

# =====================================================================
# 結果CSVの保存（全体＋失敗のみ）
# =====================================================================
# 1) 全体結果
$rowsWithResults | Export-Csv -Path $resultCsvPath -NoTypeInformation -Encoding UTF8
Write-LogMessage "Saved result CSV (all): $resultCsvPath"

# 2) 失敗のみ
$failedRows = $rowsWithResults | Where-Object { $_.Result -eq 'Failed' }
if ($failedRows -and $failedRows.Count -gt 0) {
  $failedRows | Export-Csv -Path $failedCsvPath -NoTypeInformation -Encoding UTF8
  Write-LogMessage "Saved result CSV (failed-only): $failedCsvPath (count: $($failedRows.Count))"
}
else {
  Write-LogMessage "No failed rows. Skipping failed-only CSV."
}
