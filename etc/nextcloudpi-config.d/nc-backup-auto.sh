#!/bin/bash
# Nextcloud backups
#
# Copyleft 2017 by Ignacio Nunez Hernanz <nacho _a_t_ ownyourbits _d_o_t_ com>
# GPL licensed (see end of file) * Use at your own risk!
#
# Usage:
# 
#   ./installer.sh nc-backup-auto.sh <IP> (<img>)
#
# See installer.sh instructions for details
#
# More at https://ownyourbits.com/2017/02/13/nextcloud-ready-raspberry-pi-image/
#


ACTIVE_=no
DESTDIR_=/media/USBdrive
INCLUDEDATA_=no
BACKUPDAYS_=7
BACKUPLIMIT_=4
DESCRIPTION="Periodic backups"

BASEDIR=/var/www

install() 
{
  cat > /etc/systemd/system/nc-backup.service <<EOF
[Unit]
Description=Backup Nextcloud instance

[Service]
Type=simple
ExecStart=/usr/local/bin/ncp-backup

[Install]
WantedBy=default.target
EOF
}

configure()
{
  [[ $ACTIVE_ != "yes" ]] && { 
    systemctl stop    nc-backup.timer
    systemctl disable nc-backup.timer
    echo "automatic backups disabled"
    return 0
  }

  cat > /usr/local/bin/ncp-backup <<EOF
#!/bin/bash
DESTFILE=$DESTDIR_/nextcloud-bkp_\`date +"%Y%m%d"\`.tar 
DBBACKUP=nextcloud-sqlbkp_\`date +"%Y%m%d"\`.bak

DATADIR=\$( cd $BASEDIR/nextcloud; sudo -u www-data php occ config:system:get datadirectory ) || {
  echo -e "Error reading data directory. Is NextCloud running and configured?";
  return 1;
}

cd $BASEDIR/nextcloud
sudo -u www-data php occ maintenance:mode --on

# delete older backups
[[ $BACKUPLIMIT_ != 0 ]] && {
  NUMBKPS=\$( ls "$DESTDIR_"/nextcloud-bkp_* 2>/dev/null | wc -l )
  [[ \$NUMBKPS -ge $BACKUPLIMIT_ ]] && \
    ls -t $DESTDIR_/nextcloud-bkp_* | tail -\$(( NUMBKPS - $BACKUPLIMIT_ + 1 )) | while read f; do
      echo -e "clean up old backup \$f"
      rm \$f
    done
}

# database
cd $BASEDIR
echo -e "backup database..."
mysqldump -u root --single-transaction nextcloud > \$DBBACKUP

# files
[[ "$INCLUDEDATA_" == "yes" ]] && echo -e "backup datadir... "
echo -e "backup files..."
mkdir -p $DESTDIR_
tar -cf "\$DESTFILE" "\$DBBACKUP" nextcloud/ \
  --exclude "nextcloud/data/*/files/*" \
  --exclude "nextcloud/data/.opcache" \
  --exclude "nextcloud/data/{access,error,nextcloud}.log" \
  --exclude "nextcloud/data/access.log" \
    || {
          echo -e "error generating backup"
          sudo -u www-data php "$BASEDIR"/nextcloud/occ maintenance:mode --off
          return 1
        }
  rm "\$DBBACKUP"

  [[ "$INCLUDEDATA_" == "yes" ]] && {
    echo -e "backup data files..."
    tar -rf "\$DESTFILE" -C "\$DATADIR"/.. "\$( basename "\$DATADIR" )" \
    || {
          echo -e "error generating backup"
          sudo -u www-data php "$BASEDIR"/nextcloud/occ maintenance:mode --off
          return 1
        }
  } 
  echo -e "backup \$DESTFILE generated"

cd $BASEDIR/nextcloud
sudo -u www-data php occ maintenance:mode --off
EOF
  chmod +x /usr/local/bin/ncp-backup

  cat > /etc/systemd/system/nc-backup.timer <<EOF
[Unit]
Description=Timer to backup NC periodically

[Timer]
OnBootSec=${BACKUPDAYS_}days
OnUnitActiveSec=${BACKUPDAYS_}days
Unit=nc-backup.service

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable nc-backup.timer
  systemctl start  nc-backup.timer
  echo "automatic backups enabled"
}

# License
#
# This script is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This script is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this script; if not, write to the
# Free Software Foundation, Inc., 59 Temple Place, Suite 330,
# Boston, MA  02111-1307  USA

