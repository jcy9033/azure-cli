# Source resource variable
$rg_name = "system-1"
$vm_name = "azrwin-1"

# Replication resource variable
$location = "japaneast" 
$rep_rg_name = "system-2"
$rep_vm_names = @("azrwin-2", "azrwin-3")
$rep_vm_size = "Standard_DS1_v2"
$rep_disk_sku = "StandardSSD_LRS"
$rep_disk_size = 4
$rep_vnet_name = "system-2-vnet"
$rep_subnet_name = "subnet-1"
$rep_subnet_id = az network vnet subnet list --resource-group $rep_rg_name --vnet-name $rep_vnet_name --query "[?contains(name, '$rep_subnet_name')].id" -o tsv

# Get image definition ID
$img_def_id = az sig image-definition list --resource-group $rg_name --gallery-name 'win_gal' --query "[?contains(name, '$vm_name')].id" -o tsv

# Get snapshot IDs
$snapshot_ids = az snapshot list --resource-group $rg_name --query "[?contains(name, '$vm_name') && contains(name, 'DataDisk')].id" -o tsv | Out-String -Stream | ForEach-Object { $_.Trim() }

# Create disks and VMs for each replication VM name
foreach ($rep_vm_name in $rep_vm_names) {
  $data_disk_names = @()
  $i = 0

  # Create data disk for each snapshot
  $i = 0
  foreach ($snapshot_id in $snapshot_ids) {
    $data_disk_name = "${rep_vm_name}_DataDisk_$i"
    az disk create --resource-group $rep_rg_name `
      --name $data_disk_name `
      --sku $rep_disk_sku `
      --size-gb $rep_disk_size `
      --source $snapshot_id

    $data_disk_names += $data_disk_name
    $i++
  }

  # Create network interface card
  $rep_nic_name = "${rep_vm_name}-nic"
  az network nic create --resource-group $rep_rg_name `
    --name $rep_nic_name `
    --subnet $rep_subnet_id `
    --accelerated-networking true

  $rep_nic_id = az network nic list --query "[?name=='$rep_nic_name'].id" -o tsv

  # Create VM
  az vm create --resource-group $rep_rg_name `
    --name $rep_vm_name `
    --size $rep_vm_size `
    --image $img_def_id `
    --attach-data-disks $data_disk_names `
    --location $location `
    --admin-username "azureuser" `
    --admin-password "P@ssW0rd2024#01#21" `
    --nics $rep_nic_id `
    --security-type TrustedLaunch
}