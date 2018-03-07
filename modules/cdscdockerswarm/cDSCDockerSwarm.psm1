# Defines the values for the resource's Ensure property.
enum Ensure
{
    # The resource must be absent.    
    Absent
    # The resource must be present.    
    Present
}

enum Swarm
{
    # The Swarm must be active   
    Active
    # The Swarm must be inactive
    Inactive
}

enum SwarmManagement
{
    # Manage Manager Count  
    Automatic
    # Only join as worker
    WorkerOnly
}




[DscResource()]
class cDockerConfig
{

    #Ensure present or absent
    [DscProperty(Key)]
    [Ensure]$Ensure

    #JSON format string of general configuration opstions, not including labels, hosts, and registries
    [DscProperty()]
    [string]$BaseConfigJson='{}'

    #Array of registries to be added to the configuration
    [DscProperty()]
    [string[]] $InsecureRegistries

    #Array of labels to be added to the configuration
    [DscProperty()]
    [string[]] $Labels

    #Daemon binings, defaults to all interfaces. Specify in format of 'tcp://0.0.0.0:2375'
    [DscProperty()]
    [string]$DaemonBinding

    #Adds named pipe and TCP bindings to configuration, allowing external access. This is required for Swarm mode
    [DscProperty()]
    [boolean] $ExposeAPI
    
    #Restart docker on any chane of the configuration
    [DscProperty()]
    [boolean] $RestartOnChange

    #Enable TLS
    [DscProperty()]
    [bool]$EnableTLS=$false

    # Sets the desired state of the resource.
    [void] Set()
    {    
        if ($this.Ensure -eq [Ensure]::Present) {
            
            $pendingConfiguration = $this.GetPendingConfiguration()

            #Does a config exist at all?
            $ConfigExists = $this.ConfigExists()
            Write-Verbose "Config Exists: $ConfigExists" 
            #Write Configuration
            $pendingConfiguration |  Out-File "$($env:ProgramData)\docker\config\daemon.json" -Encoding ascii -Force

            #Restart docker service if the configuration changed, or if this is the initial configuration
            if ($this.RestartOnChange -or !($ConfigExists)) {
                Write-Verbose "Restarting the Docker service"
                Restart-Service Docker
                start-sleep 5
            }
        }
        else {
            Remove-Item "$($env:ProgramData)\docker\config\daemon.json" -Force
        }     
    }        
    
    # Tests if the resource is in the desired state.
    [bool] Test()
    {   
        if ($this.Ensure -eq [Ensure]::Present) {     
            if($this.ConfigExists()){            
			    $currentConfiguration = Get-Content "$($env:ProgramData)\docker\config\daemon.json" -raw
                $pendingConfigurationJS = $this.GetPendingConfiguration() | Out-String                

                if ($currentConfiguration -eq $pendingConfigurationJS) {
                    Write-Verbose "Configuration Matches"
                    return $true
                }
                else{
                    Write-Verbose "Configuration Does not Match"
                    return $false
                }
		    }
		    else{
                Write-Verbose "Missing daemon.json"
			    return $false
		    }
        }
        else { #Make sure the config is absent
            if($this.ConfigExists()){
                Write-Verbose "daemon.json Exists but should not"
                return $false
              }
            else {
             Write-Verbose "daemon.json does not exist"
                return $true
            }
        }

		return $false
    }    
    # Gets the resource's current state.
    [cDockerConfig] Get()
    {   
        $ConfigExists = $this.ConfigExists()    
        if($ConfigExists){            
            $currentConfiguration = Get-Content "$($env:ProgramData)\docker\config\daemon.json" -raw
            $pendingConfigurationJS = $this.GetPendingConfiguration() | Out-String                

            if ($currentConfiguration -eq $pendingConfigurationJS) {
                $this.Ensure = [ensure]::Present
            }
            else {
                $this.Ensure = [ensure]::Absent
            }
        }
        else {
            $this.Ensure = [ensure]::Absent
        }
        return $this
     }

     [bool]ConfigExists() {
       if (Test-Path "$($env:ProgramData)\docker\config\daemon.json") {
                return $true
            }
            else {
                return $false
            }
     }

