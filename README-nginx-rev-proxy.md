## How to install and set up a reverse web proxy to point http(s)://xxxxx.com/aaaa -> http://internalhost1:8080/xxxx, http(s)://xxxxx.com/bbbb -> http://internalhost2:8080/yyyy, etc.

Acknowledgements:
- @Mikenye for the encouragements to get started
- @wiedehopf for the large amount of handholding to get it actually done and implemented

1. Start with a Raspberry Pi connected to the network and a clean install of Raspberry Pi OS, SSH enabled
2. Log into your Pi to the command line with SSH
3. Do a `sudo apt-get update && sudo apt-get upgrade`
4. Do `sudo apt-get install nginx`
5. Edit the config file: `sudo nano -l /etc/nginx/nginx.conf` and make the following changes:
    - Once your proxy is configured / tested / stable, you may want to switch logging off (lines 41/42):
      `access_log /var/log/nginx/access.log;` -> `access_log off;`
      `#error_log /var/log/nginx/error.log;` -> `error_log off;`

    - Enable gzip compression (lines 50 and onward):
      `# gzip comp_level 6;` -> `gzip comp_level 1;`
      `# gzip_buffers 16 8k;` -> `gzip_buffers 16 8k;`
      `# gzip_types text/plain (... etc)` -> `gzip_types text/plain (... etc)`

    Then save and exit
6. Create and add SSL certificate, replace the email address and domain name with yours. BEFORE you run this, make sure your domain name (both port 80 and port 443) will arrive at your website. If not, it will fail.
```
sudo apt install python3-certbot-nginx
sudo certbot -n --nginx --agree-tos --redirect -m me@my-email.com -d mydomain.com
```
7. In `/etc/nginx`, create a file called `locations.conf`. In this file, you will add your proxy redirects. Use `localhost` or `127.0.0.1` for ports on the local machine
```
# redirect http(s)://mywebsite/website-1/ to http://10.0.0.10:8080/website1path/ :
location /website-1/ {
	proxy_pass http://10.0.0.10:8080/website1path/;
}

# redirect http(s)://mywebsite/website-2/ to http://10.0.0.11:8088/website2path/ :
location /website-2/ {
	proxy_pass http://10.0.0.11:8088/website2path/;
}

# ...et cetera. Make sure the location ends with a "/"

# Add index.php to the list if you are using PHP
index index.html index.htm index.nginx-debian.html;
```
8. Now edit /etc/nginx/sites-available/default. There will be 3 sections that start with `server {` (potentially more that are commented out).
    - The first section is for connections to the standard http port
    - The second section is for connections to the SSL (https) port
    - The third section rewrites any incoming "http" request into a "https" request
For each `server` section, just before the closing `}`, add the following line:
```
include /etc/nginx/locations.conf;
```
9. Now, you're done! Restart the nginx server with `sudo systemctl restart nginx` and start testing!
