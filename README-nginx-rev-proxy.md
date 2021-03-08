# How to install and set up a reverse web proxy for use with @Mikenye's ADSB container collection

In Mikenye's excellent [gitbook](https://mikenye.gitbook.io/ads-b/) on how to quickly set up a number of containers to receive and process ADSB aircraft telemetry,
you probably have created a bunch of containers that each provide a web service on their own port. This is a bit hard to manage, especially if you need to now open a large range of ports on your firewall to point at these services.

This README describes how you can set up a "reverse web proxy" that allows you to point to point https://mysite.com/aaaa to something like http://internalhost1:8080/xxxx, and repeat this for each of the containers or web services. Additionally, it (optionally) will redirect any non-encrypted "http://" request to a secure "https://" request, enabling you to access your web services via SSL.

There are NO changes needed to the containers. All you need is to take a quick inventory of the web services you have and the machines / ports they live on. You can do this by (for example) reading the `docker-compose.yml` files that show which services and ports are exposed.

## Acknowledgements
- @Mikenye for the encouragements to get started
- @wiedehopf for the large amount of handholding to get it actually done and implemented

## Installation of NGINX, a small web server with reverse-proxy capabilities
1. Start with a Raspberry Pi connected to the network and a clean install of Raspberry Pi OS, SSH enabled. This Raspberry Pi doesn't need to be the same as the one of your ADSB containers and services, but they should be on the same (or connected) subnets inside your firewall.
2. Log into your Pi to the command line with SSH
3. Do `sudo apt-get update && sudo apt-get upgrade`
4. Do `sudo apt-get install nginx`

## Configuration of NGINX as a reverse web proxy
1. Edit the config file: `sudo nano -l /etc/nginx/nginx.conf` and make the following changes:
    - Once your proxy is configured / tested / stable, you may want to switch logging off (near lines 41/42):
      `access_log /var/log/nginx/access.log;` -> `access_log off;`
      `#error_log /var/log/nginx/error.log;` -> `error_log off;`
    Then save and exit

2. Test. At this time, http://mysite.com (using the external or internal address) should render a template web page.

3. Make sure you can reach the website from the outside world. Test this with a machine outside your local network, for example your mobile phone using the data network (Wifi switched off!)

4. Create and add SSL certificate Replace the email address and domain name with yours. Note - this will fail if you can't reach the machine from the Internet. See step 3 above.
```
sudo apt install python3-certbot-nginx
sudo certbot -n --nginx --agree-tos --redirect -m me@my-email.com -d mydomain.com
```
This will create an SSL certificate for you that is valid for 90 days. For renewing and auto-renewing, see the Troubleshooting section below.

5. In `/etc/nginx`, create a file called `locations.conf`. In this file, you will add your proxy redirects. Use `localhost` or `127.0.0.1` for ports on the local machine. See an example of this file below - adapt it to your own needs

6. Now edit /etc/nginx/sites-available/default. There will be 3 sections that start with `server {` (potentially more that are commented out).
    - The first section is for connections to the standard http port
    - The second section is for connections to the SSL (https) port
    - The third section rewrites any incoming "http" request into a "https" request

For each `server` section, just before the closing `}`, add the following line:
```
include /etc/nginx/locations.conf;
```
7. Now, you're done! Restart the nginx server with `sudo systemctl restart nginx` and start testing!

## Troubleshooting and known issues
- My page renders badly / not / partially. This is often the case because of one of these issues:
	- The website uses absolute paths. So if the website is looking for `/index.html` instead of `index.html`, it will work at `http://mysite/index.html` but it won't work on `http://mysite/myapp/index.html`. This is a coding bug that can only be solved with some work-arounds. 
THis is the case with the `graphs` package for the `readsb-protobuf` container needs access to `../radar`, which is located below its own root. If you want to redirect (for example) http://graphs.mysite.com to the graphs package, you must add a second proxy_pass to `radar`. See example at the end of this guide.

- Your SSL certificate is only valid for 90 days and needs renewing thereafter.
Renewal is quick and easy -- `/usr/bin/certbot renew`
You can also set up easy automatic renewal by adding a crontab entry to take care of this:
```
$ crontab -e
0 12 * * * /usr/bin/certbot renew --quiet
```
This will check daily (at noon) if your certificate needs renewing, and once there's less than 1 month left, it will auto-renew it.
More information about using Let's Encrypt SSL certificates with nginx can be found [here](https://www.nginx.com/blog/using-free-ssltls-certificates-from-lets-encrypt-with-nginx).

- The target website uses websockets. In this case, make sure to implement something similar to `location /acars/` as shown below in the `locations.conf` example.


## Example `/etc/nginx/sites-enabled/default` file
Note - this is the file from my own setup. I have a bunch of services spread around machines and ports, and each `location` entry redirects a request from http://mysite.com/xxxx to wherever the webserver for xxxx is located on my subnet. It won't work directly for anyone else, but feel free to use it as an example.
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

## Example `/etc/nginx/locations.conf` file
Note - this is the file from my own setup. I have a bunch of service spread around machines and ports, and each `location` entry redirects a request from http://mysite/xxxx to wherever the webserver for xxxx is located on my subnet. It won't work directly for anyone else, but feel free to use it as an example.
```
location /readsb/ {
	proxy_pass http://10.0.0.191:8080/;                                                                                                
} 

location /piaware/ {
	proxy_pass http://10.0.0.191:8081/;                                                                                                
}

location /tar1090/ {
	proxy_pass http://10.0.0.191:8082/;                                                                                                
} 

location /adsb/ {
	proxy_pass http://10.0.0.191:8082/;                                                                                                
} 

location /planefence/ {
	proxy_pass http://10.0.0.191:8083/;                                                                                                
} 

location /plane-alert/ {
	proxy_pass http://10.0.0.191:8083/plane-alert/;                                                                                                
} 

location /heatmap/ {
	proxy_pass http://10.0.0.191:8084/;                                                                                                
} 

location /stats/ {
	proxy_pass http://10.0.0.191:8080/graphs/;                                                                                                
} 

location /graphs/ {
	proxy_pass http://10.0.0.191:8080/graphs/;                                                                                                
} 
location /radar/ {
	proxy_pass http://10.0.0.191:8080/radar/;                                                                                                
	# this is needed because of URL issues with the graphs package in readsb
} 


location /acars/ {
	proxy_pass http://10.0.0.188:80/;
	# These extra header settings are necessary to make acars work (to enable websockets):
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $http_connection;
        proxy_set_header Host $http_host;
} 

location /acarshub/ {
	proxy_pass http://10.0.0.188:80/;                                                     
	# These extra header settings are necessary to make acars work (to enable websockets):
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $http_connection;
        proxy_set_header Host $http_host;
} 

location /acarsdb/ {
	proxy_pass http://10.0.0.188:8080/;                                                                                                
} 

location /noise/ {
	proxy_pass http://10.0.0.191:30088/;                                                                                                
} 

location /noisecapt/ {
	proxy_pass http://10.0.0.191:30088/;                                                                                                
} 

# Add index.php to the list if you are using PHP
index index.html index.htm index.nginx-debian.html;
```
