#!/bin/bash

echo "🟢 Starting WordPress Restore Script (Cloudways Destination Server)"

read -p "🔹 Enter destination app name (Cloudways DB name): " app_name

dest_path="/home/master/applications/${app_name}/public_html"
priv_path="/home/master/applications/${app_name}/private_html"

# Step 1: Move to public_html
cd "$dest_path" || { echo "❌ Destination path not found."; exit 1; }

# Step 2: Detect destination site URL
site_url=$(wp option get siteurl 2>/dev/null)
if [[ -z "$site_url" ]]; then
  echo "⚠️ Could not auto-detect destination site URL."
  read -p "🌐 Please manually enter the destination site URL (with https): " site_url
else
  site_url=${site_url/http:/https:}
  echo "🌐 Detected destination site URL: $site_url"
fi

# Step 3: Detect or manually enter destination DB credentials
if [[ -f "wp-config.php" ]]; then
  wp_db_name=$(awk -F"'" '/DB_NAME/{print $4}' wp-config.php)
  wp_db_user=$(awk -F"'" '/DB_USER/{print $4}' wp-config.php)
  wp_db_pass=$(awk -F"'" '/DB_PASSWORD/{print $4}' wp-config.php)
  wp_db_host=$(awk -F"'" '/DB_HOST/{print $4}' wp-config.php | cut -d':' -f1)
  wp_db_port=$(awk -F"'" '/DB_HOST/{print $4}' wp-config.php | cut -s -d':' -f2)
  wp_prefix=$(awk -F"'" '/\$table_prefix/{print $2}' wp-config.php)
else
  echo "⚠️ wp-config.php not found, collecting DB credentials manually."
  read -p "📛 Enter DB Name: " wp_db_name
  read -p "👤 Enter DB User: " wp_db_user
  read -p "🔑 Enter DB Password: " wp_db_pass
  read -p "🖥️ Enter DB Host (e.g., 127.0.0.1): " wp_db_host
  read -p "🔌 Enter DB Port (default 3306): " wp_db_port
  wp_prefix="wp_"
fi
[ -z "$wp_db_port" ] && wp_db_port=3306

# Step 4: Ask if you want to wipe current files
read -p "🧼 Do you want to remove all current public_html files before restore? (y/n): " wipe_choice
if [[ "$wipe_choice" =~ ^[Yy]$ ]]; then
  echo "🧼 Wiping public_html..."
  mkdir -p "$priv_path"
  cp wp-config.php "$priv_path/wp-config-restore.bak"
  # Safely delete all except test.sh
  find "${dest_path:?}" -mindepth 1 ! -name 'test.sh' -exec rm -rf {} +
fi

# Step 5: Download and extract archive
read -p "🌍 Enter source domain (without https): " source_site

echo "📥 Downloading https://${source_site}/${source_site}.tar.gz..."
wget "https://${source_site}/${source_site}.tar.gz" --no-check-certificate || { echo "❌ Download failed."; exit 1; }

echo "📦 Extracting archive..."
tar -xzvf "${source_site}.tar.gz" || { echo "❌ Extraction failed."; exit 1; }

# Step 6: Update wp-config.php in the extracted files
if [[ -f "wp-config.php" ]]; then
  echo "⚙️ Replacing DB credentials in extracted wp-config.php..."
  sed -i "s/define('DB_NAME', *'.*');/define('DB_NAME', '$wp_db_name');/" wp-config.php
  sed -i "s/define('DB_USER', *'.*');/define('DB_USER', '$wp_db_user');/" wp-config.php
  sed -i "s/define('DB_PASSWORD', *'.*');/define('DB_PASSWORD', '$wp_db_pass');/" wp-config.php
  sed -i "s/define('DB_HOST', *'.*');/define('DB_HOST', '$wp_db_host:$wp_db_port');/" wp-config.php
  sed -i "/DB_COLLATE/a\define('WP_HOME', '$site_url');"
fi

# Step 7: Replacing Source path with destination path.
# Ensure source path file exists
if [ ! -f source_path.txt ]; then
  echo "❌ Error: source_path.txt not found. Please run store_source_path.sh first."
  exit 1
fi

# Read old source path from file
OLD_PATH=$(cat source_path.txt)
NEW_PATH=${dest_path:?}  # Use predefined destination path

# Ask whether to skip wp-content
read -p "🎯 Do you want to skip the 'wp-content' directory during path replacement? (yes/no): " SKIP_WP

# Run path replacement
if [[ "$SKIP_WP" == "yes" ]]; then
  echo "🔁 Replacing '$OLD_PATH' with '$NEW_PATH' in all files except 'wp-content'..."
  find "$dest_path" -path "$dest_path/wp-content" -prune -o -type f -exec sed -i "s#$OLD_PATH#$NEW_PATH#g" {} +
