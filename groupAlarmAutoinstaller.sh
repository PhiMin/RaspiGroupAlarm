#!/bin/bash

###################################################################
# Script Name : groupAlarmAutoinstaller.sh
# Version     : 1.1
# Description : Automatically configures Raspian for GroupAlarm
#
# Author      : Philip Minkenberg
# Email       : philip.minkenberg@feuerwehr-orsbeck.de
###################################################################

echo "00_Initialize ..."
echo "============================================================"

API_URL="https://app.groupalarm.com/api/v1/alarms?organization="
MONITOR_URL="https://app.groupalarm.com/de/monitor/"

AUTOSTART_FILE=/etc/xdg/lxsession/LXDE-pi/autostart
CRON_FILE=/var/spool/cron/crontabs/pi
SCREENSAVER_FILE=/home/pi/groupAlarmScreensaver.py
PY_VENV=/home/pi/python-venv

apt_install="apt-get install --assume-yes -qq -V"
pip=$PY_VENV/bin/pip3
python=$PY_VENV/bin/python3

echo "  * Check if script is executed as root ..."
if [ "$EUID" -ne 0 ]
	then echo "!!! Please run script as root !!!"
	exit
fi

echo "============================================================"

echo "01_Installing missing packages ..."
echo "============================================================"
if dpkg-query -W unclutter > /dev/null 2>/dev/null; then
	echo "  * unclutter already installed, ignoring ..."
else
	echo "  * installing unclutter ..."
	$apt_install unclutter
fi

if dpkg-query -W xscreensaver-data > /dev/null 2>/dev/null; then
	echo "  * xscreensaver already installed, ignoring ..."
else
	echo "  * installing xscreensaver ..."
	$apt_install xscreensaver
fi

if dpkg-query -W jq > /dev/null 2>/dev/null; then
	echo "  * jq already installed, ignoring ..."
else
	echo "  * installing jq ..."
	$apt_install jq
fi

if dpkg-query -W unattended-upgrades > /dev/null 2>/dev/null; then
	echo "  * unattended-upgrades already installed, ignoring ..."
else
	echo "  * installing unattended-upgrades ..."
	$apt_install unattended-upgrades
fi
echo "============================================================"

echo "02_Setting up Python virtual environment ..."
echo "============================================================"
if [ -d $PY_VENV ]; then
	echo "  * Python virtual environment already created, ignoring ..."
else
	echo "  * creating venv at $PY_VENV ..."
	python3 -m venv $PY_VENV
fi

if $python -c "import dateutil"; then
	echo "  * package python-dateutil already installed ..."
else
	echo "  * installing package python-dateutil ..."
	$pip install python-dateutil
fi

if $python -c "import RPi.GPIO"; then
	echo "  * package RPi.GPIO already installed ..."
else
	echo "  * installing package RPi.GPIO ..."
	$pip install rpi.gpio
fi

if $python -c "import requests"; then
	echo "  * package requests already installed ..."
else
	echo "  * installing package requests ..."
	$pip install requests
fi

if $python -c "from vcgencmd import Vcgencmd"; then
	echo "  * package Vcgencmd already installed ..."
else
	echo "  * installing package Vcgencmd ..."
	$pip install vcgencmd
fi

echo "============================================================"

echo "03_User Configuration ..."
echo "============================================================"
# Login Key Configuration
if grep -q $MONITOR_URL $AUTOSTART_FILE; then
	MONITOR_ID=`grep -Po "$MONITOR_URL\\d+" $AUTOSTART_FILE | sed 's/.*\///'`
	MONITOR_KEY=`grep -Po "view_token=[a-z0-9\-]*" $AUTOSTART_FILE | sed 's/view_token=//'`
	if grep -q "dark-theme" $AUTOSTART_FILE; then
		MONITOR_DARK_MODE=true
		MONITOR_DARK_OPTION="&theme=dark-theme"
	else
		MONITOR_DARK_MODE=false
		MONITOR_DARK_OPTION=""
	fi

	echo "  * Configuration found from previous configuration:"
	echo "  > Monitor-ID = $MONITOR_ID"
	echo "  > Monitor-Key = $MONITOR_KEY"
	echo "  > Dark Mode = $MONITOR_DARK_MODE"

	#Check if Login-Key from previous installation is valid
	FULL_URL="$MONITOR_URL$MONITOR_ID?view_token=$MONITOR_KEY"
	REDIRECT_URL=`curl -Ls -o /dev/null -w %{url_effective} $FULL_URL`
	if [ "$FULL_URL" == "$REDIRECT_URL" ]; then
		while true; do
			read -p "  * Do you wish to use this configuration? [yn]: " yn
			case $yn in
				[Yy]* ) LOOP=false;break;;
				[Nn]* ) LOOP=true;break;;
				* ) echo "  * Please answer [y]es or [n]o";;
			esac
		done
	else
		echo "  * ERROR: Configuration invalid."
		LOOP=true
	fi
fi

while $LOOP; do
	read -p "  * Enter Moitor-ID (integer):          " MONITOR_ID
	read -p "  * Enter Monitor-Key (36 characters):  " MONITOR_KEY
	read -p "  * Do you wish to use dark mode? [yn]: " yn
	case $yn in
		[Yy]* ) MONITOR_DARK_MODE=true;break;;
		[Nn]* ) MONITOR_DARK_MODE=false;break;;
		* ) echo "  * Please answer [y]es or [n]o";;
	esac
	
	FULL_URL="$MONITOR_URL$MONITOR_ID?view_token=$MONITOR_KEY"
	REDIRECT_URL=`curl -Ls -o /dev/null -w %{url_effective} $FULL_URL`

	if [ "$FULL_URL" == "$REDIRECT_URL" ]; then
		LOOP=false
	else
		echo "  * Configuration wrong. Please try again (To exit press Ctrl+C)..."
	fi
