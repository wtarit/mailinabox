#!/bin/bash
# Nextcloud
##########################

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

# ### Installing Nextcloud

echo "Installing Nextcloud (contacts/calendar)..."

# Nextcloud core and app (plugin) versions to install.
# With each version we store a hash to ensure we install what we expect.

# Nextcloud core
# --------------
# * See https://nextcloud.com/changelog for the latest version.
# * Check https://docs.nextcloud.com/server/latest/admin_manual/installation/system_requirements.html
#   for whether it supports the version of PHP available on this machine.
# * Nextcloud only supports upgrades from consecutive major versions. Existing
#   installations must follow the upstream migration requirement in README.md.
# * The hash is the SHA1 hash of the ZIP package, which you can find by just running this script and
#   copying it from the error message when it doesn't match what is below.
nextcloud_ver=34.0.1
nextcloud_hash=576623416739b81e59d8c4df71a7b087fa6d985c

# Nextcloud apps
# --------------
# * Find the most recent release that is compatible with the Nextcloud version above by:
#   https://apps.nextcloud.com/apps/contacts
#   https://apps.nextcloud.com/apps/calendar
#   https://apps.nextcloud.com/apps/user_external
#
# * For these three packages, contacts, calendar and user_external, the hash is the SHA1 hash of
# the release package, which you can find by just running this script and copying it from
# the error message when it doesn't match what is below:

# Always ensure the versions are supported, see https://apps.nextcloud.com/apps/contacts
contacts_ver=8.7.4
contacts_hash=76ba6ee92e7be7fd1d7cb82e539dbc9309a3e41c

# Always ensure the versions are supported, see https://apps.nextcloud.com/apps/calendar
calendar_ver=6.5.1
calendar_hash=a4155ba3b7caac5e5add69d1673fbd981c19cc13

# Always ensure the versions are supported, see https://apps.nextcloud.com/apps/user_external
user_external_ver=4.0.0
user_external_hash=214497dd8691f279ba3740797c565310f0793054

# Developer advice (test plan)
# ----------------------------
# When upgrading above versions, how to test?
#
# 1. Enter your server instance (or on the Vagrant image)
# 1. Git clone <your fork>
# 2. Git checkout <your fork>
# 3. Run `sudo ./setup/nextcloud.sh`
# 4. Ensure the installation completes. If any hashes mismatch, correct them.
# 5. Enter nextcloud web, run following tests:
# 5.1 You still can create, edit and delete contacts
# 5.2 You still can create, edit and delete calendar events
# 5.3 You still can create, edit and delete users
# 5.4 Go to Administration > Logs and ensure no new errors are shown

# Clear prior packages and install dependencies from apt.
apt-get purge -qq -y owncloud* # we used to use the package manager

apt_install curl php"${PHP_VER}" php"${PHP_VER}"-fpm \
	php"${PHP_VER}"-cli php"${PHP_VER}"-sqlite3 php"${PHP_VER}"-gd php"${PHP_VER}"-curl \
	php"${PHP_VER}"-dev php"${PHP_VER}"-gd php"${PHP_VER}"-xml php"${PHP_VER}"-mbstring php"${PHP_VER}"-zip php"${PHP_VER}"-apcu \
	php"${PHP_VER}"-intl php"${PHP_VER}"-imagick php"${PHP_VER}"-gmp php"${PHP_VER}"-bcmath

# Enable APC before Nextcloud tools are run.
tools/editconf.py /etc/php/"$PHP_VER"/mods-available/apcu.ini -c ';' \
	apc.enabled=1 \
	apc.enable_cli=1

