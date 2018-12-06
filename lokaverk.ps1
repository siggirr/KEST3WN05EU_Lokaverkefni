function IPToNetKort{
    param(
        [Parameter(Mandatory=$true, HelpMessage= "Sl��u inn IP t�lu til a� f� nafn net korts")]
        [string]$IPTala
    )

    return (Get-NetIPAddress -IPAddress $IPTala).InterfaceAlias
}





$grunnpath = "dc=ts-sigvid,dc=local"
$envirogrunnpath = $env:USERDNSDOMAIN
$envirosplitpath = $envirogrunnpath.Split('.')
$domainControllerPaste = "dc=" + $envirosplitpath[0]  + ",dc=" + $envirosplitpath[1]

#Netstillingar
Rename-NetAdapter -Name (IPToNetKort -IPTala 169.254.*) -NewName "LAN"
New-NetIPAddress -InterfaceAlias "LAN" -IPAddress  10.10.0.1 -PrefixLength 21
Set-DnsClientServerAddress -InterfaceAlias "LAN" -ServerAddresses 127.0.0.1

#Setja inn AD-DS role-i�
Install-WindowsFeature -Name ad-domain-services -IncludeManagementTools

#Promote server � domain-controller
Install-ADDSForest -DomainName ts-sigvid.local -InstallDns -SafeModeAdministratorPassword (ConvertTo-SecureString -AsPlainText "pass.123" -Force)

#REBOOT--------------

#Setja inn DHCP Role
Install-WindowsFeature -Name DHCP -IncludeManagementTools

#Setja upp DHCP scope
Add-DhcpServerv4Scope -Name scope1 -StartRange 10.10.0.10 -EndRange 10.10.7.254 -SubnetMask 255.255.248.0
Set-DhcpServerv4OptionValue -DnsServer 10.10.0.1 -Router 10.10.0.2
Add-DhcpServerInDC $($env:COMPUTERNAME + "." + $env:USERDNSDOMAIN)

#--------------------

#Gr�ja lykilor�
$passwd = ConvertTo-SecureString -AsPlainText "2015P@ssword" -Force
$win8notandi = New-Object System.Management.Automation.PSCredential -ArgumentList $("win3a-w81-11\administrator"), $passwd
$serverNotandi = New-Object System.Management.Automation.PSCredential -ArgumentList $($env:USERDOMAIN + "\administrator"), $passwd

#Setja win8 v�l � domain
Add-Computer -ComputerName "win3a-w81-11" -LocalCredential $win8notandi -DomainName $env:USERDNSDOMAIN -Credential $serverNotandi -Restart -Force

#B�a til OU fyrir t�lvur
New-ADOrganizationalUnit -Name T�lvur -ProtectedFromAccidentalDeletion $false 

#F�ra win8 v�l � n�ja OU-i�
Move-ADObject -Identity "CN=WIN3A-W81-11,CN=Computers,DC=ts-sigvid,DC=local"  -TargetPath $("OU=T�lvur" + ",DC=" + $env:USERDOMAIN + ",DC=" + $env:USERDNSDOMAIN.Split('.')[1])


New-ADOrganizationalUnit Notendur -ProtectedFromAccidentalDeletion $false
New-ADGroup Allir -Path $("ou=notendur," + $domainControllerPaste) -GroupScope Global


$notendur = Import-Csv .\lokaverk_notendur.csv


New-ADOrganizationalUnit -Name Kennarar -Path $("ou=Starfsmenn," +"ou=notendur," + $domainControllerPaste) -ProtectedFromAccidentalDeletion $false

#Starfsmenn OU , group og setja Allir group �
if((Get-ADOrganizationalUnit -Filter {name -eq "Starfsmenn"}).Name -ne "Starfsmenn"){
    New-ADOrganizationalUnit -Name "Starfsmenn" -Path $("ou=notendur," + $domainControllerPaste) -ProtectedFromAccidentalDeletion $false
    New-ADGroup -Name Starfsmenn -Path $("ou=Starfsmenn,ou=notendur," + $domainControllerPaste) -GroupScope Global
    Add-ADGroupMember -Identity Allir -Members "Starfsmenn"
}

