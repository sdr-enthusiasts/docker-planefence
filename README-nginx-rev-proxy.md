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

## Troubleshooting and known issues
- The `graphs` package for the `readsb-protobuf` container needs access to `../radar`, which is located below its own root. If you want to redirect (for example) http://graphs.mysite.com to the graphs package, you must add a second proxy_pass to `radar`. Here is an example from my own setup:
```
location /graphs/ {
	proxy_pass http://10.0.0.190:8080/graphs/;
}
location /radar/ {
	proxy_pass http://10.0.0.190:8080/radar/;
	# this is needed because of URL issues with the graphs package in readsb
}
```
## Example `/etc/nginx/sites-enabled/default` file
Note - this is the file from my own setup. I have a bunch of service spread around machines and ports, and each `location` entry redirects a request from http://mysite/xxxx to wherever the webserver for xxxx is located on my subnet. It won't work directly for anyone else, but feel free to use it as an example.
```
##
# You should look at the following URL's in order to grasp a solid understanding
# of Nginx configuration files in order to fully unleash the power of Nginx.
# https://www.nginx.com/resources/wiki/start/
# https://www.nginx.com/resources/wiki/start/topics/tutorials/config_pitfalls/
# https://wiki.debian.org/Nginx/DirectoryStructure
#
# In most cases, administrators will remove this file from sites-enabled/ and
# leave it as reference inside of sites-available where it will continue to be
# updated by the nginx packaging team.
#
# This file will automatically load configuration files provided by other
# applications, such as Drupal or Wordpress. These applications will be made
# available underneath a path with that package name, such as /drupal8.
#
# Please see /usr/share/doc/nginx-doc/examples/ for more detailed examples.
##

# Default server configuration
#
server {
	
	# This server instance defines access to "http" on port 80
	
	listen 80 default_server;
	listen [::]:80 default_server;

	root /var/www/html;

	# Add index.php to the list if you are using PHP
	index index.html index.htm index.nginx-debian.html;

	server_name _;

	location / {
		# First attempt to serve request as file, then
		# as directory, then fall back to displaying a 404.
		try_files $uri $uri/ =404;
	}

	include /etc/nginx/locations.conf;
}

server {
	# This server instance defines access to "https" (SSL enabled) on port 443
	
	root /var/www/html;

	# Add index.php to the list if you are using PHP
	index index.html index.htm index.nginx-debian.html;
        server_name ramonk.net; # managed by Certbot


	location / {
		# First attempt to serve request as file, then
		# as directory, then fall back to displaying a 404.
		try_files $uri $uri/ =404;
	}

        listen [::]:443 ssl ipv6only=on; # managed by Certbot
        listen 443 ssl; # managed by Certbot
        ssl_certificate /etc/letsencrypt/live/ramonk.net/fullchain.pem; # managed by Certbot
        ssl_certificate_key /etc/letsencrypt/live/ramonk.net/privkey.pem; # managed by Certbot
        include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
        ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot

	include /etc/nginx/locations.conf;
}

server {
	# This server instance redirects every non-encrypted HTTP request on port 80 to its encryped HTTPS equivalent
	# It probably makes the 1st server instance in this file unnecessary, but I haven't tried running without it
	# If you don't want automatic redirects of http://mysite.com/... to https://mysite.com/..., then comment out
	# this entire server section.
	
        if ($host = mysite.com) {
        	return 301 https://$host$request_uri;
        } # managed by Certbot

	listen 80 ;
	listen [::]:80 ;
        server_name mysite.com;
	return 404; # managed by Certbot

	include /etc/nginx/locations.conf;
}

```

## Example `locations.conf` file
Note - this is the file from my own setup. I have a bunch of service spread around machines and ports, and each `location` entry redirects a request from http://mysite/xxxx to wherever the webserver for xxxx is located on my subnet. It won't work directly for anyone else, but feel free to use it as an example.
```
location /readsb/ {
	proxy_pass http://10.0.0.190:8080/;                                                                                            
} 

location /piaware/ {
	proxy_pass http://10.0.0.190:8081/;                                                                                                
}

location /tar1090/ {
	proxy_pass http://10.0.0.190:8082/;                                                                                                
} 

location /adsb/ {
	proxy_pass http://10.0.0.190:8082/;                                                                                                
} 

location /planefence/ {
	proxy_pass http://10.0.0.190:8083/;                                                                                                
} 

location /plane-alert/ {
	proxy_pass http://10.0.0.190:8083/plane-alert/;                                                                                                
} 

location /heatmap/ {
	proxy_pass http://10.0.0.190:8084/;                                                                                                
} 

location /stats/ {
	proxy_pass http://10.0.0.190:8080/graphs/;                                                                                                
} 

location /graphs/ {
	proxy_pass http://10.0.0.190:8080/graphs/;                                                                                                
} 
location /radar/ {
	proxy_pass http://10.0.0.190:8080/radar/;                                                                                                
	# this is needed because of URL issues with the graphs package in readsb
} 

location /acars/ {
	proxy_pass http://10.0.0.166:80/;                                                                                                
} 

location /acarshub/ {
	proxy_pass http://10.0.0.166:80/;                                                                                                
} 

location /acarsdb/ {
	proxy_pass http://10.0.0.166:80/;                                                                                                
} 

location /noise/ {
	proxy_pass http://10.0.0.190:30088/;                                                                                                
} 

location /noisecapt/ {
	proxy_pass http://10.0.0.190:30088/;                                                                                                
} 

# Add index.php to the list if you are using PHP
index index.html index.htm index.nginx-debian.html;
```
