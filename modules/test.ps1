$parameters = @{
    'Automation Account Name' = 'AutomationAccount'
}
New-AzureRmResourceGroupDeployment -TemplateFile .\deploymodule.json @parameters -Verbose -ResourceGroupName Utility-RG 