     [string]GetPendingConfiguration() {
     
        $pendingConfiguration = $this.BaseConfigJson | ConvertFrom-json

        if ($this.InsecureRegistries) {
            $pendingConfiguration | Add-Member -Name "insecure-registries" -Value  $this.InsecureRegistries -MemberType NoteProperty
        }
        if ($this.Labels) {
            $pendingConfiguration | Add-Member -Name "labels" -Value $this.Labels -MemberType NoteProperty
        }

        $CertExists = Test-Path $env:ALLUSERSPROFILE\docker\certs.d\cert.pem
        $KeyExists = Test-Path $env:ALLUSERSPROFILE\docker\certs.d\key.pem
        if ($this.EnableTLS -and $CertExists -and $KeyExists) {
            #Add TLS                 
            $pendingConfiguration | Add-Member -MemberType NoteProperty -Name  "tlscacert" -Value "C:\ProgramData\docker\certs.d\ca.pem"
            $pendingConfiguration | Add-Member -MemberType NoteProperty -Name  "tlscert" -Value "C:\ProgramData\docker\certs.d\cert.pem"
            $pendingConfiguration | Add-Member -MemberType NoteProperty -Name  "tlskey" -Value "C:\ProgramData\docker\certs.d\key.pem"
            $pendingConfiguration | Add-Member -MemberType NoteProperty -Name  "tlsverify" -Value $true     
            #Adjust port for TLS
            if($this.exposeApi -eq $true){
                if ($this.DaemonBinding) {
                    $binding = $this.DaemonBinding            
                }
                else {
                    $binding = "tcp://0.0.0.0:2376"
                }
			    $pendingConfiguration | Add-Member -Name "hosts" -MemberType NoteProperty -Value @($binding, "npipe://")
            }       
        }
        else{
            if($this.exposeApi -eq $true){
                if ($this.DaemonBinding) {
                    $binding = $this.DaemonBinding            
                }
                else {
                    $binding = "tcp://0.0.0.0:2375"
                }
			    $pendingConfiguration | Add-Member -Name "hosts" -MemberType NoteProperty -Value @($binding, "npipe://")
            }
        }

        return $pendingConfiguration | ConvertTo-Json
     }
    

}


# [DscResource()] indicates the class is a DSC resource.
[DscResource()]
class cDockerSwarm
{

    #Swarm Master URl in the format of "10.10.10.10:2377"
    [DscProperty(Key)]
    [string]$SwarmMasterURI

    #Activate swarm mode on the host and connect to swarm master. Must be Active or Inactive
    [DscProperty(Mandatory)]
    [Swarm] $SwarmMode

    #Number of managers to attempt of SwarmManagement is automatic. The nodes will join as managers until the number specified is met. 
    [DscProperty()]
    [int] $ManagerCount=3

    #Automatic will manage the number of managers in the swarm. WorkerOnly will join only as worker nodes
    [DscProperty(Mandatory)]
    [SwarmManagement]$SwarmManagement

    # Sets the desired state of the resource.
    [void] Set()
    {    
        Write-Verbose "Using Swarm Master: $($this.SwarmMasterURI)"
        $SwarmDockerHost = $($this.SwarmMasterURI).Split(':')[0]
        $SwarmManagerIsMe = (Get-NetIPAddress).IPAddress -contains $SwarmDockerHost
        Write-Verbose "Getting Local Docker info"

        $LocalInfo = $this.GetLocalDockerInfo()
        
        Write-Verbose "Getting Swarm info from $SwarmDockerHost"
        if ((test-netconnection $SwarmDockerHost -Port 2375).tcpTestSucceeded) {
            $swarmConnString = $SwarmDockerHost
            $tls = $null
        }
        elseif ((test-netconnection $SwarmDockerHost -Port 2376).tcpTestSucceeded) {
            $swarmConnString = "$($SwarmDockerHost):2376"
            $tls = "--tls"
        }
        else {
            write-error "no connection to remote swarm manager"
        }
        #Random seed to sleep to get better distribution, and prevent too many managers.
        Start-Sleep (get-random -Minimum 0 -Maximum 15)
        $SwarmInfo = . "$($Env:ProgramFiles)\docker\docker.exe" -H $swarmConnString $tls info -f '{{ json .Swarm }}' | ConvertFrom-Json
        $managers = $SwarmInfo.managers
        
        if ($LocalInfo.Swarm.LocalNodeState -eq "active") {
            $InRightSwarm = $LocalInfo.Swarm.RemoteManagers.Addr -contains $this.SwarmMasterURI
            if (!$InRightSwarm) {
                Write-Verbose "Server is in the wrong swarm; leaving"
                . "$($Env:ProgramFiles)\docker\docker.exe" swarm leave -f
            }
            elseif ($this.SwarmMode -eq [Swarm]::Inactive) {
                Write-Verbose "Server is in the a swarm and should be inactive; leaving"
			    . "$($Env:ProgramFiles)\docker\docker.exe" swarm leave -f
		    }
            elseif (($this.SwarmMode -eq [Swarm]::Active) -and ($managers -lt $this.ManagerCount)) {
                . "$($Env:ProgramFiles)\docker\docker.exe" -H $swarmConnString $tls node promote $env:COMPUTERNAME
            }
        }
        elseif ($this.SwarmMode -eq [Swarm]::Active) {
            
            if ($SwarmManagerIsMe) {
                Write-Verbose "Creating a new Swarm"
                . "$($Env:ProgramFiles)\docker\docker.exe" swarm init --advertise-addr $this.SwarmMasterURI
            }
            elseif (($this.SwarmManagement -eq [SwarmManagement]::Automatic) -and ($managers -lt $this.ManagerCount)) {
                Write-Verbose "Joining the Swarm as a manager"
                $this.JoinSwarm($swarmConnString, $tls, "manager")
            }
            else {
                Write-Verbose "Joining the Swarm as a worker"
                $this.JoinSwarm($swarmConnString, $tls,"worker")
            }
        }        
		
    }        
    
