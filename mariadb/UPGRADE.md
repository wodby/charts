# Upgrade to 0.4.0

The default image changes from MariaDB 11.2 to `wodby/mariadb:11.4-r0` because the 11.2 image line is no longer maintained.

Before upgrading an installation with existing data, back up the database and plan the MariaDB 11.2-to-11.4 upgrade. This chart does not migrate database files automatically. Set `image.tag` explicitly when coordinating the database upgrade with the chart upgrade.
