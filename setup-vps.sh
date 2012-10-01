#!/bin/bash
# penggunaan
#	bash setup-vps.sh <nama user> <domain> <ip>

adduser $1
mkdir /home/$1/nginx
mkdir /home/$1/public_html
mkdir /home/$1/public_html/localhost
mkdir /home/$1/public_html/$2
touch /home/$1/public_html/localhost/index.html
# update vps
DEBIAN_FRONTEND=noninteractive apt-get update
DEBIAN_FRONTEND=noninteractive apt-get -q -y install build-essential nano libpcre3 libpcre3-dev zlib1g-dev zlib1g libssl-dev libxslt-dev libxml2-dev sudo screen netselect-apt unzip

# hapus file nameserver
mv /etc/resolv.conf /etc/resolv.conf.original

# ubah menjadi dns google
cat > /etc/resolv.conf <<END
nameserver 8.8.8.8
nameserver 8.8.4.4
END

# restart jaringan
service networking restart

# Tambahkan repositori nginx
echo "deb http://nginx.org/packages/debian/ squeeze nginx" >> /etc/apt/sources.list
echo "deb-src http://nginx.org/packages/debian/ squeeze nginx" >> /etc/apt/sources.list

wget http://nginx.org/packages/keys/nginx_signing.key
cat nginx_signing.key | apt-key add -

wget https://raw.github.com/gist/3712985/8bb4a1a46b9394a222e8c871a46f92ec91ab7fb0/setup-debian.sh

bash setup-debian.sh system
bash setup-debian.sh exim4
bash setup-debian.sh nginx
bash setup-debian.sh mysql
bash setup-debian.sh php
DEBIAN_FRONTEND=noninteractive apt-get -q -y install php5-mcrypt php-pear

# buat folder yang diperlukan
mkdir -p /var/lib/nginx/body 
mkdir -p /var/lib/nginx/proxy 
mkdir -p /var/lib/nginx/fastcgi 
mkdir -p /var/lib/nginx/uwsgi 
mkdir -p /var/lib/nginx/scgi


# backup konfig nginx
cp -rf /etc/nginx /etc/nginx.original
cp /etc/init.d/nginx /root/nginx.orginal

# hapus nginx
DEBIAN_FRONTEND=noninteractive apt-get -q -y remove --purge nginx

#based on my guide I add make software to my /srv directory
mkdir /srv/software
cd /srv/software
mkdir nginx-modules
cd nginx-modules


wget http://labs.frickle.com/files/ngx_cache_purge-1.6.tar.gz
tar -xvf ngx_cache_purge-1.6.tar.gz

wget http://openssl.org/source/openssl-1.0.1c.tar.gz 
tar -xvf openssl-1.0.1c.tar.gz

wget wget http://nginx.org/download/nginx-1.3.6.tar.gz 
tar xvfz nginx-1.3.6.tar.gz

cd nginx-1.3.6

wget http://nginx.org/patches/spdy/patch.spdy.txt && patch -p0 < patch.spdy.txt 

./configure --sbin-path=/usr/local/sbin/nginx --prefix=/etc/nginx --conf-path=/etc/nginx/nginx.conf --error-log-path=/var/log/nginx/error.log --http-client-body-temp-path=/var/lib/nginx/body --http-fastcgi-temp-path=/var/lib/nginx/fastcgi --http-log-path=/var/log/nginx/access.log --http-proxy-temp-path=/var/lib/nginx/proxy --http-scgi-temp-path=/var/lib/nginx/scgi --http-uwsgi-temp-path=/var/lib/nginx/uwsgi --lock-path=/var/lock/nginx.lock --pid-path=/var/run/nginx.pid --with-debug --with-http_addition_module --with-http_dav_module --with-http_gzip_static_module --with-http_realip_module --with-http_stub_status_module --with-http_ssl_module --with-http_sub_module --with-http_xslt_module --with-ipv6 --with-sha1=/usr/include/openssl --with-md5=/usr/include/openssl --with-mail --with-mail_ssl_module --add-module=/srv/software/nginx-modules/ngx_cache_purge-1.6 --with-openssl='/srv/software/nginx-modules/openssl-1.0.1c'
make
make install


#restore backup
cp -rf /etc/nginx /etc/nginx.new_install_backup
rm /etc/nginx -r
cp -rf /etc/nginx.original /etc/nginx

# Setting auto run nginx daemon
wget https://bitbucket.org/fway/vps/raw/951767d729b1/nginx.init.d -O /etc/init.d/nginx

# Setting nginx config
cat > /etc/nginx/nginx.conf <<END
user www-data;
worker_processes  1;

error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;


events {
    worker_connections  1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile        on;
    #tcp_nopush     on;

    keepalive_timeout  65;

	gzip  on;
	server_tokens off;
	include /etc/nginx/conf.d/*.conf;
	include /home/$1/nginx/*.conf;
}
END


# install php myadmin
wget http://sourceforge.net/projects/phpmyadmin/files/phpMyAdmin/3.5.2.2/phpMyAdmin-3.5.2.2-all-languages.zip/download -O /home/$1/public_html/localhost/pma.zip
cd /home/$1/public_html/localhost/
unzip pma.zip
mv /home/$1/public_html/localhost/phpMyAdmin-* /home/$1/public_html/localhost/pmabrox

# install wordpress
cd /home/$1/public_html/$2/
wget http://wordpress.org/latest.zip -O wp.zip
unzip wp.zip
mv wordpress wp

cat > /home/$1/public_html/$2/index.php <<END
<?php
define('WP_USE_THEMES', true);
require('./wp/wp-blog-header.php');
?>
END


# konfigurasi nginx localhost
cat > /home/$1/nginx/localhost.conf <<END
server {
	listen 80;
	server_name $3;
    root /home/$1/public_html/localhost;
   	include /etc/nginx/fastcgi_php;
	
	location / {
		index index.php index.html index.htm;
		if (!-e \$request_filename) {
			rewrite ^(.*)\$  /index.php last;
		}
	}
}

END

# konfigurasi nginx domain
cat > /home/$1/nginx/$2.conf <<END
server {
	listen 80;
	listen [::]:80  default ipv6only=on;
	server_name $2 *.$2;
    root /home/$1/public_html/$2;
   	include /etc/nginx/fastcgi_php;
	
	location / {
		index index.php index.html index.htm;
		if (!-e \$request_filename) {
			rewrite ^(.*)\$  /index.php last;
		}
	}
}

END

# auto start nginx
chmod +x /etc/init.d/nginx
/usr/sbin/update-rc.d -f nginx defaults

service nginx reload

# ubah user data
chown www-data:www-data /home/$1/public_html -R
chown $1:$1 /home/$1/nginx -R

# add user to sudoers

echo "$1 ALL=(ALL) ALL" >> /etc/sudoers