else
  echo "🔁 Replacing '$OLD_PATH' with '$NEW_PATH' in all files including 'wp-content'..."
  find "$dest_path" -type f -exec sed -i "s#$OLD_PATH#$NEW_PATH#g" {} +
fi

echo "✅ Path replacement completed successfully."


# Step 8: Extract and import database
if [[ -f ".backup_meta/db_backup.tar.gz" ]]; then
  echo "📂 Extracting database backup..."
  tar -xzvf .backup_meta/db_backup.tar.gz  || { echo "❌ Failed to extract DB backup."; exit 1; }

  if [[ -f "db_backup.sql" ]]; then
    echo "🛠️ Importing database..."
    mysql -h "$wp_db_host" -P "$wp_db_port" -u "$wp_db_user" -p"$wp_db_pass" "$wp_db_name" < db_backup.sql || { echo "❌ Database import failed."; exit 1; }
  else
    echo "❌ db_backup.sql not found after extraction."
    exit 1
  fi
else
  echo "❌ .backup_meta/db_backup.tar.gz not found. Exiting."
  exit 1
fi

# Step 9: Cleanup
read -p "🧹 Do you want to delete the DB backup and archive files? (y/n): " clean_choice
if [[ "$clean_choice" =~ ^[Yy]$ ]]; then
  echo "🧹 Cleaning up files..."
  rm -f "${source_site}.tar.gz" db_backup.sql
  rm -rf .backup_meta
fi

# Step 10: Ask for source URL to perform search-replace
read -p "🔁 Enter source site URL (without https and www): " source_url

echo "🔄 Running search-replace from https://${source_url} ➜ $site_url"
# Replace https://source.com ➜ destination
wp search-replace "https://${source_url}" "$site_url" --all-tables

# Replace http://source.com ➜ destination
wp search-replace "http://${source_url}" "$site_url" --all-tables

# Replace https://www.source.com ➜ destination
wp search-replace "https://www.${source_url}" "$site_url" --all-tables

# Replace http://www.source.com ➜ destination
wp search-replace "http://www.${source_url}" "$site_url" --all-tables

# Step 11: Flush cache
echo "🚿 Flushing WordPress cache..."
wp cache flush

echo "✅ WordPress site successfully restored from https://${source_url} to $site_url"
[master_kbxmhytfrf]:public_html$ test.sh
bash: test.sh: command not found
[master_kbxmhytfrf]:public_html$ read -p "🔁 Enter source site URL (without https): " source_url
source_url="https://${source_url}"

echo "🔄 Running search-replace from $source_url^C
[master_kbxmhytfrf]:public_html$ nano test.sh
[master_kbxmhytfrf]:public_html$ chmod u+x test
chmod: cannot access 'test': No such file or directory
[master_kbxmhytfrf]:public_html$ chmod u+x test.sh
[master_kbxmhytfrf]:public_html$ ./test.sh
🔁 Enter source site URL (without https): wordpress-1472141-5567149.cloudwaysapps.com


[master_kbxmhytfrf]:public_html$ ./test.sh
🔁 Enter source site URL (without https): wordpress-1472141-5567149.cloudwaysapps.com
🔄 Running search-replace from https://wordpress-1472141-5567149.cloudwaysapps.com
[master_kbxmhytfrf]:public_html$ > test.sh
[master_kbxmhytfrf]:public_html$ nano test.sh
[master_kbxmhytfrf]:public_html$ cat test.sh
#!/bin/bash

echo "🟢 Starting WordPress Restore Script (Cloudways Destination Server)"

# Step 1: Ask for app name
read -p "🔹 Enter destination app name (Cloudways DB name): " app_name

dest_path="/home/master/applications/${app_name}/public_html"
priv_path="/home/master/applications/${app_name}/private_html"

# Step 2: Move to public_html
cd "$dest_path" || { echo "❌ Destination path not found."; exit 1; }

# Step 3: Detect destination site URL
site_url=$(wp option get siteurl 2>/dev/null | sed -E 's~^https?://~~')
if [[ -z "$site_url" ]]; then
  echo "⚠️ Could not auto-detect destination site URL."
  read -p "🌐 Please manually enter the destination site URL (without https): " site_url
fi
site_url="https://${site_url}"
echo "🌐 Using destination site URL: $site_url"