InstallNextcloud() {

	version=$1
	hash=$2
	version_contacts=$3
	hash_contacts=$4
	version_calendar=$5
	hash_calendar=$6
	version_user_external=${7:-}
	hash_user_external=${8:-}

	echo
	echo "Upgrading to Nextcloud version $version"
	echo

	# Download and verify
	wget_verify "https://download.nextcloud.com/server/releases/nextcloud-$version.zip" "$hash" /tmp/nextcloud.zip

	# user_external has no release compatible with Nextcloud 30. Disable it while
	# PHP-FPM is stopped for that maintenance hop, then install its Nextcloud
	# 31-compatible release on the following hop.
	if [ -z "$version_user_external" ] && [ -e "$STORAGE_ROOT/owncloud/owncloud.db" ]; then
		sudo -u www-data php"$PHP_VER" /usr/local/lib/owncloud/occ config:system:delete user_backends
		sudo -u www-data php"$PHP_VER" /usr/local/lib/owncloud/occ app:disable user_external
	fi

	# Remove the current owncloud/Nextcloud
	rm -rf /usr/local/lib/owncloud

	# Extract ownCloud/Nextcloud
	unzip -q /tmp/nextcloud.zip -d /usr/local/lib
	mv /usr/local/lib/nextcloud /usr/local/lib/owncloud
	rm -f /tmp/nextcloud.zip

	# The apps we actually want are not in Nextcloud core. Download their
	# packaged releases from GitHub.
	mkdir -p /usr/local/lib/owncloud/apps

	wget_verify "https://github.com/nextcloud-releases/contacts/releases/download/v$version_contacts/contacts-v$version_contacts.tar.gz" "$hash_contacts" /tmp/contacts.tgz
	tar xf /tmp/contacts.tgz -C /usr/local/lib/owncloud/apps/
	rm /tmp/contacts.tgz

	wget_verify "https://github.com/nextcloud-releases/calendar/releases/download/v$version_calendar/calendar-v$version_calendar.tar.gz" "$hash_calendar" /tmp/calendar.tgz
	tar xf /tmp/calendar.tgz -C /usr/local/lib/owncloud/apps/
	rm /tmp/calendar.tgz

	# Starting with Nextcloud 15, the app user_external is no longer included in Nextcloud core,
	# we will install from their github repository.
	if [ -n "$version_user_external" ]; then
		wget_verify "https://github.com/nextcloud-releases/user_external/releases/download/v$version_user_external/user_external-v$version_user_external.tar.gz" "$hash_user_external" /tmp/user_external.tgz
		tar -xf /tmp/user_external.tgz -C /usr/local/lib/owncloud/apps/
		rm /tmp/user_external.tgz
	fi

	# Fix weird permissions.
	chmod 750 /usr/local/lib/owncloud/{apps,config}

	# Create a symlink to the config.php in STORAGE_ROOT (for upgrades we're restoring the symlink we previously
	# put in, and in new installs we're creating a symlink and will create the actual config later).
	ln -sf "$STORAGE_ROOT/owncloud/config.php" /usr/local/lib/owncloud/config/config.php

	# Make sure permissions are correct or the upgrade step won't run.
	# $STORAGE_ROOT/owncloud may not yet exist, so use -f to suppress
	# that error.
	chown -f -R www-data:www-data "$STORAGE_ROOT/owncloud" /usr/local/lib/owncloud || /bin/true

	# If this isn't a new installation, immediately run the upgrade script.
	# Then check for success (0=ok and 3=no upgrade needed, both are success).
	if [ -e "$STORAGE_ROOT/owncloud/owncloud.db" ]; then
		# ownCloud 8.1.1 broke upgrades. It may fail on the first attempt, but
		# that can be OK.
		sudo -u www-data php"$PHP_VER" /usr/local/lib/owncloud/occ upgrade
		E=$?
		if [ $E -ne 0 ] && [ $E -ne 3 ]; then
			echo "Trying ownCloud upgrade again to work around ownCloud upgrade bug..."
			sudo -u www-data php"$PHP_VER" /usr/local/lib/owncloud/occ upgrade
			E=$?
			if [ $E -ne 0 ] && [ $E -ne 3 ]; then exit 1; fi
			sudo -u www-data php"$PHP_VER" /usr/local/lib/owncloud/occ maintenance:mode --off
			echo "...which seemed to work."
		fi

		# Add missing indices. NextCloud didn't include this in the normal upgrade because it might take some time.
		sudo -u www-data php"$PHP_VER" /usr/local/lib/owncloud/occ db:add-missing-indices
		sudo -u www-data php"$PHP_VER" /usr/local/lib/owncloud/occ db:add-missing-primary-keys

		# Run conversion to BigInt identifiers, this process may take some time on large tables.
		sudo -u www-data php"$PHP_VER" /usr/local/lib/owncloud/occ db:convert-filecache-bigint --no-interaction

		# Complete queued background migrations before moving to the next major
		# version, as required by Nextcloud's upgrade procedure.
		for _ in 1 2 3; do
			sudo -u www-data php"$PHP_VER" -f /usr/local/lib/owncloud/cron.php
		done
	fi
}

