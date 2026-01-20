Database Mail Workaround for SQL Server 2022
This repository contains a PowerShell script that serves as a workaround for the Database Mail issue in SQL Server 2022 (CU22/CU23) where DatabaseMail.exe fails due to a missing internal assembly (Microsoft.SqlServer.DatabaseMail.XEvents).
The script polls unsent mail items from msdb.dbo.sysmail_mailitems, sends them using Send-MailMessage, updates their status, and logs the process. It's designed to be transparent to SQL Agent jobs and sp_send_dbmail calls.
Features

Dynamic handling of multiple Database Mail profiles and accounts.
Supports text/HTML bodies, attachments, priorities, CC/BCC.
Duplicate prevention via a custom logging table (WorkaroundMailLog).
Anonymous/relay SMTP mode (no credentials needed if configured that way).
Compatible with PowerShell 5.1 (default on Windows Server 2016+).

Prerequisites

SQL Server 2022 (or compatible) with access to msdb database.
PowerShell 5.1+ (built-in on Windows Server).
Permissions: Run as an account with read/write access to msdb (e.g., SQL Server service account).
SMTP server configured for anonymous/relay from the script's host.

Installation and Setup

Clone the Repositorytextgit clone https://github.com/yourusername/database-mail-workaround.git
cd database-mail-workaround
Install Required Modules (Run in elevated PowerShell)
Step 1: Enable TLS 1.2 (for older servers to access PowerShell Gallery):text[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Step 2: Install NuGet Provider (required for module installation):textInstall-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Step 3: Install SqlServer Module (for Invoke-Sqlcmd):textInstall-Module -Name SqlServer -Force -AllowClobber -Scope AllUsers
If prompted, trust the PSGallery repository (type 'Y').
Verify: Get-Module -ListAvailable SqlServer.


Configure the Script
Edit DatabaseMailWorkaround.ps1:
Set $SqlServerInstance to your SQL instance (e.g., ".", "SERVER\INSTANCE", or FQDN).
Adjust $LogFilePath for logging (e.g., "C:\Logs\DatabaseMailWorkaround.log").
If your SMTP requires credentials: Uncomment and add secure password logic in the credentials section.

If SSL errors occur with Invoke-Sqlcmd, use:textInvoke-Sqlcmd -ConnectionString "Server=$SqlServerInstance;Database=msdb;Integrated Security=True;TrustServerCertificate=True;" -Query $query


Usage

Run Manually (for testing):text.\DatabaseMailWorkaround.ps1
Schedule via Task Scheduler (for production):
Open Task Scheduler → Create Task.
General: Run with highest privileges; Run whether user logged on or not.
Trigger: Every 2-5 minutes (repeat indefinitely).
Action: Start a program → powershell.exe
Arguments: -ExecutionPolicy Bypass -File "C:\Path\To\DatabaseMailWorkaround.ps1"
Use the SQL service account or equivalent.

Monitoring
Check logs: Open $LogFilePath.
Query custom table:SQLSELECT * FROM msdb.dbo.WorkaroundMailLog ORDER BY ProcessedDate DESC;
Verify sent mails:SQLSELECT * FROM msdb.dbo.sysmail_mailitems WHERE sent_status = 1;


Troubleshooting

Module Not Found: Reinstall SqlServer module (see Installation).
SSL/Connection Errors: Use TrustServerCertificate=True in connection string.
SMTP Auth Required: Add credentials in the script (use app passwords for security).
No Mails Sent: Ensure unsent items exist (SELECT * FROM msdb.dbo.sysmail_mailitems WHERE sent_status IN (0,2);).
Display Name Issues: Script uses plain email for From; upgrade to PowerShell 7 for better header support if needed.

Limitations

Skips advanced features like custom Reply-To or sensitivity headers (due to PowerShell 5.1 limits).
Assumes anonymous SMTP; customize for authenticated servers.
Not a permanent fix — monitor for Microsoft CU/hotfix.

Contributing
Feel free to fork, submit PRs, or report issues. Tested on Windows Server 2016+ with SQL 2022.
License
MIT License — free to use/modify.
