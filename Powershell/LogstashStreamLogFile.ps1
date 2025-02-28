$global:tcpClient = $null
$global:stream = $null
$global:writer = $null

function Initialize-LogstashConnection {
    param (
        [string]$LogstashServer,
        [int]$LogstashPort
    )
    
    if ($null -eq $global:tcpClient ) {
        $global:tcpClient = New-Object System.Net.Sockets.TcpClient
        $global:tcpClient.Connect($LogstashServer, $LogstashPort)
        $global:stream = $global:tcpClient.GetStream()
        $global:writer = New-Object System.IO.StreamWriter($global:stream)
        $global:writer.AutoFlush = $true
    }
}

function Send-LogstashEventTCP ($message, $processingFile) {
    if ($null -eq $global:writer ) {
        $global:writer.WriteLine($Message)
    } else {
        Write-host "Connection broke, quiting."
        write-host "File that was being processed: $($processingFile.name)"
        write-host "Will rename file to INCOMPLETE"
        Rename-Item -Path $processingFile.fullname -NewName "$($processingFile.name.Split('.')[0])-INCOMPLETE.log"
        break
    }
}

function Close-LogstashConnection {
    if ($null -eq $global:writer ) {
        $global:writer.Close()
    }
    if ($null -eq $global:stream ) {
        $global:stream.Close()
    }
    if ($null -eq $global:tcpClient ) {
        $global:tcpClient.Close()
    }
    
    $global:writer = $null
    $global:stream = $null
    $global:tcpClient = $null
}

$endpointServer = ""
$endpointPort   = 5016

write-host "Opening TCP connection to $($endpointServer)"
Initialize-LogstashConnection -LogstashServer $endpointServer -LogstashPort $endpointPort

write-host 'Collecting Files to process' -ForegroundColor Yellow
$LogFilesToProcess = Get-ChildItem -Path 'L:\IISLogs' | ? {$_.name -notmatch "COMPLETED"} | sort LastWriteTime 
write-host "Files collected: $($LogFilesToProcess.count)"

$count = 0
foreach ($fileToProcess in $LogFilesToProcess) {
    write-host "`nGetting data from file: $($fileToProcess.name) at $($fileToProcess.FullName)"
    #$logFile = Get-Content -Path $fileToProcess.fullname #| ConvertFrom-Csv

    write-host "Data collection completed."
    Write-Host "sending $($fileToProcess.fullname) with $($logFile.count) messages"

    # stream line the reading of file, better at handling memory
    $logFileReader = [system.io.streamreader]::new("$($fileToProcess.FullName)") 
    try {
        while (($line = $logFileReader.ReadLine()) -ne $null) {
            Send-LogstashEventTCP -Message $line -processingFile $($fileToProcess)
            $count ++
        }
    } finally {
        $logFileReader.Close()
    }

    write-host "$($count) Messages sent. Renaming File to Completed." -ForegroundColor Green
    Rename-Item -Path $fileToProcess.fullname -NewName "$($fileToProcess.name.Split('.')[0])-COMPLETED.log"
    $count = 0
}

write-host 'Processing completed.' -ForegroundColor Yellow

write-host "Closing TCP connection"

Close-LogstashConnection