# Current Nextcloud Version, #1623
# Checking /usr/local/lib/owncloud/version.php shows version of the Nextcloud application, not the DB
# $STORAGE_ROOT/owncloud is kept together even during a backup. It is better to rely on config.php than
# version.php since the restore procedure can leave the system in a state where you have a newer Nextcloud
# application version than the database.

# If config.php exists, get version number, otherwise CURRENT_NEXTCLOUD_VER is empty.
if [ -f "$STORAGE_ROOT/owncloud/config.php" ]; then
	CURRENT_NEXTCLOUD_VER=$(php"$PHP_VER" -r "include(\"$STORAGE_ROOT/owncloud/config.php\"); echo(\$CONFIG['version']);")
else
	CURRENT_NEXTCLOUD_VER=""
fi

# If the Nextcloud directory is missing (never been installed before, or the nextcloud version to be installed is different
# from the version currently installed, do the install/upgrade
if [ ! -d /usr/local/lib/owncloud/ ] || [[ ! ${CURRENT_NEXTCLOUD_VER} =~ ^$nextcloud_ver ]]; then

	# Stop php-fpm if running. If they are not running (which happens on a previously failed install), dont bail.
	service php"$PHP_VER"-fpm stop &> /dev/null || /bin/true

	# Backup the existing ownCloud/Nextcloud.
	# Create a backup directory to store the current installation and database to
	BACKUP_DIRECTORY=$STORAGE_ROOT/owncloud-backup/$(date +"%Y-%m-%d-%T")
	mkdir -p "$BACKUP_DIRECTORY"
	if [ -d /usr/local/lib/owncloud/ ]; then
		echo "Upgrading Nextcloud --- backing up existing installation, configuration, and database to directory to $BACKUP_DIRECTORY..."
		cp -r /usr/local/lib/owncloud "$BACKUP_DIRECTORY/owncloud-install"
	fi
	if [ -e "$STORAGE_ROOT/owncloud/owncloud.db" ]; then
		cp "$STORAGE_ROOT/owncloud/owncloud.db" "$BACKUP_DIRECTORY"
	fi
	if [ -e "$STORAGE_ROOT/owncloud/config.php" ]; then
		cp "$STORAGE_ROOT/owncloud/config.php" "$BACKUP_DIRECTORY"
	fi

	# If ownCloud or Nextcloud was previously installed....
	if [ -n "${CURRENT_NEXTCLOUD_VER}" ]; then
		if [ -e "$STORAGE_ROOT/owncloud/config.php" ]; then
			# Remove the read-onlyness of the config while running migrations.
			sed -i -e '/config_is_read_only/d' "$STORAGE_ROOT/owncloud/config.php"
		fi

		# Nextcloud supports upgrades from only one major version at a time.
		# Use the final maintenance release of each major and app releases that
		# the Nextcloud app store marks compatible with that server version.
		if [[ ${CURRENT_NEXTCLOUD_VER} =~ ^26 ]]; then
			InstallNextcloud 27.1.11 9f30c01a021c2e5a9e7baff119955afb3c552ebc 5.5.4 c4e3f2183a0088b829f8aa1b3af1f87c9a4c46a2 4.7.20 12d876904e227156e39ca4335b18481b42a6d00f 3.4.0 7f9d8f4dd6adb85a0e3d7622d85eeb7bfe53f3b4
			CURRENT_NEXTCLOUD_VER="27.1.11"
		fi
		if [[ ${CURRENT_NEXTCLOUD_VER} =~ ^27 ]]; then
			InstallNextcloud 28.0.14 8a9edcfd26d318eb7d1cfa44d69796f2d1098a80 5.5.4 c4e3f2183a0088b829f8aa1b3af1f87c9a4c46a2 4.7.20 12d876904e227156e39ca4335b18481b42a6d00f 3.4.0 7f9d8f4dd6adb85a0e3d7622d85eeb7bfe53f3b4
			CURRENT_NEXTCLOUD_VER="28.0.14"
		fi
		if [[ ${CURRENT_NEXTCLOUD_VER} =~ ^28 ]]; then
			InstallNextcloud 29.0.16 ceb3014aaddc70d3074d2c69bc6afc76eb1aeff0 6.0.7 babb779107b029c30ad20b81da33b4f95e1136ff 4.7.20 12d876904e227156e39ca4335b18481b42a6d00f 3.4.0 7f9d8f4dd6adb85a0e3d7622d85eeb7bfe53f3b4
			CURRENT_NEXTCLOUD_VER="29.0.16"
		fi
		if [[ ${CURRENT_NEXTCLOUD_VER} =~ ^29 ]]; then
			InstallNextcloud 30.0.17 0494197f1984ce8a2f83084c0759a24d48474017 7.3.18 762542bb8c6a6bbde7e785f23d2dea88254cfabe 5.5.22 d21e273bda1355ab3b20340ed465f19670a98afc
			CURRENT_NEXTCLOUD_VER="30.0.17"
		fi
		if [[ ${CURRENT_NEXTCLOUD_VER} =~ ^30 ]]; then
			InstallNextcloud 31.0.14 a891fede2cd4cb3347a406da3fb4f99cd62c89ce 7.3.18 762542bb8c6a6bbde7e785f23d2dea88254cfabe 5.5.22 d21e273bda1355ab3b20340ed465f19670a98afc 4.0.0 214497dd8691f279ba3740797c565310f0793054
			CURRENT_NEXTCLOUD_VER="31.0.14"
		fi
		if [[ ${CURRENT_NEXTCLOUD_VER} =~ ^31 ]]; then
			InstallNextcloud 32.0.12 c8a4b04009bacb8597bdf93676edce4abfa8b019 8.3.16 86fc315337a9d328ef443a12416223b14e4c9878 6.5.1 a4155ba3b7caac5e5add69d1673fbd981c19cc13 4.0.0 214497dd8691f279ba3740797c565310f0793054
			CURRENT_NEXTCLOUD_VER="32.0.12"
		fi
		if [[ ${CURRENT_NEXTCLOUD_VER} =~ ^32 ]]; then
			InstallNextcloud 33.0.6 0fd7f62553087918bebde68d65e751842adf2168 8.7.4 76ba6ee92e7be7fd1d7cb82e539dbc9309a3e41c 6.5.1 a4155ba3b7caac5e5add69d1673fbd981c19cc13 4.0.0 214497dd8691f279ba3740797c565310f0793054
			CURRENT_NEXTCLOUD_VER="33.0.6"
		fi
	fi

	InstallNextcloud $nextcloud_ver $nextcloud_hash $contacts_ver $contacts_hash $calendar_ver $calendar_hash $user_external_ver $user_external_hash

	# Some migrations are intentionally excluded from the normal upgrade because
	# they can take a long time. Complete them before bringing Nextcloud back.
	if [ -e "$STORAGE_ROOT/owncloud/owncloud.db" ]; then
		sudo -u www-data php"$PHP_VER" /usr/local/lib/owncloud/occ maintenance:repair --include-expensive
	fi
