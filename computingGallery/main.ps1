# Variables
$galleryName = "chanpuGal"
$resourceGroup = "chanpu-dev"
$publisherUri = "https://www.engineer-chanpu.com"
$publisherEmail = "cchi9033@outlook.com"
$eulaLink = "https://www.engineer-chanpu.com/eula"
$prefix = "azureImages"

# Create
az sig create `
  --gallery-name $galleryName `
  --permissions community `
  --resource-group $resourceGroup `
  --publisher-uri $publisherUri `
  --publisher-email $publisherEmail `
  --eula $eulaLink `
  --public-name-prefix $prefix
