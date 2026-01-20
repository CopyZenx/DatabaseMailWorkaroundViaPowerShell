Here’s a beautifully formatted README.md file optimized for GitHub's Markdown rendering (with headers, badges, tables, code blocks, emojis, and sections for great visual appeal). You can copy-paste this directly into your repository's README.md.
Markdown<div align="center">

# - Database Mail Workaround for SQL Server 2022

**A seamless PowerShell-based replacement for the broken DatabaseMail.exe in SQL Server 2022 CU22/CU23**

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue?logo=powershell&logoColor=white)](https://learn.microsoft.com/powershell/)
[![SQL Server](https://img.shields.io/badge/SQL%20Server-2022-orange?logo=microsoftsqlserver&logoColor=white)](https://www.microsoft.com/sql-server/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

</div>

## - The Problem

After applying **SQL Server 2022 Cumulative Update 22 or 23**, Database Mail fails with:
Could not load file or assembly 'Microsoft.SqlServer.DatabaseMail.XEvents, Version=16.0.0.0...'
The system cannot find the file specified.
textMicrosoft confirmed this is a **known packaging issue** — the referenced assembly is **not shipped** in the installation package, and it depends on update/installation paths.

## - The Solution

This repository provides a **transparent PowerShell workaround** that:

- Polls unsent mail items from `msdb.dbo.sysmail_mailitems`
- Dynamically reads profiles, accounts, and SMTP settings
- Sends emails using `Send-MailMessage` (anonymous/relay mode by default)
- Updates `sent_status = 1` and logs to a custom table
- Runs every few minutes via Task Scheduler

**No changes needed in your SQL Agent jobs or application code!**

## - Features

- Works with **multiple Database Mail profiles** and accounts
- Supports **HTML/plain text**, attachments, CC/BCC, priorities
- Prevents duplicate sends with custom logging table (`WorkaroundMailLog`)
- Fully compatible with **PowerShell 5.1** (default on Windows Server)
- Easy to schedule and monitor

## - Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/database-mail-workaround.git
cd database-mail-workaround
2. Install Required PowerShell Module (elevated PowerShell)
PowerShell# Enable TLS 1.2 (important for older servers)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Install NuGet provider
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force

# Install SqlServer module (system-wide)
Install-Module -Name SqlServer -Force -AllowClobber -Scope AllUsers
Accept the PSGallery prompt if asked (type 'Y').
3. Configure & Run the Script

Edit DatabaseMailWorkaround.ps1:
Set $SqlServerInstance (e.g. ".", "SQLSERVER01", or FQDN)
Adjust $LogFilePath (e.g. "C:\Logs\DatabaseMailWorkaround.log")

Test manually:PowerShell.\DatabaseMailWorkaround.ps1

4. Schedule It (Recommended for Production)
Use Task Scheduler:

Trigger: Every 2–5 minutes
Action: powershell.exe -ExecutionPolicy Bypass -File "C:\Path\To\DatabaseMailWorkaround.ps1"
Run with highest privileges and the SQL service account

- Monitoring & Logs

Log file: Check $LogFilePath for detailed activity
Custom table:SQLSELECT * FROM msdb.dbo.WorkaroundMailLog
ORDER BY ProcessedDate DESC;

- Troubleshooting





























IssueSolutionSqlServer module missingRun the install commands aboveSSL connection errorAdd TrustServerCertificate=True to connection stringSMTP requires authenticationUncomment and add secure credential logic in scriptEmails not arrivingVerify SMTP relay allows the server IP; check logsInvalid header '<' errorScript already uses plain email (no display name) to avoid this
- Limitations

Advanced headers (Reply-To, sensitivity) not supported in PowerShell 5.1
Designed for anonymous/relay SMTP (add credentials if needed)
Temporary workaround — watch for official Microsoft fix in future CUs

- Contributing
Pull requests, issues, and stars are welcome!
Tested on Windows Server 2016+ with SQL Server 2022.
- License
MIT License – feel free to use and modify.
