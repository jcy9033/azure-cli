# 과제_20240319: 가상 네트워크, 네트워크 인터페이스 카드, 공개 IP주소 리소스 생성 제어
# 과제_20240319: 다른 구독에 배포

# 변수 정의
$SourceResourceGroupName = "system-1"
$SourceVmName = "azrsrv-1"
$CloneResourceGroupName = "system-2"
$CloneVmName = "azrsrv-1-clone"
$OsType = "windows"
$OsDiskSnapshotName = "$CloneVmName-osDisk-snapshot"
$OsDiskName = "$CloneVmName-osDisk"

# Azure CLI 명령 실행 및 출력을 변수에 저장
$DiskIds = Invoke-Expression "az vm show --resource-group $SourceResourceGroupName --name $SourceVmName --query [storageProfile.osDisk.managedDisk.id,storageProfile.dataDisks[*].managedDisk.id] --output tsv"

# 문자열을 배열로 변환 (모든 공백 문자를 기준으로 분할)
$DiskIdsArray = $DiskIds -split "\s+"

# OS 디스크와 데이터 디스크 ID를 각각의 변수에 할당
$OsDiskId = $DiskIdsArray[0]
Write-Output "OS_DISK_ID: $OsDiskId"

for ($i = 1; $i -lt $DiskIdsArray.Length; $i++) {
    # 변수 이름 생성 (예: DataDiskId1, DataDiskId2, ...)
    $VarName = "DataDiskId$i"

    # 변수가 이미 존재하는지 확인하고, 존재한다면 삭제
    Remove-Variable -Name $VarName -ErrorAction SilentlyContinue

    # 변수 할당
    New-Variable -Name $VarName -Value $DiskIdsArray[$i]

    # 생성된 변수와 값 출력
    $Value = (Get-Variable -Name $VarName).Value
    Write-Output "${VarName}: $Value"
}

# OS 디스크 스냅샷 생성
Invoke-Expression "az snapshot create --resource-group $CloneResourceGroupName --source $OsDiskId --name $OsDiskSnapshotName"

# OS 디스크 스냅샷으로부터 새 디스크 생성
Invoke-Expression "az disk create --resource-group $CloneResourceGroupName --name $OsDiskName --source $OsDiskSnapshotName"

# 새 VM 생성 및 OS 디스크 연결
Invoke-Expression "az vm create --resource-group $CloneResourceGroupName --name $CloneVmName --attach-os-disk $OsDiskName --os-type $OsType"

# 데이터 디스크 스냅샷 및 디스크 생성, VM에 마운트
for ($i = 1; $i -lt $DiskIdsArray.Length; $i++) {
    $DataDiskId = $DiskIdsArray[$i]
    $DataDiskSnapshotName = "$CloneVmName-dataDisk-$i-snapshot"
    $DataDiskName = "$CloneVmName-dataDisk-$i"

    # 데이터 디스크 스냅샷 생성
    Invoke-Expression "az snapshot create --resource-group $CloneResourceGroupName --source $DataDiskId --name $DataDiskSnapshotName"

    # 데이터 디스크 스냅샷으로부터 새 디스크 생성
    Invoke-Expression "az disk create --resource-group $CloneResourceGroupName --name $DataDiskName --source $DataDiskSnapshotName"

    # 새 디스크를 VM에 마운트
    Invoke-Expression "az vm disk attach --resource-group $CloneResourceGroupName --vm-name $CloneVmName --disk $DataDiskName"
}
