# Backup-Script
I want to share my incremental backup script that I use to backup everithing on my NAS. It works with a config file, where i can specify my data.

For my use case, I want to backup my Minecraft server and Nextcloud from my NAS per SSH on my PC. You can edit the [config file](./example.config) and [backup file](./backup.sh) as you want, to match your use case. 

Please note that you have to adjust your sudo settings on your NAS/Server, so you can run the specific sudo commands without a password. If you use SSH, you also want to create an SSH-Key to run the programm automaticaly.
