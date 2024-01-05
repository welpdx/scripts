Function Who-loggedinLast{
<#
    .SYNOPSIS
        shows last logon user on remote or Local Computer

    .DESCRIPTION
        It shows the user logged in last in remote or local using event viewer at system which tracks logon and logoff events.

    .PARAMETER ComputerName
     One or more computernames

    .PARAMETER maxresults - Mandatory
    Number of users or events you would like to see

    .EXAMPLE
        PS C:\> Who-loggedinLast -maxresults 2
        Shows the current Computer last logged users
         
user                                        Action                                  Time                                   Computer                              
----                                      ------                                  ----                                   --------                              
Domain\xxxxxxxxxxxxxxxxxxxxx               Logon                                   8/26/2019 11:27:07 AM                  Computer1                               
Domain\usernameof the user                 Logoff                                  8/23/2019 3:12:27 PM                   Computer2               


    .EXAMPLE
        PS C:\> Who-loggedinLast -Computer server03,Server04,Dc02 -maxResults 1
        Shows the Last Login users of all 3 servers specified

     

    .Example all AD servers

        PS C:\> $computers=get-adcomputer -filter {operatingsystem -like '*server*'}|select -exp Name 
                           ForEach($computer in $computers)
                           {
                           Who-loggedinLast -computer $computer -maxResults 1

                          } 

                          #OR
        .Example

        Who-loggedinLast -Computer (get-adcomputer -filter {operatingsystem -like '*server*'}).Name  -maxResults 2

        Shows all computers in active directory computers

        To export in csv just add |export-csv c:\results.csv -notype

    .Example

        PS C:\>  Who-loggedinLast -Computer (get-content c C:\scripts\com.txt) -maxResults 2 
        Shows reslts of all the computers in the text file.

    .Example - Logon only

    Who-loggedinLast -maxResults 7 |where action -eq logon

    .Example - Logoff only

    Who-loggedinLast -maxResults 7 |where action -eq logoff

************************************************************************
 Notes: Run as administrator
 Author: Jiten https://community.spiceworks.com/people/jitensh
Date Created: 08/26/2019
     Credits: 
Last Revised: 10/02/2021
************************************************************************

#>
[cmdletbinding()]
   param(
   [String[]]$Computer = $env:COMPUTERNAME,
   [Parameter(Mandatory=$true)]
   [Int]$maxResults
   )
$UserProperty = @{n="User";e={(New-Object System.Security.Principal.SecurityIdentifier $_.Properties.Value[1]).Translate([System.Security.Principal.NTAccount])}}
$TypeProperty = @{n="Action";e={if($_.ID -eq 7001) {"Logon"} else {"Logoff"}}}
$TimeProeprty = @{n="Time";e={$_.timecreated}}

ForEach ($COMPUTER in ($computer))
        {
        if(!(Test-Connection -Cn $computer -BufferSize 16 -Count 1 -ea 0 -quiet))
        {
        Write-Host "$($computer) " -F Yellow -NoNewline
        write-host "Cannot be reached, may be its offline" -f red
        }
          
 Else   {
      
        TRY
        {
        
Get-WinEvent -FilterHash @{LogName='system';providername='Microsoft-Windows-Winlogon'} -MaxEvents $maxResults|
select $UserProperty,$TypeProperty,$TimeProeprty,@{n="Computer";e={$Computer}}
        }
        Catch {$error[0].exception.message}
        }
        }
        } 
        
Who-loggedinLast