# Step 4: Extract DB credentials
if [[ -f "wp-config.php" ]]; then
  wp_db_name=$(awk -F"'" '/DB_NAME/{print $4}' wp-config.php)
  wp_db_user=$(awk -F"'" '/DB_USER/{print $4}' wp-config.php)
  wp_db_pass=$(awk -F"'" '/DB_PASSWORD/{print $4}' wp-config.php)
  wp_db_host=$(awk -F"'" '/DB_HOST/{print $4}' wp-config.php | cut -d':' -f1)
  wp_db_port=$(awk -F"'" '/DB_HOST/{print $4}' wp-config.php | cut -s -d':' -f2)
  wp_prefix=$(awk -F"'" '/\$table_prefix/{print $2}' wp-config.php)
else
  echo "⚠️ wp-config.php not found. Please enter DB credentials manually."
  read -p "📛 Enter DB Name: " wp_db_name
  read -p "👤 Enter DB User: " wp_db_user
  read -p "🔑 Enter DB Password: " wp_db_pass
  read -p "🖥️ Enter DB Host (e.g., 127.0.0.1): " wp_db_host
  read -p "🔌 Enter DB Port (default 3306): " wp_db_port
  wp_prefix="wp_"
fi
[ -z "$wp_db_port" ] && wp_db_port=3306

# Step 5: Ask for wipe confirmation
read -p "🧼 Do you want to remove all current public_html files before restore? (y/n): " wipe_choice
if [[ "$wipe_choice" =~ ^[Yy]$ ]]; then
  echo "🧼 Wiping public_html..."
  mkdir -p "$priv_path"
  cp wp-config.php "$priv_path/wp-config-restore.bak" 2>/dev/null
  rm -rf ${dest_path:?}/*
fi

# Step 6: Download archive
read -p "🌍 Enter source domain (without https): " source_site
echo "📥 Downloading archive from https://${source_site}/${source_site}.tar.gz"
wget "https://${source_site}/${source_site}.tar.gz" --no-check-certificate || { echo "❌ Download failed."; exit 1; }

echo "📦 Extracting archive..."
tar -xzvf "${source_site}.tar.gz" || { echo "❌ Extraction failed."; exit 1; }

# Step 7: Modify source wp-config.php with destination creds
if [[ -f "wp-config.php" ]]; then
  echo "⚙️ Updating extracted wp-config.php with destination DB credentials..."
  sed -i "s/define('DB_NAME', *'.*');/define('DB_NAME', '$wp_db_name');/" wp-config.php
  sed -i "s/define('DB_USER', *'.*');/define('DB_USER', '$wp_db_user');/" wp-config.php
  sed -i "s/define('DB_PASSWORD', *'.*');/define('DB_PASSWORD', '$wp_db_pass');/" wp-config.php
  sed -i "s/define('DB_HOST', *'.*');/define('DB_HOST', '$wp_db_host:$wp_db_port');/" wp-config.php

  # Add WP_HOME and WP_SITEURL
  sed -i "/DB_COLLATE/a\define('WP_HOME', '$site_url');\ndefine('WP_SITEURL', '$site_url');" wp-config.php
fi

# Step 8: Extract and import database
if [[ -f ".backup_meta/db_backup.tar.gz" ]]; then
  echo "📂 Extracting database backup..."
  tar --no-overwrite-dir --no-same-owner --no-same-permissions -xzf .backup_meta/db_backup.tar.gz || { echo "❌ DB extraction failed."; exit 1; }

  if [[ -f "db_backup.sql" ]]; then
    echo "🛠️ Importing database..."
    mysql -h "$wp_db_host" -P "$wp_db_port" -u "$wp_db_user" -p"$wp_db_pass" "$wp_db_name" < db_backup.sql || { echo "❌ DB import failed."; exit 1; }
  else
    echo "❌ db_backup.sql not found after extraction."
    exit 1
  fi
else
  echo "❌ .backup_meta/db_backup.tar.gz not found. Exiting."
  exit 1
fi

# Step 9: Cleanup
read -p "🧹 Do you want to delete the DB backup and archive files? (y/n): " clean_choice
if [[ "$clean_choice" =~ ^[Yy]$ ]]; then
  echo "🧹 Cleaning up files..."
  rm -f "${source_site}.tar.gz" db_backup.sql
  rm -rf .backup_meta
fi

# Step 10: Search-replace URLs
read -p "🔁 Enter source site URL (without https): " source_url
source_url_http="http://${source_url}"
source_url_https="https://${source_url}"

echo "🔄 Replacing all references from $source_url_https and $source_url_http ➜ $site_url"
wp search-replace "$source_url_https" "$site_url" --all-tables
wp search-replace "$source_url_http" "$site_url" --all-tables

# Step 11: Update WP options just to be safe
wp option update siteurl "$site_url"
wp option update home "$site_url"

# Step 12: Flush cache
echo "🚿 Flushing WordPress cache..."
wp cache flush

echo "✅ WordPress site successfully restored from $source_url to $site_url"