fi

# ### Configuring Nextcloud

# Setup Nextcloud if the Nextcloud database does not yet exist. Running setup when
# the database does exist wipes the database and user data.
if [ ! -f "$STORAGE_ROOT/owncloud/owncloud.db" ]; then
	# Create user data directory
	mkdir -p "$STORAGE_ROOT/owncloud"

	# Create an initial configuration file.
	instanceid=oc$(echo "$PRIMARY_HOSTNAME" | sha1sum | fold -w 10 | head -n 1)
	cat > "$STORAGE_ROOT/owncloud/config.php" <<EOF;
<?php
\$CONFIG = array (
  'datadirectory' => '$STORAGE_ROOT/owncloud',

  'instanceid' => '$instanceid',

  'forcessl' => true, # if unset/false, Nextcloud sends a HSTS=0 header, which conflicts with nginx config

  'overwritewebroot' => '/cloud',
  'overwrite.cli.url' => '/cloud',
  'user_backends' => array(
    array(
      'class' => '\OCA\UserExternal\IMAP',
      'arguments' => array(
        '127.0.0.1', 143, null, null, false, false
       ),
    ),
  ),
  'memcache.local' => '\OC\Memcache\APCu',
);
?>
EOF

	# Create an auto-configuration file to fill in database settings
	# when the install script is run. Make an administrator account
	# here or else the install can't finish.
	adminpassword=$(dd if=/dev/urandom bs=1 count=40 2>/dev/null | sha1sum | fold -w 30 | head -n 1)
	cat > /usr/local/lib/owncloud/config/autoconfig.php <<EOF;
