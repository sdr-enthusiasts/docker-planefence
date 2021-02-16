#!/usr/bin/with-contenv bash
#shellcheck shell=bash

APPNAME="config_tweeting"

echo "[$APPNAME][$(date)] Running config_tweeting"

# -----------------------------------------------------------------------------------
# Copyright 2020, 2021 Ramon F. Kolb - licensed under the terms and conditions
# of GPLv3. The terms and conditions of this license are included with the Github
# distribution of this package, and are also available here:
# https://github.com/kx1t/planefence4docker/
#
# The package contains parts of, and modifications or derivatives to the following:
# Dump1090.Socket30003 by Ted Sluis: https://github.com/tedsluis/dump1090.socket30003
# These packages may incorporate other software and license terms.
#
# -----------------------------------------------------------------------------------

echo Configure Tweeting for PlaneFence
echo
echo Prerequisite -- you should already have signed up for an Developer Account
echo with Twitter, and created an application with Read/Write/Direct message
echo permissions.
echo
echo "If you haven't done this, or don't know how to do this, please browse to this"
echo link: https://elfsight.com/blog/2020/03/how-to-get-twitter-api-key/
echo
if [[ -f ~/.twurlrc ]]
then
  echo -----------------------------------------------------------------------------------
  echo !!! WARNING !!!
  echo It appears that Tweeting already has been configured for Twitter handle $(sed -n '/profiles:/{n;p;}' /root/.twurlrc | tr -d '[:blank:][=:=]').
  echo If you do not want to overwrite this configuration, press CTRL-C now.
  echo -----------------------------------------------------------------------------------
  echo
  echo If you overwrite it and you want to return to the previous configuration, you can do so by entering:
  echo \"docker exec -t planefence mv -f ~/.twurlrc.backup ~/.twurlrc\"
  echo
fi
echo In order to configure Twitter correctly, you will need 2 keys from your
echo Twitter Dev Account, as they pertain to the application you created:
echo - Consumer API Key
echo - Consumer API Key Secret
echo
echo Paste them here:
read -p "Enter Consumer API Key: " -r KEY
read -p "Enter Consumer API Secret: " -r SECRET
[[ "$(wc -c <<< $KEY)" != "26" ]] && echo "Warning - your Consumer API Key should probably be 25 characters. Please check!"
[[ "$(wc -c <<< $SECRET)" != "51" ]] && echo "Warning - your Consumer API Key Secret should probably be 50 characters. Please check!"
echo
echo MAKE SURE TO SAVE A COPY OF THESE KEYS SOMEWHERE. YOU MAY NEED THEM AGAIN IN THE FUTURE!
echo
echo If incidentally overwrite your old config and you want to return to the previous configuration, you can do so by entering:
echo \"docker exec -t planefence mv -f ~/.twurlrc.backup ~/.twurlrc\"
echo
echo Press ENTER to continue the configuration or CTRL-C to abort. Any existing configuration will be backed up.
read
[[ -f ~/.twurlrc ]] && mv -f ~/.twurlrc ~/.twurlrc.backup
echo
twurl authorize --consumer-key $KEY --consumer-secret $SECRET
unset KEY
unset SECRET
cp -f ~/.twurlrc /run/planefence
echo
echo Tweeting is now configured. You can switch it ON or OFF by changing the PF_TWEET parameter in \".env\" to \"ON\" or \"OFF\".
echo We strongly recommend you to BACK UP your twitter configuration file. You can do so by typing:
echo \"docker cp planefence:/root/.twurlrc .\"
echo If you recreate the container and lose the file somehow, you can always restore it by typing:
echo \"docker cp .twurlrc planefence:/root/.twurlrc\"
echo
read -p "Do you want tweeting to be enabled for this session [Y/n]?" -r question
if [[ "$(tr '[:upper:]' '[:lower:]' <<< ${QUESTION:0:1})" == "y" ]] || [[ "$QUESTION" == "" ]]
then
  sed -i 's|\(^\s*PLANETWEET=\).*|\1'"$(sed -n '/profiles:/{n;p;}' /root/.twurlrc | tr -d '[:blank:][=:=]')"'|' /usr/share/planefence/planefence.conf
  echo "Tweeting is enabled for this session only. If you want to make it permanent after reboot or rebuild of the container,"
  echo "set \"PF_TWEET\" in \".env\" to \"ON\"."
fi
