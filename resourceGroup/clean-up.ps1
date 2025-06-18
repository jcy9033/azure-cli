# Specify the start string of the target resource group.
$startString = Read-Host -Prompt "Enter the start string of the Resource Group"

# List the target resource groups for deletion and highlight them with a different color.
az group list -o table | Select-String $startString | ForEach-Object { Write-Host $_ -ForegroundColor Red }

# Confirm whether to proceed with the resource group deletion.
$confirmation = Read-Host -Prompt "Do you want to execute the script? (Y/n)"

if ($confirmation -eq "Y") {
    # Place your script execution code here.
    Write-Host "Executing the script."

    # Get the names of all resource groups that start with 'chanpu-'.
    $rgsToDelete = az group list --query "[?starts_with(name, '$startString')].name" --output tsv

    # Iterate through each resource group, delete it, and create a new one with the same name.
    foreach ($rg in $rgsToDelete) {
        # Delete the resource group.
        az group delete --name $rg --yes --no-wait

        # Wait until the deletion is complete.
        Do {
            Start-Sleep -Seconds 5
            $status = az group exists --name $rg
        } While ($status -eq "true")

        # After deletion, create a new resource group with the same name.
        az group create --name $rg --location japaneast
    }
}
else {
    Write-Host "Not executing the script."
}
