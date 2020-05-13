Function Get-AccessToken {

    $clientId = "d1ddf0e4-d672-4dae-b554-9d5bdfd93547"
    $redirectUrl = [System.Uri]"urn:ietf:wg:oauth:2.0:oob" # This is the standard Redirect URI for Windows Azure PowerShell
    $resource = "https://graph.microsoft.com/";
    $scope = "https://graph.microsoft.com/.default"
    $authUrl = "https://login.microsoftonline.com/organizations";

    $postParams = @{ scope = "$scope"; client_id = "$clientId" }
    $response = Invoke-RestMethod -Method POST -Uri "$authurl/oauth2/v2.0/devicecode" -Body $postParams

    $responsePrompt = $response.user_code

    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $LoginToAzureAD                  = New-Object system.Windows.Forms.Form
    $LoginToAzureAD.ClientSize       = '350,350'
    $LoginToAzureAD.text             = "Login to Azure AD"
    $LoginToAzureAD.TopMost          = $false

    $user_code_label                 = New-Object system.Windows.Forms.Label
    $user_code_label.text            = "Azure AD Device Code:"
    $user_code_label.AutoSize        = $false
    $user_code_label.width           = 320
    $user_code_label.height          = 30
    $user_code_label.Anchor          = 'top,right,bottom,left'
    $user_code_label.location        = New-Object System.Drawing.Point(15,25)
    $user_code_label.Font            = 'Microsoft Sans Serif,14'

    $user_code                       = New-Object system.Windows.Forms.Label
    $user_code.text                  = $responsePrompt
    $user_code.AutoSize              = $false
    $user_code.width                 = 300
    $user_code.height                = 40
    $user_code.Anchor                = 'top,right,bottom,left'
    $user_code.location              = New-Object System.Drawing.Point(25,70)
    $user_code.Font                  = 'Microsoft Sans Serif,24,style=Bold'

    $directions                      = New-Object system.Windows.Forms.Label
    $directions.text                 = "To sign in, use a web browser on another device to open the page https://microsoft.com/devicelogin and enter the code above to authenticate. Click OK when logged in."
    $directions.AutoSize             = $true
    $directions.MaximumSize          = New-Object System.Drawing.Size(320,0)
    $directions.Anchor               = 'top,right,bottom,left'
    $directions.location             = New-Object System.Drawing.Point(15,150)
    $directions.Font                 = 'Microsoft Sans Serif,11'

    $OK                              = New-Object system.Windows.Forms.Button
    $OK.text                         = "OK"
    $OK.width                        = 80
    $OK.height                       = 30
    $OK.location                     = New-Object System.Drawing.Point(85,285)
    $OK.Font                         = 'Microsoft Sans Serif,12,style=Bold'
    $OK.DialogResult                 = [System.Windows.Forms.DialogResult]::OK

    $Cancel                          = New-Object system.Windows.Forms.Button
    $Cancel.text                     = "Cancel"
    $Cancel.width                    = 80
    $Cancel.height                   = 30
    $Cancel.location                 = New-Object System.Drawing.Point(185,285)
    $Cancel.Font                     = 'Microsoft Sans Serif,12'
    $Cancel.DialogResult             = [System.Windows.Forms.DialogResult]::Cancel

    $LoginToAzureAD.AcceptButton     = $OK
    $LoginToAzureAD.CancelButton     = $Cancel

    $LoginToAzureAD.controls.AddRange(@($user_code_label,$user_code,$directions,$OK,$Cancel))

    $LoginToAzureAD.ShowDialog()

    If($LoginToAzureAD -eq [Windows.Forms.DialogResult]::Cancel) {
        Exit
    }

    $tokenParams = @{ grant_type = "device_code"; scope = "$scope"; client_id = "$clientId"; code = "$($response.device_code)" }

    $tokenResponse = $null

    $tokenResponse = Invoke-RestMethod -Method POST -Uri "$authurl/oauth2/v2.0/token" -Body $tokenParams

    return $tokenResponse

}