<?php
\$AUTOCONFIG = array (
  # storage/database
  'directory' => '$STORAGE_ROOT/owncloud',
  'dbtype' => 'sqlite3',

  # create an administrator account with a random password so that
  # the user does not have to enter anything on first load of Nextcloud
  'adminlogin'    => 'root',
  'adminpass'     => '$adminpassword',
);
?>
EOF

	# Set permissions
	chown -R www-data:www-data "$STORAGE_ROOT/owncloud" /usr/local/lib/owncloud

	# Execute Nextcloud's setup step, which creates the Nextcloud sqlite database.
	# It also wipes it if it exists. And it updates config.php with database
	# settings and deletes the autoconfig.php file.
	(cd /usr/local/lib/owncloud || exit; sudo -u www-data php"$PHP_VER" /usr/local/lib/owncloud/index.php;)
fi

# Update config.php.
# * trusted_domains is reset to localhost by autoconfig starting with ownCloud 8.1.1,
#   so set it here. It also can change if the box's PRIMARY_HOSTNAME changes, so
#   this will make sure it has the right value.
# * Some settings weren't included in previous versions of Mail-in-a-Box.
# * We need to set the timezone to the system timezone to allow fail2ban to ban
#   users within the proper timeframe
# * We need to set the logdateformat to something that will work correctly with fail2ban
# * mail_domain' needs to be set every time we run the setup. Making sure we are setting
#   the correct domain name if the domain is being change from the previous setup.
# Use PHP to read the settings file, modify it, and write out the new settings array.
TIMEZONE=$(cat /etc/timezone)
CONFIG_TEMP=$(/bin/mktemp)
php"$PHP_VER" <<EOF > "$CONFIG_TEMP" && mv "$CONFIG_TEMP" "$STORAGE_ROOT/owncloud/config.php";
<?php
include("$STORAGE_ROOT/owncloud/config.php");

\$CONFIG['config_is_read_only'] = false;
\$CONFIG['appstoreenabled'] = false; # Keep installed apps under provisioning control.

\$CONFIG['trusted_domains'] = array('$PRIMARY_HOSTNAME');

\$CONFIG['memcache.local'] = '\OC\Memcache\APCu';
\$CONFIG['overwrite.cli.url'] = 'https://${PRIMARY_HOSTNAME}/cloud';

\$CONFIG['logtimezone'] = '$TIMEZONE';
\$CONFIG['logdateformat'] = 'Y-m-d H:i:s';

\$CONFIG['user_backends'] = array(
  array(
    'class' => '\OCA\UserExternal\IMAP',
    'arguments' => array(
      '127.0.0.1', 143, null, null, false, false
    ),
  ),
);

\$CONFIG['mail_domain'] = '$PRIMARY_HOSTNAME';
\$CONFIG['mail_from_address'] = 'administrator'; # just the local part, matches the required administrator alias on mail_domain/$PRIMARY_HOSTNAME
\$CONFIG['mail_smtpmode'] = 'sendmail';
\$CONFIG['mail_smtpauth'] = true; # if smtpmode is smtp
\$CONFIG['mail_smtphost'] = '127.0.0.1'; # if smtpmode is smtp
\$CONFIG['mail_smtpport'] = '587'; # if smtpmode is smtp
\$CONFIG['mail_smtpsecure'] = ''; # if smtpmode is smtp, must be empty string
\$CONFIG['mail_smtpname'] = ''; # if smtpmode is smtp, set this to a mail user
\$CONFIG['mail_smtppassword'] = ''; # if smtpmode is smtp, set this to the user's password

echo "<?php\n\\\$CONFIG = ";
var_export(\$CONFIG);
echo ";";
?>
EOF
chown www-data:www-data "$STORAGE_ROOT/owncloud/config.php"

# Enable/disable apps. Note that this must be done after the Nextcloud setup.
# The firstrunwizard gave Josh all sorts of problems, so disabling that.
# user_external is what allows Nextcloud to use IMAP for login. The contacts
# and calendar apps are the extensions we really care about here.
hide_output sudo -u www-data php"$PHP_VER" /usr/local/lib/owncloud/console.php app:disable firstrunwizard
hide_output sudo -u www-data php"$PHP_VER" /usr/local/lib/owncloud/console.php app:enable user_external
hide_output sudo -u www-data php"$PHP_VER" /usr/local/lib/owncloud/console.php app:enable contacts
hide_output sudo -u www-data php"$PHP_VER" /usr/local/lib/owncloud/console.php app:enable calendar

