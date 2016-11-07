﻿function Import-GoogSheet {
    [cmdletbinding(DefaultParameterSetName="SheetsAPI")]
    Param
    (      
      [parameter(Mandatory=$true)]
      [String]
      $SpreadsheetId,
      [parameter(Mandatory=$false)]
      [ValidateNotNullOrEmpty()]
      [String]
      $Owner = $Script:PSGoogle.AdminEmail,
      [parameter(ParameterSetName="DriveAPI",Mandatory=$false)]
      [switch]
      $UseDriveAPI,
      [parameter(ParameterSetName="SheetsAPI",Mandatory=$false)]
      [ValidateNotNullOrEmpty()]
      [string]
      $SpecifyRange="A1:Z1000",
      [parameter(ParameterSetName="SheetsAPI",Mandatory=$false)]
      [ValidateSet("FORMATTED_STRING","SERIAL_NUMBER")]
      [string]
      $DateTimeRenderOption="FORMATTED_STRING",
      [parameter(ParameterSetName="SheetsAPI",Mandatory=$false)]
      [ValidateSet("FORMATTED_VALUE","UNFORMATTED_VALUE","FORMULA")]
      [string]
      $ValueRenderOption="FORMATTED_VALUE",
      [parameter(ParameterSetName="SheetsAPI",Mandatory=$false)]
      [ValidateSet("ROWS","COLUMNS","DIMENSION_UNSPECIFIED")]
      [string]
      $MajorDimension="ROWS",
      [parameter(ParameterSetName="SheetsAPI",Mandatory=$false)]
      [int]
      $RowStart=1,
      [parameter(ParameterSetName="SheetsAPI",Mandatory=$false)]
      [switch]
      $Raw,
      [parameter(Mandatory=$false)]
      [String]
      $AccessToken,
      [parameter(Mandatory=$false)]
      [ValidateNotNullOrEmpty()]
      [String]
      $P12KeyPath = $Script:PSGoogle.P12KeyPath,
      [parameter(Mandatory=$false)]
      [ValidateNotNullOrEmpty()]
      [String]
      $AppEmail = $Script:PSGoogle.AppEmail,
      [parameter(Mandatory=$false)]
      [ValidateNotNullOrEmpty()]
      [String]
      $AdminEmail = $Script:PSGoogle.AdminEmail
    )
if ($UseDriveAPI)
    {
    $TempCSV = "$env:TEMP\PSGoogle-TempCSV-$((New-Guid).Guid).csv"
    $fileParams = @{
        FileID=$SpreadsheetId
        Owner=$Owner
        Type="CSV"
        OutFilePath=$TempCSV 
        }
    if ($AccessToken)
        {
        $fileParams.Add("AccessToken",$AccessToken)
        }
    else 
        {
        $fileParams.Add("P12KeyPath",$P12KeyPath)
        $fileParams.Add("AppEmail",$AppEmail)
        $fileParams.Add("AdminEmail",$AdminEmail)
        }
    Write-Verbose "Downloading temp CSV to: $TempCSV"
    Get-GoogDriveFile @fileParams -Verbose:$false
    Write-Verbose "Importing temp CSV"
    $response = Import-Csv $TempCSV
    Write-Verbose "Removing temp CSV"
    Remove-Item $TempCSV -Force
    }
else
    {
    if ($MajorDimension -ne "ROWS")
        {
        $Raw = $true
        Write-Warning "Setting -Raw to True -- Parsing requires the MajorDimension to be set to ROWS (default value)"
        }
    if (!$AccessToken)
        {
        $AccessToken = Get-GoogToken -P12KeyPath $P12KeyPath -Scopes "https://www.googleapis.com/auth/drive" -AppEmail $AppEmail -AdminEmail $Owner
        }
    $header = @{
        Authorization="Bearer $AccessToken"
        }
    $URI = "https://sheets.googleapis.com/v4/spreadsheets/$SpreadsheetId/values/$SpecifyRange`?dateTimeRenderOption=$DateTimeRenderOption&majorDimension=$MajorDimension&valueRenderOption=$ValueRenderOption"
    try
        {
        $response = Invoke-RestMethod -Method Get -Uri $URI -Headers $header -ContentType "application/json"
        if (!$Raw)
            {
            $response = $(if ($RowStart){$response.values | Select -Skip $([int]$RowStart -1)}else{$response.values}) | 
                % {
                    $i=0
                    $cont = $true
                    if ($_[$i])
                        {
                        $row="`"$($_[$i])`""
                        $i++
                        }
                    else
                        {
                        $cont = $false
                        }
                    while ($cont)
                        {
                        if ($_[$i])
                            {
                            $row+=",`"$($_[$i])`""
                            }
                        else
                            {
                            $cont = $false
                            }
                        $i++
                        }
                    $row
                    } | 
                ConvertFrom-Csv
            }
        }
    catch
        {
        try
            {
            $result = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($result)
            $reader.BaseStream.Position = 0
            $reader.DiscardBufferedData()
            $resp = $reader.ReadToEnd()
            $response = $resp | ConvertFrom-Json | 
                Select-Object @{N="Error";E={$Error[0]}},@{N="Code";E={$_.error.Code}},@{N="Message";E={$_.error.Message}},@{N="Domain";E={$_.error.errors.domain}},@{N="Reason";E={$_.error.errors.reason}}
            }
        catch
            {
            $response = $resp
            }
        }
    }
return $response
}