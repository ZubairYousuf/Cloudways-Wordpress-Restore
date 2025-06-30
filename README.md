# WordPress Restore Script for Cloudways

## 📜 Description

This Bash script automates the restoration of a WordPress website on a Cloudways-hosted server.
It handles database import, file extraction, configuration updates, and search-replace operations for domain and file path references.

This script is designed to work with backups created by the companion tool: wordpress-backup-tool.
Use that script to generate a complete .tar.gz backup of your site (including database and path metadata), which can then be restored seamlessly using this script.


## 🚀 Features

- Auto-detect destination site URL
- Extract and import database from `.tar.gz`
- Modify wp-config with destination credentials
- Optional public_html cleanup before restore
- Path replacement between old and new directories (optional `wp-content` exclusion)
- Full search-replace for all source and destination URLs
- Cache flush at the end

## 📂 Structure

- `wp-config.php` is auto-updated with destination database credentials and URLs.
- Source backup should be in format: `https://source-domain.com/source-domain.tar.gz`
- Database should be located inside `.backup_meta/db_backup.tar.gz`

## 🛠️ Usage

### 1. Upload `test.sh` to any Cloudways app's `public_html`

```bash
chmod u+x test.sh
./test.sh
```

### 2. Prompts & Flow

You will be asked for the following:

- Destination app name (DB name)
- Confirmation to wipe existing `public_html`
- Source domain (without https)
- Whether to exclude `wp-content` from path replacements
- Source URL for domain replacements

### 3. Requirements

- WP-CLI must be installed (`wp` command must be available)
- Script should be executed as the master user (or a user with wp-cli and DB import rights)

## 📦 Output

At the end of the script:

- Your WordPress site is restored and updated.
- Old references to domain and filesystem paths are replaced.
- WP cache is flushed.

## 🔐 Safety

- A backup of `wp-config.php` is created before wiping files (if selected).
- Skips deletion of the script itself during wipe.

---

## 💡 Notes

- Be sure to run the [store_source_path.sh] script on the source before generating archive.
- Ensure `.backup_meta/db_backup.tar.gz` contains `db_backup.sql`.
---

### Author
**Zubair Yousuf**

**Last Updated: June 30, 2025**