foreach($n in $notendur){
$hlutverk = $n.hlutverk
$skoli = $n.skoli
$braut = $n.braut
    if($n.hlutverk -like "Kennarar"){ 
            "Kennari: " + $n.Hlutverk + " - " +  $n.Nafn + " - " + $n.Braut
            #Hlutverk OU , group og setja Allir group �
            if((Get-ADOrganizationalUnit -Filter {name -eq $hlutverk}).Name -ne $hlutverk){
               New-ADOrganizationalUnit -Name $hlutverk -Path $("ou=Starfsmenn,"+"ou=notendur," + $domainControllerPaste) -ProtectedFromAccidentalDeletion $false
               New-ADGroup -Name $hlutverk -Path $("ou=" + $hlutverk + ",ou=Starfsmenn," +"ou=notendur,"+ $domainControllerPaste) -GroupScope Global
               Add-ADGroupMember -Identity Allir -Members $hlutverk
            }
            #Sk�li OU , group og setja Allir group �
            if((Get-ADOrganizationalUnit -SearchBase $("OU=" + $hlutverk + ",ou=Starfsmenn,ou=notendur," + $domainControllerPaste ) -Filter {name -eq $braut}).Name -ne $braut){
               New-ADOrganizationalUnit -Name $skoli -Path $("ou=" + $hlutverk + ",ou=Starfsmenn,ou=notendur," + $domainControllerPaste) -ProtectedFromAccidentalDeletion $false
               New-ADGroup -Name $($skoli + " " + $hlutverk) -Path $("ou=" + $skoli + ",ou=" + $hlutverk + ",ou=Starfsmenn,ou=notendur," + $domainControllerPaste) -GroupScope Global
               Add-ADGroupMember -Identity  $hlutverk -Members $($skoli + " " + $hlutverk)
            }
            #Braut OU , group og setja Allir group �
            if((Get-ADOrganizationalUnit -SearchBase $("OU=" + $hlutverk + ",ou=Starfsmenn,ou=notendur," + $domainControllerPaste ) -Filter {name -eq $braut}).Name -ne $braut){
               New-ADOrganizationalUnit -Name $braut -Path $("ou=" + $skoli + ",ou=" + $hlutverk + ",ou=Starfsmenn,ou=notendur," + $domainControllerPaste) -ProtectedFromAccidentalDeletion $false
               New-ADGroup -Name $($braut + " " + $hlutverk) -Path $("ou=" +$braut + ",ou=" + $skoli + ",ou=" + $hlutverk + ",ou=Starfsmenn,ou=notendur," + $domainControllerPaste) -GroupScope Global
               Add-ADGroupMember -Identity $($skoli + " "  + $hlutverk) -Members $($braut + " " + $hlutverk)
              }
    
           
    }  if($n.hlutverk -like "Nemendur") {
            "Nemandi: " + $n.Hlutverk + " - " +  $n.Nafn + " - " + $n.Braut
            #Hlutverk
            if((Get-ADOrganizationalUnit -Filter {name -eq $hlutverk}).Name -ne $hlutverk){
                New-ADOrganizationalUnit -Name $hlutverk -Path $("ou=notendur," + $domainControllerPaste) -ProtectedFromAccidentalDeletion $false
                New-ADGroup -Name $hlutverk -Path $("ou=" + $hlutverk + ",ou=notendur," + $domainControllerPaste) -GroupScope Global
                Add-ADGroupMember -Identity Allir -Members $hlutverk
            }
            #Sk�li
            if((Get-ADOrganizationalUnit -SearchBase $("OU=" + $hlutverk + ",ou=notendur," + $domainControllerPaste ) -Filter {name -eq $braut}).Name -ne $braut)
            {
               New-ADOrganizationalUnit -Name $skoli -Path $("ou=" + $hlutverk +",ou=notendur," + $domainControllerPaste) -ProtectedFromAccidentalDeletion $false
               New-ADGroup -Name $($skoli + " " + $hlutverk) -Path $("ou=" + $skoli + ",ou=" + $hlutverk + ",ou=notendur," + $domainControllerPaste) -GroupScope Global
               Add-ADGroupMember -Identity $hlutverk -Members $($skoli + " " + $hlutverk)
            }
            #Braut
            if((Get-ADOrganizationalUnit -SearchBase $("OU=" + $hlutverk + ",ou=notendur," + $domainControllerPaste ) -Filter {name -eq $braut}).Name -ne $braut){
               New-ADOrganizationalUnit -Name $braut -Path $("ou=" + $skoli + ",ou=" + $hlutverk + ",ou=notendur," + $domainControllerPaste) -ProtectedFromAccidentalDeletion $false
               New-ADGroup -Name $($braut + " " + $hlutverk) -Path $("ou=" + $braut +",ou=" + $skoli + ",ou=" + $hlutverk + ",ou=notendur," + $domainControllerPaste) -GroupScope Global
               Add-ADGroupMember -Identity $($skoli + " " +$hlutverk) -Members $($braut + " " + $hlutverk)
            }
    } 
}

