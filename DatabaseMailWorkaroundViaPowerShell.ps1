param (
    [string]$SqlServerInstance = ".",
    [string]$LogFilePath       = "C:\Temp\DatabaseMailWorkaround.log",
    [int]$BatchSize            = 50,
    [switch]$VerboseLogging    = $true
)

Import-Module SqlServer -ErrorAction SilentlyContinue
if (-not (Get-Module -Name SqlServer)) {
    Write-Error "SqlServer module missing. Run: Install-Module -Name SqlServer -Scope AllUsers"
    exit 1
}

function Log-Message {
    param ([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    if ($VerboseLogging) { Write-Host $logEntry }
    Add-Content -Path $LogFilePath -Value $logEntry -ErrorAction SilentlyContinue
}

$connStr = "Server=$SqlServerInstance;Database=msdb;Integrated Security=True;TrustServerCertificate=True;"
Invoke-Sqlcmd -ConnectionString $connStr -Query "SELECT @@VERSION"

$createLogTableQuery = @"
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'WorkaroundMailLog')
CREATE TABLE msdb.dbo.WorkaroundMailLog (
    LogId INT IDENTITY(1,1) PRIMARY KEY,
    MailItemId INT NOT NULL,
    ProcessedDate DATETIME NOT NULL DEFAULT GETDATE(),
    Status VARCHAR(50) NOT NULL,
    ErrorMessage NVARCHAR(MAX) NULL
);
"@
Invoke-Sqlcmd -ConnectionString $connStr -Query $createLogTableQuery -ErrorAction Stop
Log-Message "Custom logging table ensured."

$unsentMailsQuery = @"
SELECT TOP $BatchSize 
    mi.mailitem_id,
    mi.profile_id,
    mi.recipients,
    mi.copy_recipients,
    mi.blind_copy_recipients,
    mi.subject,
    mi.body,
    mi.body_format,
    mi.importance,
    mi.file_attachments,
    mi.from_address
FROM msdb.dbo.sysmail_mailitems mi
LEFT JOIN msdb.dbo.WorkaroundMailLog log ON mi.mailitem_id = log.MailItemId
WHERE mi.sent_status IN (0, 2)
  AND log.MailItemId IS NULL
ORDER BY mi.send_request_date ASC;
"@
$unsentMails = Invoke-Sqlcmd -ConnectionString $connStr -Query $unsentMailsQuery
Log-Message "Found $($unsentMails.Count) unsent mail items to process."

foreach ($mail in $unsentMails) {
    $mailId = $mail.mailitem_id
    Log-Message "Processing mailitem_id: $mailId" "DEBUG"

    try {
        $profileQuery = "SELECT name AS ProfileName FROM msdb.dbo.sysmail_profile WHERE profile_id = $($mail.profile_id);"
        $profile = Invoke-Sqlcmd -ConnectionString $connStr -Query $profileQuery
        if (-not $profile) { throw "Profile ID $($mail.profile_id) not found." }
        Log-Message "Using profile: $($profile.ProfileName)" "DEBUG"

        $accountQuery = @"
        SELECT TOP 1
            a.email_address,
            a.display_name,
            s.servername AS SmtpServer,
            s.port,
            s.username,
            s.enable_ssl
        FROM msdb.dbo.sysmail_profileaccount pa
        INNER JOIN msdb.dbo.sysmail_account a ON pa.account_id = a.account_id
        INNER JOIN msdb.dbo.sysmail_server s ON a.account_id = s.account_id
        WHERE pa.profile_id = $($mail.profile_id)
        ORDER BY pa.sequence_number ASC;
"@
        $account = Invoke-Sqlcmd -ConnectionString $connStr -Query $accountQuery
        if (-not $account) { throw "No account/server for profile ID $($mail.profile_id)." }

        $from = if ($mail.from_address -and $mail.from_address -isnot [System.DBNull]) { $mail.from_address } else { $account.email_address }

        if ($account.display_name -and $account.display_name -isnot [System.DBNull] -and $account.display_name.Trim() -ne '') {
            Log-Message "Skipping display name '$($account.display_name)' to avoid header errors - using plain email: $from" "WARN"
        }

        $to   = if ($mail.recipients)          { ($mail.recipients -split ';' | ForEach-Object { $_.Trim() }) | Where-Object { $_ -ne '' } } else { @() }
        $cc   = if ($mail.copy_recipients)     { ($mail.copy_recipients -split ';' | ForEach-Object { $_.Trim() }) | Where-Object { $_ -ne '' } } else { $null }
        $bcc  = if ($mail.blind_copy_recipients) { ($mail.blind_copy_recipient -split ';' | ForEach-Object { $_.Trim() }) | Where-Object { $_ -ne '' } } else { $null }

        $attachments = if ($mail.file_attachments) { ($mail.file_attachments -split ';' | ForEach-Object { $_.Trim() }) | Where-Object { $_ -ne '' } } else { $null }

        $priority = switch ($mail.importance) {
            'Low'   { 'Low' }
            'High'  { 'High' }
            default { 'Normal' }
        }

        $cred = $null
        $username = $account.username
        if ($username -and $username -isnot [System.DBNull] -and $username.Trim() -ne '') {
            Log-Message "Username found but no password → attempting without creds (relay mode)" "WARN"
        } else {
            Log-Message "No username → anonymous/relay SMTP" "INFO"
        }

        $sendParams = @{
            From       = $from
            To         = $to
            Subject    = $mail.subject
            Body       = $mail.body
            SmtpServer = $account.SmtpServer
            Port       = $account.port
            UseSsl     = [bool]$account.enable_ssl
            Priority   = $priority
            ErrorAction= 'Stop'
        }

        if ($cc)                  { $sendParams['Cc']          = $cc }
        if ($bcc)                 { $sendParams['Bcc']         = $bcc }
        if ($attachments)         { $sendParams['Attachments'] = $attachments }
        if ($mail.body_format -eq 'HTML') { $sendParams['BodyAsHtml'] = $true }

        if ($cred) { $sendParams['Credential'] = $cred }

        Send-MailMessage @sendParams
        Log-Message "Successfully sent mailitem_id: $mailId"

        $updateQuery = "UPDATE msdb.dbo.sysmail_mailitems SET sent_status = 1, sent_date = GETDATE() WHERE mailitem_id = $mailId;"
        Invoke-Sqlcmd -ConnectionString $connStr -Query $updateQuery

        $logQuery = "INSERT INTO msdb.dbo.WorkaroundMailLog (MailItemId, Status) VALUES ($mailId, 'Sent');"
        Invoke-Sqlcmd -ConnectionString $connStr -Query $logQuery

    } catch {
        $errMsg = $_.Exception.Message
        Log-Message "Failed mailitem_id: $mailId. Error: $errMsg" "ERROR"

        $updateQuery = "UPDATE msdb.dbo.sysmail_mailitems SET sent_status = 3, last_mod_date = GETDATE() WHERE mailitem_id = $mailId;"
        Invoke-Sqlcmd -ConnectionString $connStr -Query $updateQuery

        $safeErr = $errMsg.Replace("'", "''")
        $logQuery = "INSERT INTO msdb.dbo.WorkaroundMailLog (MailItemId, Status, ErrorMessage) VALUES ($mailId, 'Failed', '$safeErr');"
        Invoke-Sqlcmd -ConnectionString $connStr -Query $logQuery
    }
}

Log-Message "Script execution completed."