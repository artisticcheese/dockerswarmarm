$parameters = @{
    'Automation Account Name' = 'AzureAutomation'
}
New-AzureRmResourceGroupDeployment -TemplateFile .\deploymodule.json @parameters -Verbose -ResourceGroupName Utility-RG 