done

#API Key Configuration
if [ -f $SCREENSAVER_FILE ]; then

	APIKEY=`grep -P "api_key=" $SCREENSAVER_FILE | sed "s/api_key='\([^']*\)'/\1/"`
	echo "  * API-Key found from previous configuration: "
	echo "    $APIKEY"

	ORGID=`grep -P "org_id=" $SCREENSAVER_FILE | sed "s/org_id='\([^']*\)'/\1/"`
	echo "  * Organization ID found from previous configuration: $ORGID"

	#Check if API/Access Key from previous installation is valid
	while true; do
		read -p "  * Do you wish to use this key? [yn]: " yn
		case $yn in
			[Yy]* ) LOOP=false; break;;
			[Nn]* ) LOOP=true; break;;
			* ) echo "  * Please answer [y]es or [n]o";;
		esac
	done
else
	LOOP=true
fi

while $LOOP; do
	read -p "  * Enter API-Key   (64 characters):    " APIKEY
	read -p "  * Organization ID (integer):          " ORGID
	LOOP=false
done

echo "============================================================"

echo "04_Configure Screensaver..."
echo "============================================================"
echo "  * Create file $SCREENSAVER_FILE ..."
cat <<EOF > $SCREENSAVER_FILE
#!/usr/bin/python

import RPi.GPIO as GPIO
import time
import requests
from dateutil.parser import parse
from datetime import datetime, timedelta
from vcgencmd import Vcgencmd

#############
# API Setup #
#############

api_key='$APIKEY'
org_id='$ORGID'

api_url='$API_URL'+org_id

##############
# GPIO Setup #
##############

GPIO.setmode(GPIO.BCM)              #Set GPIO layout
pir = 23                            #Assign GPIO 23 to PIR
GPIO.setup(pir, GPIO.IN)            #Setup GPIO pin PIR as input
print ("Sensor initializing . . .")
time.sleep(2)                       #Give sensor time to startup
print ("Sensor activated")
print ("Press Ctrl+c to end program")

#################
# Display Setup #
#################

isDisplayOn = True
vcgm = Vcgencmd()

################
#     Loop     #
################

try:
	while True:
		#get timestamp of last alarm via API
		response = requests.get(api_url, headers={
			"Content-Type": "application/json",
			"API-TOKEN": api_key
		})

		#check if there was an alarm within the last hour
		if(len(response.json()['alarms']) > 0):
			lastAlarm = parse(response.json()['alarms'][0]['startDate']).replace(tzinfo=None)
			isAlarm = datetime.utcnow() < lastAlarm+timedelta(hours=1)
			print("Alarm: " + str(isAlarm))
		else:
			isAlarm = False

		#check if motion is detected
		isMotion = bool(GPIO.input(pir))
		print("Motion: " + str(isMotion))
		
		if((isAlarm or isMotion) and not isDisplayOn):
			print("Turn Display on!")
			isDisplayOn = True
			vcgm.display_power_on(display=7) 
		
		if(not(isAlarm or isMotion) and isDisplayOn):
			print("Turn Display off!")
			isDisplayOn = False
			vcgm.display_power_off(display=7)
			
		#wait 5 seconds
		time.sleep(5)

except KeyboardInterrupt:				#Ctrl+c
	pass								#Do nothing, continue to finally

finally:
	GPIO.cleanup()						#reset all GPIO
	vcgm.display_power_on(display=7)	#Turn on display again 
	print ("Program ended")
EOF

echo "  * Set permissions for file $SCREENSAVER_FILE ..."
chown pi:pi $SCREENSAVER_FILE
chmod a+x $SCREENSAVER_FILE
echo "============================================================"


echo "05_Configure Chromium Kiosk Mode..."
echo "============================================================"
echo "  * Create Backup of $AUTOSTART_FILE ..."
cp -n $AUTOSTART_FILE $AUTOSTART_FILE.bak
echo "  * Create new $AUTOSTART_FILE ..."
cat <<EOF > $AUTOSTART_FILE
@lxpanel --profile LXDE-pi
@pcmanfm --desktop --profile LXDE-pi
#@xscreensaver -no-splash

@xset s off
@xset -dpms
@xset s noblank

#Kiosk Mode
@chromium-browser --noerrdialogs --kiosk --incognito $MONITOR_URL$MONITOR_ID?view_token=$MONITOR_KEY$MONITOR_DARK_OPTION

#Disable Cursor
@unclutter -display :0 -noevents - grab

#Screensaver
@$python $SCREENSAVER_FILE
EOF
echo "============================================================"

echo "06_Configure Auto Reboot (Daily at 03:00) ..."
echo "============================================================"
echo "  * Check if daily reboot is already configured ..."
if [ -f $CRON_FILE ] && `grep -q "sudo reboot" $CRON_FILE`; then
	echo "  * Entry already exists. Skipping ..."
else
	echo "  * Add line to crontab ..."
	echo "0 3 * * * sudo reboot" >> $CRON_FILE
	chown pi:crontab $CRON_FILE
	chmod 600 $CRON_FILE
fi

echo "============================================================"

echo "07_Reboot ..."
echo "============================================================"

while true; do
	read -p "  * Do you wish to reboot? [yn]: " yn
	case $yn in
		[Yy]* ) REBOOT=true; break;;
		[Nn]* ) REBOOT=false; break;;
		* ) echo "  * Please answer [y]es or [n]o";;
	esac
done

if $LOOP; then
	echo "  * Raspberry will now reboot ..."
	sleep 5
	reboot
fi