# When upgrading, run the upgrade script again now that apps are enabled. It seems like
# the first upgrade at the top won't work because apps may be disabled during upgrade?
# Check for success (0=ok, 3=no upgrade needed).
sudo -u www-data php"$PHP_VER" /usr/local/lib/owncloud/occ upgrade
E=$?
if [ $E -ne 0 ] && [ $E -ne 3 ]; then exit 1; fi

# Disable default apps that we don't support
sudo -u www-data \
	php"$PHP_VER" /usr/local/lib/owncloud/occ app:disable photos dashboard activity \
	| (grep -v "No such app enabled" || /bin/true)

# Set PHP FPM values to support large file uploads
# (semicolon is the comment character in this file, hashes produce deprecation warnings)
tools/editconf.py /etc/php/"$PHP_VER"/fpm/php.ini -c ';' \
	upload_max_filesize=16G \
	post_max_size=16G \
	output_buffering=16384 \
	memory_limit=512M \
	max_execution_time=600 \
	short_open_tag=On

# Set Nextcloud recommended opcache settings
tools/editconf.py /etc/php/"$PHP_VER"/cli/conf.d/10-opcache.ini -c ';' \
	opcache.enable=1 \
	opcache.enable_cli=1 \
	opcache.interned_strings_buffer=8 \
	opcache.max_accelerated_files=10000 \
	opcache.memory_consumption=128 \
	opcache.save_comments=1 \
	opcache.revalidate_freq=1

# Migrate users_external data from <0.6.0 to version 3.0.0
# (see https://github.com/nextcloud/user_external).
# This version was probably in use in Mail-in-a-Box v0.41 (February 26, 2019) and earlier.
# We moved to v0.6.3 in 193763f8. Ignore errors - maybe there are duplicated users with the
# correct backend already.
sqlite3 "$STORAGE_ROOT/owncloud/owncloud.db" "UPDATE oc_users_external SET backend='127.0.0.1';" || /bin/true

# Set up a general cron job for Nextcloud.
# Also add another job for Calendar updates, per advice in the Nextcloud docs
# https://docs.nextcloud.com/server/24/admin_manual/groupware/calendar.html#background-jobs
cat > /etc/cron.d/mailinabox-nextcloud << EOF;
#!/bin/bash
# Mail-in-a-Box
*/5 * * * *	www-data	php$PHP_VER -f /usr/local/lib/owncloud/cron.php
*/5 * * * *	www-data	php$PHP_VER -f /usr/local/lib/owncloud/occ dav:send-event-reminders
EOF
chmod +x /etc/cron.d/mailinabox-nextcloud

# We also need to change the sending mode from background-job to occ.
# Or else the reminders will just be sent as soon as possible when the background jobs run.
hide_output sudo -u www-data php"$PHP_VER" -f /usr/local/lib/owncloud/occ config:app:set dav sendEventRemindersMode --value occ

# Now set the config to read-only.
# Do this only at the very bottom when no further occ commands are needed.
sed -i'' "s/'config_is_read_only'\s*=>\s*false/'config_is_read_only' => true/" "$STORAGE_ROOT/owncloud/config.php"

# Rotate the nextcloud.log file
cat > /etc/logrotate.d/nextcloud <<EOF
# Nextcloud logs
$STORAGE_ROOT/owncloud/nextcloud.log {
		size 10M
		create 640 www-data www-data
		rotate 30
		copytruncate
		missingok
		compress
}
EOF

# There's nothing much of interest that a user could do as an admin for Nextcloud,
# and there's a lot they could mess up, so we don't make any users admins of Nextcloud.
# But if we wanted to, we would do this:
# ```
# for user in $(management/cli.py user admins); do
#	 sqlite3 $STORAGE_ROOT/owncloud/owncloud.db "INSERT OR IGNORE INTO oc_group_user VALUES ('admin', '$user')"
# done
# ```

# Enable PHP modules and restart PHP.
restart_service php"$PHP_VER"-fpm
