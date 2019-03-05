FROM php:7.2-apache

MAINTAINER Hipay Fullservice <integration@hipay.com>

#======================
# Install packages needed by php's extensions
#======================
RUN apt-get update \
	&& apt-get -qy --no-install-recommends install \
		git \
	 	libmcrypt-dev \
		libjpeg62-turbo-dev \
		libpng-dev \
		libfreetype6-dev \
		libxslt1-dev \
		libicu-dev \
		mysql-client \
		default-libmysqlclient-dev \
    && docker-php-ext-configure gd --with-freetype-dir=/usr/include/ --with-jpeg-dir=/usr/include/ \
    && docker-php-ext-configure zip --enable-zip \
    && docker-php-ext-install gd bcmath intl mbstring soap xsl zip pdo_mysql \
	&& curl -sS https://getcomposer.org/installer | php -- --filename=composer -- --install-dir=/usr/local/bin \
	&& pecl install apcu \
    && echo "extension=apcu.so" > /usr/local/etc/php/conf.d/apcu.ini \
	&& rm -r /var/lib/apt/lists/*

#======================
# Install Gosu
#======================
RUN curl -o /usr/local/bin/gosu -fsSL "https://github.com/tianon/gosu/releases/download/1.7/gosu-$(dpkg --print-architecture)" \
	  && chmod +x /usr/local/bin/gosu

#======================
# Install Dockerize
#======================
RUN curl -o dockerize-linux-amd64-v0.2.0.tar.gz -sSOL https://github.com/jwilder/dockerize/releases/download/v0.2.0/dockerize-linux-amd64-v0.2.0.tar.gz
RUN tar -C /usr/local/bin -xzvf dockerize-linux-amd64-v0.2.0.tar.gz
RUN chmod u+x /usr/local/bin/dockerize

#=================================================
# ENV credentials for repo.magento.com and github
# Fake but valid credentials
# You can put yours tokens with environments variables
#=================================================
ENV GITHUB_API_TOKEN=bef0ec80d12009086371c166b904702cea3d35b1 \
    MAGE_ACCOUNT_PUBLIC_KEY=e3b8d4033c8f6440aec19950253a8cb3 \
	MAGE_ACCOUNT_PRIVATE_KEY=8a297c071a7c3085ea0630283c96f002

#===============
# PHP configuration
#===============
ENV PHP_TIMEZONE Europe/Paris

COPY conf/php.ini /usr/local/etc/php/conf.d/
COPY conf/apache2/site-available/000-default.conf /etc/apache2/site-available/
RUN ln -s /usr/local/bin/php /usr/bin/php

#====================================
# Apache configuration
# Active mod rewrite
#====================================
RUN a2enmod rewrite

#=============================
# Create Magento2 user and put it in web server's group
#============================
RUN adduser --disabled-password --gecos "" magento2 \
  && usermod -a -G www-data magento2 \
  && usermod -a -G magento2 www-data

WORKDIR /var/www/html/magento2
RUN chown -R magento2:www-data /var/www/html/magento2

ENV DOCKERIZE_TEMPLATES_PATH /home/magento2/dockerize

#==========================================
# Prepare Dockerize template for Auth, composer and MTF config
#==========================================
COPY conf/dockerize/auth.json.tmpl \
        conf/dockerize/composer.json.tmpl \
        conf/dockerize/mtf/phpunit.xml.tmpl \
        conf/dockerize/mtf/credentials.xml.tmpl \
        conf/dockerize/mtf/etc/config.xml.tmpl \
        /home/magento2/dockerize/

RUN chown -R magento2:magento2 $DOCKERIZE_TEMPLATES_PATH

# Create .composer directory in user home
RUN gosu magento2 mkdir /home/magento2/.composer/

# Magento Version
ENV MAGE_VERSION="2.3.0" MAGE_SAMPLE_DATA_VERSION="100.*"

# Dockerize auth and composer config
RUN gosu magento2 dockerize -template $DOCKERIZE_TEMPLATES_PATH/auth.json.tmpl:/home/magento2/.composer/auth.json \
												-template $DOCKERIZE_TEMPLATES_PATH/composer.json.tmpl:/var/www/html/magento2/composer.json

RUN gosu magento2 composer config -g github-oauth.github.com $GITHUB_API_TOKEN

# Get Magento CE release and sample data
RUN gosu magento2 composer install

#=========================
# Download MFT
#=========================
WORKDIR dev/tests/functional/
RUN  gosu magento2 composer install

#=============================
# Set file system ownership and permissions
#============================
WORKDIR /var/www/html/magento2
RUN chown -R magento2:www-data .
RUN find . -type d -exec chmod 770 {} \; \
	&& find . -type f -exec chmod 660 {} \; \
	&& chmod u+x bin/magento \
	&& chmod u+x /var/www/html/magento2/dev/tests/functional/vendor/phpunit/phpunit/phpunit

# magento and phpunit binaries to global path
ENV PATH=/var/www/html/magento2/dev/tests/functional/vendor/bin:/var/www/html/magento2/bin:$PATH
RUN echo "PATH=/var/www/html/magento2/dev/tests/functional/vendor/bin:/var/www/html/magento2/bin:$PATH" >> /home/magento2/.profile

#==========================
# Default Env variables used by magento installation
#==========================
ENV MYSQL_ROOT_PASSWORD magento2

#====================================================
# If you want to use sample data with installation or reinstallaiton,
# set command argument value else let it empty
# Eg. ENV MAGE_INSTALL_SAMPLE_DATA --use-sample-data
#=====================================================
ENV MAGE_REINSTALL=0 \
  MAGE_INSTALL_SAMPLE_DATA="--use-sample-data" \
  MAGE_ADMIN_FIRSTNAME="John" \
  MAGE_ADMIN_LASTNAME="Doe" \
  MAGE_ADMIN_EMAIL="john.doe@yopmail.com" \
  MAGE_ADMIN_USER="admin" \
  MAGE_ADMIN_PWD="admin123" \
  MAGE_BASE_URL="http://127.0.0.1" \
  MAGE_BASE_URL_SECURE="https://127.0.0.1" \
  MAGE_BACKEND_FRONTNAME="admin" \
  MAGE_DB_HOST="db" \
  MAGE_DB_PORT="3306" \
  MAGE_DB_NAME="magento2" \
  MAGE_DB_USER="magento2" \
  MAGE_DB_PASSWORD="magento2" \
  MAGE_DB_PREFIX="mage_" \
  MAGE_LANGUAGE="en_US" \
  MAGE_CURRENCY="USD" \
  MAGE_TIMEZONE="America/Chicago" \
  MAGE_USE_REWRITES=1 \
  MAGE_USE_SECURE=0 \
  MAGE_USE_SECURE_ADMIN=0 \
  MAGE_ADMIN_USE_SECURITY_KEY=0 \
  MAGE_SESSION_SAVE=files \
  MAGE_KEY="69c60a47f9dca004e47bf8783f4b9408"

#====================================================
# If you want to clean database with reinstallation,
# set command argument value else let it empty
# Eg. ENV MAGE_CLEANUP_DATABASE --cleanup-database
#=====================================================
ENV MAGE_CLEANUP_DATABASE="" \
  MAGE_DB_INIT_STATEMENTS="SET NAMES utf8;" \
  MAGE_SALES_ORDER_INCREMENT_PREFIX=0

#=================================================
# Env var used after installation
#=================================================
ENV MAGE_RUN_REINDEX=1 \
  MAGE_RUN_CACHE_CLEAN=0 \
  MAGE_RUN_CACHE_FLUSH=0 \
  MAGE_RUN_CACHE_DISABLE=1 \
  MAGE_RUN_STATIC_CONTENT_DEPLOY=1 \
  MAGE_RUN_SETUP_DI_COMPILE=0 \
  MAGE_RUN_DEPLOY_MODE=developer \
  MAGE_ENABLE_MODULE_MAGENTO_DEVELOPER=1

#============================================
# Env var used for custom package composer installation
# Env CUSTOM_MODULE is used for enable your module after required by composer
#============================================
ENV CUSTOM_REPOSITORIES="" \
  CUSTOM_PACKAGES="" \
  CUSTOM_MODULES=""

# Set minimum-stability to dev in composer.json
RUN gosu magento2 sed -i -e"s/\"minimum-stability\": \"alpha\"/\"minimum-stability\": \"dev\"/g" composer.json

# Override DocumentRoot
RUN sed -i -e 's/\/var\/www\/html/\/var\/www\/html\/magento2/' /etc/apache2/apache2.conf \
    && sed -i -e 's/\/var\/www\/html/\/var\/www\/html\/magento2/' /etc/apache2/sites-available/000-default.conf

ENV APACHE_RUN_USER=www-data \
     APACHE_RUN_GROUP=www-data \
     APACHE_PID_FILE=/var/run/apache2/apache2.pid \
     APACHE_RUN_DIR=/var/run/apache2 \
     APACHE_LOCK_DIR=/var/lock/apache2 \
     APACHE_LOG_DIR=/var/log/apache2

#==========================
# Selenium config (default host: selenium)
# Used by Magento testing framework
# You must to run your selenium server
# the best way is to use selenium image with docker-compose
#=========================
ENV SELENIUM_HOST=selenium \
  SELENIUM_PORT=4444

COPY bin/magento2-start /usr/local/bin/
ENTRYPOINT ["magento2-start"]