foreach($n in $notendur){
    $hlutverk = $n.hlutverk
    $skoli = $n.skoli
    $braut = $n.braut
    
    
    
    
    if($hlutverk -like "Nemendur"){
        $loginNafnNemenda = nameShortcut -nafn $n.Nafn
        $nemendaUppl = @{
        Office = $n.Skoli
        Title = $n.Hlutverk
        Department = $n.Braut
        Name = $n.nafn
        givenname = $n.Nafn.SubString(0, $n.Nafn.LastIndexOf(' '))
        surname = $n.Nafn.Split(' ')[-1]
        SamAccountName = $loginNafnNemenda
        UserPrincipalName = $($loginNafnNemenda + "@ts-sigvid.local")
        AccountPassword = (ConvertTo-SecureString -AsPlainText "pass.123" -Force)
        Path = $("ou=" + $braut + ",ou=" + $skoli + ",ou=" + $hlutverk + ",ou=notendur,"  + $domainControllerPaste)
        Enabled = $true
        
        
        }
        "Nemandi: " + $loginNafnNemenda + " - " + $n.Nafn
        New-ADUser @nemendaUppl -Verbose
        Add-ADGroupMember -Identity $($braut + " " + $hlutverk) -Members $loginNafnNemenda

        
    }
    

    if($hlutverk -like "Kennarar")
    {
        $loginNafnKennara = replaceISL -inputiSL $n.Nafn
        $kennaraUppl = @{
        Office = $n.Skoli
        Title = $n.Hlutverk
        Department = $n.Braut
        Name = $n.nafn

        surname = $n.Nafn.Split(' ')[-1]
        givenname = $n.Nafn.SubString(0, $n.Nafn.LastIndexOf(' '))
      
        SamAccountName = $loginNafnKennara
        UserPrincipalName = $($loginNafnKennara + "@" + $envirogrunnpath)
        AccountPassword = (ConvertTo-SecureString -AsPlainText "pass.123" -Force)
        Path = $("ou=" + $braut + ",ou=" + $skoli + ",ou=" + $hlutverk + ",ou=Starfsmenn,ou=notendur,"  + $domainControllerPaste)
        Enabled = $true

        
        }
        "Kennari: " + $loginNafnKennara + " - " + $n.Nafn
        New-ADUser @kennaraUppl -Verbose
        Add-ADGroupMember -Identity $($braut + " " + $hlutverk) -Members $loginNafnKennara
    }

}

#Notendannafn  Nemenda function
function nameShortcut{
    param(
        [Parameter(Mandatory=$true, HelpMessage="Settu inn nafn Kennara/Nemenda")]
        [string]$nafn
    )
    $nafn = replaceISL -inputiSL $nafn.ToLower()
    #$userNameCounter = 1
    $splitName = $nafn.Split(".")
    $first = $splitName[0].Substring(0, 2)
    $last = $splitName[-1].Substring(0, 2)
    $concatString = $($first + $last + "*")

    #$replacedShortcut = replaceISL -inputiSL $concatString
    $fjoldiEins = @(Get-ADUser -Filter { SamAccountName -eq $concatString}).Count
    #$fjoldiEins = (Get-ADUser -Filter *| where {$_.SamAccountName -eq $concatString}).Count
    #Erum staddir h�r grunum a� �a� s� stjarnan Substring var � 0,4 range sem t�k bara 4 char vanta�i meira range !! Hvernig � a� f� $fjoldiEins fj�lda = 1
    if($fjoldiEins -ge 2){
        return $($concatString.Substring(0,4) + $fjoldiEins)
    }
    if($fjoldiEins -like 0){
        return $concatString.Substring(0,4) 
    }
    if($fjoldiEins -like 1){
        return $($concatString.Substring(0,4) + "1")
    }
}

# (Get-ADUser -Filter { SamAccountName -eq "anan"}).Count

#Notendanafn Kennara function
function replaceISL{
    param(
        [Parameter(Mandatory=$true, HelpMessage= "H�r er sett inn nafn starfsmanns")]
        [string]$inputiSL
    )
    $s = $inputISL.ToLower()
    $s = $s.replace('�','a')
    $s = $s.replace('�','u')
    $s = $s.replace('�','e')
    $s = $s.replace('�','d')
    $s = $s.replace('�','i')
    $s = $s.replace('�','o')
    $s = $s.replace('�','th')
    $s = $s.replace('�','ae')
    $s = $s.replace('�','o')
    $s = $s.replace('�','y')
    $s = $s.replace(' ','.')
    $s = $s.replace('..', '.')
     # ef $s er lengra en 20 stafir 
        # substring(0,20)
    

    if($s.Length -gt 20){
        $s = $s.Substring(0, 20)
    }

    if($s[$s.Length - 1] -eq '.'){
        $s = $s.Substring(0, 19)
    }
    return $s; 
}

Add-DnsServerPrimaryZone -Name "tskoli.is" -ReplicationScope Domain

foreach($n in $notendur){
$samAccName = nameShortcut -nafn $n.Nafn 
    if($n.Braut -eq "T�lvubraut")
        {
            Add-DnsServerResourceRecordA -ZoneName "tskoli.is" -Name $samAccName -IPv4Address 10.10.0.1
            ## New-Item -ItemType Directory -Force -Path $("C:\inetpub\wwwroot\" + $samAccName)
            New-Item $("C:\inetpub\wwwroot\" + $samAccName + "\index.html") -Value $("Vefs��an hj� " + $n.Nafn) -ItemType File
            New-Website -Name $($samAccName + ".tskoli.is") -HostHeader $($samAccName + ".tskoli.is")  -PhysicalPath $("C:\inetpub\wwwroot\" + $samAccName)
        }
}

foreach($n in $notendur){
$samAccName = nameShortcut -nafn $n.Nafn 
    if($n.Braut -eq "T�lvubraut")
        {
            ## New-Item -ItemType Directory -Force -Path $("C:\inetpub\wwwroot\" + $samAccName)
            
        }
}


