Configuration swarmhost
{
    param
    (
        [string] $clientCert = (Get-AutomationVariable -Name VMSSclientcert),
        [string] $clientKey = (Get-AutomationVariable -Name VMSSclientkey),
        [string] $CAcert = (Get-AutomationVariable -Name ca),
        [string] $SwarmManagerURI
    )
    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DSCResource -moduleName xNetworking
    Import-DscResource -ModuleName cChoco 
    Import-DSCResource -moduleName cDSCDockerSwarm

    Node localhost
    {
        Environment DockerCertpath {
            Name  = "DOCKER_CERT_PATH"
            Value = "c:\programdata\docker\clientcerts\"
        }

        cDockerSwarm Swarm {
            DependsOn       = @('[cDockerConfig]DaemonJson', "[File]ClientCert", "[File]ClientKey")
            SwarmMasterURI  = "$($SwarmManagerURI):2377"
            SwarmMode       = 'Active'
            ManagerCount    = 3
            SwarmManagement = 'Automatic'
        }
        cDockerConfig DaemonJson {
            Ensure          = 'Present'
            RestartOnChange = $false
            ExposeAPI       = $false
            EnableTLS       = $false
            Dependson       = @("[xFirewallProfile]DisablePublic", "[xFirewallProfile]DisablePublic")
        }

        cChocoInstaller installChoco {
            InstallDir = "c:\choco"
        }
        xFirewallProfile DisablePublic {
            Enabled = "False"
            Name    = "Public"
        }
        xFirewallProfile DisablePrivate {
            Enabled = "False"
            Name    = "Private"

        }
        cChocoPackageInstallerSet installSomeStuff {
            Ensure = 'Present'
            Name   = @(
                "classic-shell"
                "7zip"
                "visualstudiocode"
            )
            
        }
        File ClientCert {
            Destinationpath = "c:\programdata\docker\clientcerts\cert.pem"
            Contents        = $clientCert
            Force           = $true
        }
        File ClientKey {
            Destinationpath = "c:\programdata\docker\clientcerts\key.pem"
            Contents        = $clientKey
            Force           = $true
        }
        Script CertFiles {
            DependsOn  = @("[File]ClientCert", "[File]ClientKey")
            SetScript  = 
            {
                
                get-childitem "$($env:programdata)\docker\clientcerts\*.pem" | foreach-object {(get-content $_) | set-content  -Path $_  -Encoding ASCII}
                New-Item "$($env:programdata)\docker\clientcerts\processed.txt" -force
                
            }
            TestScript = { 
                Test-Path "$($env:programdata)\docker\clientcerts\processed.txt"
            }
            GetScript  = { @{Result = ("User profile is $($env:UserProfile)")} }
        }
    }
}
swarmhost