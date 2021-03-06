#!/bin/bash

# Disable Strict Host checking for non interactive git clones

mkdir -p -m 0700 /root/.ssh
echo -e "Host *\n\tStrictHostKeyChecking no\n" >> /root/.ssh/config

if [[ "$GIT_USE_SSH" == "1" ]] ; then
  echo -e "Host *\n\tUser ${GIT_USERNAME}\n\n" >> /root/.ssh/config
fi

if [ ! -z "$SSH_KEY" ]; then
 echo $SSH_KEY > /root/.ssh/id_rsa.base64
 base64 -d /root/.ssh/id_rsa.base64 > /root/.ssh/id_rsa
 chmod 600 /root/.ssh/id_rsa
fi

# Set custom webroot
if [ ! -z "$WEBROOT" ]; then
 webroot=$WEBROOT
 sed -i "s#root /var/www/html;#root ${webroot};#g" /etc/nginx/sites-available/default.conf
else
 webroot=/var/www/html
fi

# Setup git variables
if [ ! -z "$GIT_EMAIL" ]; then
 git config --global user.email "$GIT_EMAIL"
fi
if [ ! -z "$GIT_NAME" ]; then
 git config --global user.name "$GIT_NAME"
 git config --global push.default simple
fi

if [[ "$SKIP_LARAVEL"  == "No" ]]; then
  if [ ! -f "/var/www/html/.env" ]; then
    echo "Trying laravel install."
  	rm -rf /var/www/html/laravelinstall &&\
  	mkdir -p /var/www/html/laravelinstall &&\
	EXPECTED_SIGNATURE=$(wget -q -O - https://composer.github.io/installer.sig) &&\
	php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" &&\
	ACTUAL_SIGNATURE=$(php -r "echo hash_file('SHA384', 'composer-setup.php');") &&\
	if [ "$EXPECTED_SIGNATURE" != "$ACTUAL_SIGNATURE" ] 
	  then
	    >&2 echo 'ERROR: Invalid installer signature'
        rm composer-setup.php
	  exit 1
	fi
	php composer-setup.php --quiet &&\
	RESULT=$? &&\
	echo $RESULT &&\
	rm composer-setup.php &&\
  	php composer.phar create-project laravel/laravel /var/www/html/laravelinstall "$LARAVEL_VERSION" --prefer-dist &&\
  	cp -r  /var/www/html/laravelinstall/. /var/www/html/ &&\
  	rm -rf /var/www/html/laravelinstall
  	if [[ "$SKIP_ENV" == "1" ]] ; then
        echo "Skipping env file creation."
  	else

  	    sed -i -e 's/DB_DATABASE=.*/DB_DATABASE='"$MYSQL_DATABASE"'/g' /var/www/html/.env
  	    sed -i -e 's/DB_USERNAME=.*/DB_USERNAME=root /g' /var/www/html/.env
  	    sed -i -e 's/DB_PASSWORD=.*/DB_PASSWORD='"$MYSQL_ROOT_PASSWORD"' /g' /var/www/html/.env
  	    sed -i -e 's/APP_ENV=.*/APP_ENV=production /g' /var/www/html/.env
  	    sed -i -e 's/APP_URL=.*/APP_URL='"$PRODUCTION_DOMAIN"' /g' /var/www/html/.env
  	    sed -i -e 's/DB_HOST=.*/DB_HOST='"$MYSQL_HOST"' /g' /var/www/html/.env
  	fi
  	rm -rf .gitignore
  	#rm -rf /var/www/html/routes/web.php
  else
  	echo "Skipping laravel install. Env file alredy exists. Stashing potenttialy unwanted changes..."
  	git stash
  	if [ ! -z "$ENV_FILE_CONTENT" ]; then
        echo -e  "$ENV_FILE_CONTENT" > /var/www/html/.env
  	else

  	    sed -i -e 's/DB_DATABASE=.*/DB_DATABASE='"$MYSQL_DATABASE"'/g' /var/www/html/.env
  	    sed -i -e 's/DB_USERNAME=.*/DB_USERNAME=root /g' /var/www/html/.env
  	    sed -i -e 's/DB_PASSWORD=.*/DB_PASSWORD='"$MYSQL_ROOT_PASSWORD"' /g' /var/www/html/.env
  	    sed -i -e 's/APP_ENV=.*/APP_ENV=production /g' /var/www/html/.env
  	    sed -i -e 's/APP_URL=.*/APP_URL='"$PRODUCTION_DOMAIN"' /g' /var/www/html/.env
  	    sed -i -e 's/DB_HOST=.*/DB_HOST='"$MYSQL_HOST"' /g' /var/www/html/.env
  	fi
  fi
fi



# Dont pull code down if the .git folder exists
if [ ! -d "/var/www/html/.git" ]; then
 # Pull down code from git for our site!

 # Remove the test index file
 if [[ "$RESET_ALL" == "1" ]] ; then
   echo "Eliminating the html folder"
   rm -Rf /var/www/html/[a-zA-Z_-]*
   rm -Rf /var/www/html/.[a-zA-Z_-]*
   pwd
   ls -la
 fi

 if [ ! -z "$GIT_REPO" ]; then

   GIT_COMMAND='git clone '
   if [ ! -z "$GIT_BRANCH" ]; then
     GIT_COMMAND=${GIT_COMMAND}" -b ${GIT_BRANCH}"
   fi

   if [ -z "$GIT_USERNAME" ] && [ -z "$GIT_PERSONAL_TOKEN" ]; then
     GIT_COMMAND=${GIT_COMMAND}" ${GIT_REPO}"
   else
    if [[ "$GIT_USE_SSH" == "1" ]]; then
      GIT_COMMAND=${GIT_COMMAND}" ${GIT_REPO}"
    else
      GIT_COMMAND=${GIT_COMMAND}" https://${GIT_USERNAME}:${GIT_PERSONAL_TOKEN}@${GIT_REPO}"
    fi
   fi
   ${GIT_COMMAND} /var/www/html || exit 1
   chown -Rf nginx.nginx /var/www/html
 fi
else
 GIT_COMMAND='git pull '
 if [ ! -z "$GIT_BRANCH" ]; then
   GIT_COMMAND=${GIT_COMMAND}" -b ${GIT_BRANCH}"
 fi

 if [ -z "$GIT_USERNAME" ] && [ -z "$GIT_PERSONAL_TOKEN" ]; then
   GIT_COMMAND=${GIT_COMMAND}" ${GIT_REPO}"
 else
  if [[ "$GIT_USE_SSH" == "1" ]]; then
    GIT_COMMAND=${GIT_COMMAND}" ${GIT_REPO}"
  else
	echo "pulling from  ${GIT_REPO}"
    GIT_COMMAND=${GIT_COMMAND}" https://${GIT_USERNAME}:${GIT_PERSONAL_TOKEN}@${GIT_REPO}"
  fi
 fi
 ${GIT_COMMAND}
 #|| exit 1
fi
if [  ! -z "$SKIP_LARAVEL" ]; then
  # Try auto install for composer
  if [ -f "$WEBROOT/../composer.lock" ]; then
    php composer.phar install --no-dev
    echo "Runnig composer update"
    php composer.phar update --no-dev
    if [ -f "$WEBROOT/../vendor/tymon/jwt-auth/src/Providers/JWTAuthServiceProvider.php" ]; then
      echo "Runnig artisan"
      php artisan vendor:publish --provider="Tymon\JWTAuth\Providers\JWTAuthServiceProvider"
      php artisan jwt:generate
  	echo "Artisan ran"
    fi
  fi
fi

# Enable custom nginx config files if they exist
if [ -f /var/www/html/conf/nginx/nginx-site.conf ]; then
  cp /var/www/html/conf/nginx/nginx-site.conf /etc/nginx/sites-available/default.conf
fi

if [ -f /var/www/html/conf/nginx/nginx-site-ssl.conf ]; then
  cp /var/www/html/conf/nginx/nginx-site-ssl.conf /etc/nginx/sites-available/default-ssl.conf
fi

# Display PHP error's or not
if [[ "$ERRORS" != "1" ]] ; then
 echo php_flag[display_errors] = off >> /usr/local/etc/php-fpm.conf
else
 echo php_flag[display_errors] = on >> /usr/local/etc/php-fpm.conf
fi

# Display Version Details or not
if [[ "$HIDE_NGINX_HEADERS" == "0" ]] ; then
 sed -i "s/server_tokens off;/server_tokens on;/g" /etc/nginx/nginx.conf
else
 sed -i "s/expose_php = On/expose_php = Off/g" /usr/local/etc/php-fpm.conf
fi

# Pass real-ip to logs when behind ELB, etc
if [[ "$REAL_IP_HEADER" == "1" ]] ; then
 sed -i "s/#real_ip_header X-Forwarded-For;/real_ip_header X-Forwarded-For;/" /etc/nginx/sites-available/default.conf
 sed -i "s/#set_real_ip_from/set_real_ip_from/" /etc/nginx/sites-available/default.conf
 if [ ! -z "$REAL_IP_FROM" ]; then
  sed -i "s#172.16.0.0/12#$REAL_IP_FROM#" /etc/nginx/sites-available/default.conf
 fi
fi
# Do the same for SSL sites
if [ -f /etc/nginx/sites-available/default-ssl.conf ]; then
 if [[ "$REAL_IP_HEADER" == "1" ]] ; then
  sed -i "s/#real_ip_header X-Forwarded-For;/real_ip_header X-Forwarded-For;/" /etc/nginx/sites-available/default-ssl.conf
  sed -i "s/#set_real_ip_from/set_real_ip_from/" /etc/nginx/sites-available/default-ssl.conf
  if [ ! -z "$REAL_IP_FROM" ]; then
   sed -i "s#172.16.0.0/12#$REAL_IP_FROM#" /etc/nginx/sites-available/default-ssl.conf
  fi
 fi
fi

# Increase the memory_limit
if [ ! -z "$PHP_MEM_LIMIT" ]; then
 sed -i "s/memory_limit = 512M/memory_limit = ${PHP_MEM_LIMIT}M/g" /usr/local/etc/php/conf.d/docker-vars.ini
fi

# Increase the post_max_size
if [ ! -z "$PHP_POST_MAX_SIZE" ]; then
 sed -i "s/post_max_size = 100M/post_max_size = ${PHP_POST_MAX_SIZE}M/g" /usr/local/etc/php/conf.d/docker-vars.ini
fi

# Increase the upload_max_filesize
if [ ! -z "$PHP_UPLOAD_MAX_FILESIZE" ]; then
 sed -i "s/upload_max_filesize = 100M/upload_max_filesize= ${PHP_UPLOAD_MAX_FILESIZE}M/g" /usr/local/etc/php/conf.d/docker-vars.ini
fi

if [ ! -z "$PUID" ]; then
  if [ -z "$PGID" ]; then
    PGID=${PUID}
  fi
  deluser nginx
  addgroup -g ${PGID} nginx
  adduser -D -S -h /var/cache/nginx -s /sbin/nologin -G nginx -u ${PUID} nginx
else
  # Always chown webroot for better mounting
  chown -Rf nginx.nginx /var/www/html
fi
if [  ! -z "$SKIP_LARAVEL" ]; then
    chmod ugo+rwx /var/www/html/storage/framework/
    chmod ugo+rwx /var/www/html/storage/logs/
    chmod ugo+rwx /var/www/html/storage/laravel-backups/
    chmod ugo+rwx /var/www/html/bootstrap/cache/
    chmod ugo+rwx /var/www/html/images/
    chmod ugo+rwx /var/www/html/uploads/
    chmod ugo+rwx /var/www/html/storage/app/
fi

# Run custom scripts
if [[ "$RUN_SCRIPTS" == "1" ]] ; then
  if [ -d "/var/www/html/scripts/" ]; then
    # make scripts executable incase they aren't
    chmod -Rf 750 /var/www/html/scripts/*
    # run scripts in number order
    for i in `ls /var/www/html/scripts/`; do /var/www/html/scripts/$i ; done
  else
    echo "Can't find script directory"
  fi
fi

# Start supervisord and services
exec /usr/bin/supervisord -n -c /etc/supervisord.conf
