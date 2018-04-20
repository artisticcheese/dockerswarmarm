Configuration SwarmManager
{
    # Parameter help description
    param
    (
        [string] $privateKey = (Get-AutomationVariable -Name privatekey),
        [string] $serverCert = (Get-AutomationVariable -Name servercert),
        [string] $CAcert = (Get-AutomationVariable -Name ca),
         [string] $clientCert = (Get-AutomationVariable -Name VMSSclientcert),
        [string] $clientKey = (Get-AutomationVariable -Name VMSSclientkey),
        [string] $SwarmManagerURI
    )
    
    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName cChoco 
    Import-DSCResource -moduleName cDSCDockerSwarm -ModuleVersion 0.9.2
    Import-DSCResource -moduleName xNetworking
    Node localhost
    {
        Environment DockerCertpath {
            Name  = "DOCKER_CERT_PATH"
            Value = "c:\programdata\docker\clientcerts\"
        }
        cDockerConfig DaemonJson {
            DependsOn       = @("[Script]CertFiles")
            Ensure          = 'Present'
            RestartOnChange = $true
            EnableTLS = $true
            ExposeAPI = $true
            Labels          = "pet_swarm_manager=true"
        }
        xFirewallProfile DisablePublic {
            Enabled = "False"
            Name   = "Public"
        }
        xFirewallProfile DisablePrivate {
            Enabled = "False"
            Name   = "Private"
        }
        cDockerSwarm Swarm {
            DependsOn       = '[cDockerConfig]DaemonJson'
            SwarmMasterURI  = "$($SwarmManagerURI):2377"
            SwarmMode       = 'Active'
            ManagerCount    = 3
            SwarmManagement = 'Automatic'
        }

        cChocoInstaller installChoco {
            InstallDir = "c:\choco"
        }
        cChocoPackageInstallerSet ProgramInstalls {
            Ensure = 'Present'
            Name   = @(
                "classic-shell"
                "7zip"
                "visualstudiocode"
                "sysinternals"
            )
            
        }
        File PrivateKey {
            Dependson = @("[Environment]DockerCertpath")
            Destinationpath = "$($env:programdata)\docker\certs.d\key.pem"
            Contents        = $privateKey
            Force           = $true
        }
        File ServerCert {
            Destinationpath = "$($env:programdata)\docker\certs.d\cert.pem"
            Contents        = $serverCert
            Force           = $true
        }
        File CACert {
            Destinationpath = "$($env:programdata)\docker\certs.d\ca.pem"
            Contents        = $CAcert
            Force           = $true
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
        #Have to use Script to save files with [File] resource is saving by default in UTF8-BOM
        Script CertFiles {
            DependsOn  = @("[File]PrivateKey", "[File]ServerCert", "[File]CAcert", "[File]ClientCert", "[File]ClientKey")
            SetScript  = 
            {
                get-childitem "$($env:programdata)\docker\certs.d\*.pem" | foreach-object {(get-content $_) | set-content  -Path $_  -Encoding ASCII}
                get-childitem "$($env:programdata)\docker\clientcerts\*.pem" | foreach-object {(get-content $_) | set-content  -Path $_  -Encoding ASCII}
                New-Item "$($env:programdata)\docker\clientcerts\processed.txt" -force
                 New-Item "$($env:programdata)\docker\certs.d\processed.txt" -force
            }
            TestScript = { 
                (Test-Path -Path "$($env:programdata)\docker\certs.d\processed.txt") -and (Test-Path "$($env:programdata)\docker\clientcerts\processed.txt")
            }
            GetScript  = { @{Result = ("User profile is $($env:UserProfile)")} }
        }
    }
}

SwarmManager 