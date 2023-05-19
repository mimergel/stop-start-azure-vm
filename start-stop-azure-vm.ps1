Param 
(    
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()] 
    [string]$AzureVMList,
    # DEV-WEEU-SAP01-HB2_hb2dhdb_z3_00l014a,DEV-WEEU-SAP01-HB2_hb2scs_z3_00l14a

    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()] 
    [string]$Action
)

# Remove quotes from $Action variable
$Action = $Action.Replace('"','')

# Remove blanks from $AzureVMList variable
$AzureVMList = $AzureVMList.Replace(' ','')

# Ensures you do not inherit an AzContext in your runbook
Disable-AzContextAutosave -Scope Process

# Connect to Azure with system-assigned managed identity
$AzureContext = (Connect-AzAccount -Identity).context

# Set and store context
$AzureContext = Set-AzContext -SubscriptionName $AzureContext.Subscription -DefaultProfile $AzureContext

# Prepare the list of virtual machines to handle
if($AzureVMList -eq "All") 
{ 
    $AzureVMs = (Get-AzVM).Name 
} 
elseif ($AzureVMList -match ',')
{ 
    $AzureVMs = $AzureVMList.Split(",") 
}
elseif ($AzureVMList) 
{ 
    $AzureVMs = $AzureVMList
} 

#[System.Collections.ArrayList]$AzureVMsToHandle = $AzureVMs 

# Loop through the virtual machines and perform the requested action
if($Action -contains 'stop')
{
    foreach ($VM in $AzureVMs) 
    {
        Write-Output "Stopping virtual machine $VM ..."
        Get-AzVM | ? {$_.Name -eq $VM} | Stop-AzVM -Force 
        
        Write-Output "Switching all disks to Standard HDD to benefit from additional savings during off-times ..."; 
        $vmResource = Get-AzResource -Name $VM
        $rgName = $vmResource.ResourceGroupName
        $vmDisks = Get-AzDisk -ResourceGroupName $rgName 
        $vmid = Get-AzVM -Name $VM -resourceGroupName $rgName
        foreach ($disk in $vmDisks)
        {
            if ($disk.ManagedBy -eq $vmid.Id)
            {
                $diskupdateconfig = New-AzDiskUpdateConfig -SkuName Standard_LRS
                Write-Output "Switching disk $disk.Name to Standard HDD"; 
                Update-AzDisk -ResourceGroupName $rgName -DiskName $disk.Name -DiskUpdate $diskupdateconfig 
            }
        }
    }
}
elseif($Action -contains 'start')
{
    foreach ($VM in $AzureVMs) 
    {
        Write-Output "Switching all disks of $VM to Premium SSD before startup to benefit from better performance ..."; 
        $vmResource = Get-AzResource -Name $VM
        $rgName = $vmResource.ResourceGroupName
        $vmDisks = Get-AzDisk -ResourceGroupName $rgName 
        $vmid = Get-AzVM -Name $VM -resourceGroupName $rgName
        foreach ($disk in $vmDisks)
        {
            if ($disk.ManagedBy -eq $vmid.Id)
            { 
                $diskupdateconfig = New-AzDiskUpdateConfig -SkuName Premium_LRS
                Write-Output "Switching disk $disk.Name to Premium_LRS"; 
                Update-AzDisk -ResourceGroupName $rgName -DiskName $disk.Name -DiskUpdate $diskupdateconfig 
            }
        }
        Write-Output "Starting virtual machine $VM ..."
        Get-AzVM | ? {$_.Name -eq $VM} | Start-AzVM 
    }
}
else
{
    Write-Output "Invalid action specified $Action. Valid actions are stop or start"
}