    # Tests if the resource is in the desired state.
    [bool] Test()
    {        
            $LocalInfo = $this.GetLocalDockerInfo()
            
			if ($LocalInfo.Swarm.LocalNodeState  -eq "active" -and ($this.SwarmMode -eq [Swarm]::Active)) {
                Write-Verbose "Swarm is Active"
                #Test for swarm membership                
                $InRightSwarm = $LocalInfo.Swarm.RemoteManagers.Addr -contains $this.SwarmMasterURI
                if ($InRightSwarm) {
                    Write-Verbose "In Correct Swarm"
                    #Test for manager count
                    if (($this.SwarmManagement -eq [SwarmManagement]::WorkerOnly) -or  ($LocalInfo.Swarm.managers -ge $this.ManagerCount )) {
                        Write-Verbose "Swarm State Good. Managers: $($LocalInfo.Swarm.managers)"
                        return $true    
                    }
                    else {
                        if ($LocalInfo.Swarm.ControlAvailable -eq $true) {
                            Write-Verbose "Not enough Managers: $($LocalInfo.Swarm.managers), but node is already a manager"
                            return $true
                        }
                        else
                        {
                        Write-Verbose "Not enough Managers: $($LocalInfo.Swarm.managers), need to be promoted"
                        return $false
                        }
                    }
                }
                else {
                    Write-Verbose "In Wrong Swarm: $($LocalInfo.Swarm.RemoteManagers.Addr) vs $($this.SwarmMasterURI)"
                    return $false
                }                
			}
			elseif ($LocalInfo.Swarm.LocalNodeState  -eq "inactive" -and ($this.SwarmMode -eq [Swarm]::Active)) {
                Write-Verbose "Swarm State $($LocalInfo.Swarm.LocalNodeState), should be $($this.SwarmMode)"				
                return $false
			}
			elseif ($LocalInfo.Swarm.LocalNodeState  -eq "active" -and ($this.SwarmMode -eq [Swarm]::Inactive)) {
                Write-Verbose "Swarm State $($LocalInfo.Swarm.LocalNodeState), should be $($this.SwarmMode)"				
				return $false
			}
			elseif ($LocalInfo.Swarm.LocalNodeState  -eq "inactive" -and ($this.SwarmMode -eq [Swarm]::Inactive)) {
                Write-Verbose "Swarm State Good"	
				return $true
			}
            else {
                Write-Verbose "Default return: failure to determine state"				
                return $false
            }
    }    
    # Gets the resource's current state.
    [cDockerSwarm] Get()
    {        
        $SwarmState = . "$($Env:ProgramFiles)\docker\docker.exe" info -f '{{ json .Swarm.LocalNodeState }}' | ConvertFrom-Json
			if ($SwarmState -eq "active"){
				$this.SwarmMode = [Swarm]::Active
			}
			elseif ($SwarmState -eq "inactive") {
				$this.SwarmMode = [Swarm]::Inactive
			}
        return $this 
    }
    
    [psobject]GetLocalDockerInfo(){
        #Try in a loop, in case docker was just restarted and is not ready yet
        $info = $null
        $i = 0
        while (!$info -and $i -lt 5) { 
            try{
                $i++
                $ErrorActionPreference = 'stop'
                Write-Verbose "Trying to get token from swarm manager"
                $info = . "$($Env:ProgramFiles)\docker\docker.exe" info -f '{{ json . }}' | ConvertFrom-Json                
                break
            }
            catch {
                Write-Verbose "Waiting for local docker to come online"
                start-sleep 5
            }            
        }
        return $info
    }

    [void]JoinSwarm($host, $tls,$type)
    {
        $token = $null
        $i = 0
        while (!$token -and $i -lt 5) { 
            try{
                $i++
                $ErrorActionPreference = 'stop'
                Write-Verbose "Trying to get token from swarm manager"
                $token = . "$($Env:ProgramFiles)\docker\docker.exe" -H $host $tls swarm join-token $type -q 
                break
            }
            catch {
                Write-Verbose "Waiting for manager to come online"
                start-sleep 15
            }
        
        }
        if ($token) {
            . "$($Env:ProgramFiles)\docker\docker.exe" swarm join --token $token $this.SwarmMasterURI
        }
        else {
            write-verbose "Failed to Get token; can't join swarm"
        }
    }    
}

