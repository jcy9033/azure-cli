# Variable
$resourcegroup = "chanpu-dev"
$vmname = "chanpu-vm"
$username = "azureuser"

# Create a virtual machine
az vm create `
  --resource-group $resourcegroup `
  --name $vmname `
  --image Win2022AzureEditionCore `
  --public-ip-sku Standard `
  --admin-username $username