Function ConvertTo-AutopilotConfigJson(){

    [cmdletbinding()]
    param
    (
            [Parameter(Mandatory=$true,ValueFromPipeline=$True)]
            [Object] $profile,
            [Parameter(Mandatory=$true)]
            [Object] $accessToken
    )
    
      Begin {
    
        # Set the org-related info
        $script:TenantOrg = ( Invoke-RestMethod -Uri "https://graph.microsoft.com/beta/organization" -Headers @{Authorization ="Bearer $($accessToken.access_token)"} -Method Get ).Value
        $script:TenantDomain = ( $script:TenantOrg.VerifiedDomains | Where-Object {$_.isDefault -eq "True"} ).Name
        
      }
    
      Process {
    
        $oobeSettings = $profile.outOfBoxExperienceSettings
    
        # Build up properties
        $json = @{}
        $json.Add("Comment_File", "Profile $($_.displayName)")
        $json.Add("Version", 2049)
        $json.Add("ZtdCorrelationId", $_.id)
        if ($profile."@odata.type" -eq "#microsoft.graph.activeDirectoryWindowsAutopilotDeploymentProfile")
        {
            $json.Add("CloudAssignedDomainJoinMethod", 1)
        }
        else
        {
            $json.Add("CloudAssignedDomainJoinMethod", 0)
        }
        if ($profile.deviceNameTemplate)
        {
            $json.Add("CloudAssignedDeviceName", $_.deviceNameTemplate)
        }
    
        # Figure out config value
        $oobeConfig = 8 + 256
        if ($oobeSettings.userType -eq 'standard') {
            $oobeConfig += 2
        }
        if ($oobeSettings.hidePrivacySettings -eq $true) {
            $oobeConfig += 4
        }
        if ($oobeSettings.hideEULA -eq $true) {
            $oobeConfig += 16
        }
        if ($oobeSettings.skipKeyboardSelectionPage -eq $true) {
            $oobeConfig += 1024
        if ($_.language) {
                $json.Add("CloudAssignedLanguage", $_.language)
            }
        }
        if ($oobeSettings.deviceUsageType -eq 'shared') {
            $oobeConfig += 32 + 64
        }
        $json.Add("CloudAssignedOobeConfig", $oobeConfig)
    
        # Set the forced enrollment setting
        if ($oobeSettings.hideEscapeLink -eq $true) {
            $json.Add("CloudAssignedForcedEnrollment", 1)
        }
        else {
            $json.Add("CloudAssignedForcedEnrollment", 0)
        }
    
        $json.Add("CloudAssignedTenantId", $script:TenantOrg.id)
        $json.Add("CloudAssignedTenantDomain", $script:TenantDomain)
        $embedded = @{}
        $embedded.Add("CloudAssignedTenantDomain", $script:TenantDomain)
        $embedded.Add("CloudAssignedTenantUpn", "")
        if ($oobeSettings.hideEscapeLink -eq $true) {
            $embedded.Add("ForcedEnrollment", 1)
        }
        else
        {
            $embedded.Add("ForcedEnrollment", 0)
        }
        $ztc = @{}
        $ztc.Add("ZeroTouchConfig", $embedded)
        $json.Add("CloudAssignedAadServerData", (ConvertTo-JSON $ztc -Compress))
    
        # Skip connectivity check
        if ($profile.hybridAzureADJoinSkipConnectivityCheck -eq $true) {
            $json.Add("HybridJoinSkipDCConnectivityCheck", 1)
        }
    
        # Hard-code properties not represented in Intune
        $json.Add("CloudAssignedAutopilotUpdateDisabled", 1)
        $json.Add("CloudAssignedAutopilotUpdateTimeout", 1800000)
    
        # Return the JSON
        ConvertTo-JSON $json
      }
    
    }

If(!(Test-Path "$psscriptroot\AutopilotConfigurationFile.json")) {

    $token = Get-AccessToken

    $graphUrl = "https://graph.microsoft.com"
    $betaEndpoint = "$graphUrl/beta"
    $autopilotProfileUrl = "$betaEndpoint/deviceManagement/windowsAutopilotDeploymentProfiles"

    $autopilotProfiles = ( Invoke-RestMethod -Uri $autopilotProfileUrl -Headers @{Authorization ="Bearer $($token.access_token)"} -Method Get ).Value

    If($autopilotProfiles.Count -gt 1) {
        For($i = 0; $i -lt $autopilotProfiles.Count; $i++) {
            Write-Host "$($i): $($autopilotProfiles[$i].displayName)"
            }
        $selection = Read-Host -Prompt "Enter number of profile to apply."
        $autopilotProfiles = $autopilotProfiles[$selection]

    } elseif($autopilotProfiles.Count -lt 1) {

        Write-Host "There doesn't seem to be an Autopilot profile. Either I didn't pull the profile correctly or Autopilot isn't configured. Check that and try again. Bye friend."
        Exit

    }

    $json = $autopilotProfiles | ConvertTo-AutopilotConfigJson -accessToken $token
    $json | Out-File "$psscriptroot\AutopilotConfigurationFile.json"

}

Copy-Item "$psscriptroot\AutopilotConfigurationFile.json" "$env:windir\Windows\Provisioning\Autopilot\"