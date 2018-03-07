#Requires -Version 3.0

Param(
    [string] $ResourceGroupLocation = "southcentralus",
    [string] $ResourceGroupName = 'Swarm-RG',
    [string] $TemplateFile = 'azuredeploy.json',
    [string] $TemplateParametersFile = 'azuredeploy.parameters-dev.json'
)
New-AzureRmResourceGroup -Name $ResourceGroupName -Location $ResourceGroupLocation -Verbose -Force
New-AzureRmResourceGroupDeployment -Name ((Get-ChildItem $TemplateFile).BaseName + '-' + ((Get-Date).ToUniversalTime()).ToString('MMdd-HHmm')) `
-ResourceGroupName $ResourceGroupName -TemplateFile $TemplateFile `
-TemplateParameterFile $TemplateParametersFile -Force -Verbose `
-ErrorVariable ErrorMessages -DeploymentDebugLogLevel All