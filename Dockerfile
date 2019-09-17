FROM php:7.2-apache-buster

MAINTAINER PI-Ecommerce <integration@hipay.com>

#=================================================
# ENV credentials for repo.magento.com
# Fake but valid credentials
# You can put yours tokens with environments variables
#=================================================
ENV MAGE_ACCOUNT_PUBLIC_KEY=e3b8d4033c8f6440aec19950253a8cb3 \
	MAGE_ACCOUNT_PRIVATE_KEY=8a297c071a7c3085ea0630283c96f002 \
    DOCKERIZE_TEMPLATES_PATH=/home/magento2/dockerize \
    MAGE_VERSION="2.3.2" \
    MAGE_SAMPLE_DATA_VERSION="100.*" \
    CUSTOM_REPOSITORIES="" \
    CUSTOM_PACKAGES="" \
    CUSTOM_MODULES="" \
    PHP_TIMEZONE="Europe/Paris" \
    APACHE_RUN_USER="www-data" \
    APACHE_RUN_GROUP="www-data" \
    APACHE_PID_FILE="/var/run/apache2/apache2.pid" \
    APACHE_RUN_DIR="/var/run/apache2" \
    APACHE_LOCK_DIR="/var/lock/apache2" \
    APACHE_LOG_DIR="/var/log/apache2" \
    MAGE_INSTALL_SAMPLE_DATA="--use-sample-data" \
    MAGE_ADMIN_FIRSTNAME="John" \
    MAGE_ADMIN_LASTNAME="Doe" \
    MAGE_ADMIN_EMAIL="john.doe@yopmail.com" \
    MAGE_ADMIN_USER="admin" \
    MAGE_ADMIN_PWD="admin123" \
    MAGE_BASE_URL="http://127.0.0.1" \
    MAGE_BASE_URL_SECURE="https://127.0.0.1" \
    MAGE_BACKEND_FRONTNAME="admin" \
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
    MAGE_KEY="69c60a47f9dca004e47bf8783f4b9408" \
    MYSQL_ROOT_PASSWORD="magento2" \
    MAGE_RUN_REINDEX=0 \
    MAGE_RUN_CACHE_CLEAN=0 \
    MAGE_RUN_CACHE_FLUSH=0 \
    MAGE_RUN_CACHE_DISABLE=0 \
    MAGE_RUN_STATIC_CONTENT_DEPLOY=0 \
    MAGE_RUN_SETUP_DI_COMPILE=0 \
    MAGE_RUN_DEPLOY_MODE=developer

#======================
# Install packages needed by php's extensions
#======================
RUN apt-get update \
	&& apt-get -qy --no-install-recommends install \
		git \
		unzip \
	 	libmcrypt-dev \
		libjpeg62-turbo-dev \
		libpng-dev \
		libfreetype6-dev \
		libxslt1-dev \
		libicu-dev \
		msmtp \
		vim \
		wget \
		ssh \
		libsodium-dev \
		default-mysql-client \
        default-libmysqlclient-dev  \
    && docker-php-ext-configure gd --with-freetype-dir=/usr/include/ --with-jpeg-dir=/usr/include/ \
    && docker-php-ext-configure zip --enable-zip \
    && docker-php-ext-install gd bcmath intl mbstring soap xsl zip pdo_mysql \
	&& curl -sS https://getcomposer.org/installer | php -- --filename=composer -- --install-dir=/usr/local/bin \
	&& pecl install apcu \
    && echo "extension=apcu.so" > /usr/local/etc/php/conf.d/apcu.ini \
	&& rm -r /var/lib/apt/lists/* \
	&& curl -o /usr/local/bin/gosu -fsSL "https://github.com/tianon/gosu/releases/download/1.7/gosu-$(dpkg --print-architecture)" \
    && chmod +x /usr/local/bin/gosu \
    && a2enmod rewrite \
    && echo "sendmail_path = /usr/sbin/ssmtp -t" > /usr/local/etc/php/conf.d/sendmail.ini \
    && wget https://phar.phpunit.de/phpunit-6.2.phar \
    && chmod +x phpunit-6.2.phar \
    && mv -f phpunit-6.2.phar /usr/local/bin/phpunit \
    && phpunit --version \
    && echo '' && pecl install xdebug \
    && echo "zend_extension=$(find /usr/local/lib/php/extensions/ -name xdebug.so)" > /usr/local/etc/php/conf.d/xdebug.ini \
    && ln -s /usr/local/bin/php /usr/bin/ \
    && curl -o dockerize-linux-amd64-v0.2.0.tar.gz -sSOL https://github.com/jwilder/dockerize/releases/download/v0.2.0/dockerize-linux-amd64-v0.2.0.tar.gz \
    && tar -C /usr/local/bin -xzvf dockerize-linux-amd64-v0.2.0.tar.gz \
    && chmod u+x /usr/local/bin/dockerize \
    && curl -O  https://files.magerun.net/n98-magerun2.phar  \
    && chmod +x ./n98-magerun2.phar \
    && cp ./n98-magerun2.phar /usr/local/bin/ \
    && rm ./n98-magerun2.phar

#======================
# COPY FILE AND CONFIGURATION
#======================
COPY conf/php.ini /usr/local/etc/php/conf.d/
COPY conf/apache2/site-available/000-default.conf /etc/apache2/sites-available/
COPY bin/magento2-start /usr/local/bin/

WORKDIR /var/www/html/magento2

#=============================
# Create Magento2 user and put it in web server's group
#============================
RUN adduser --disabled-password --gecos "" magento2 \
    && usermod -a -G www-data magento2 \
    && usermod -a -G magento2 www-data

#==========================================
# Prepare Dockerize template for Auth, composer and MTF config
#==========================================
COPY conf/dockerize/auth.json.tmpl \
        conf/dockerize/composer.json.tmpl \
        conf/dockerize/mtf/phpunit.xml.tmpl \
        conf/dockerize/mtf/credentials.xml.tmpl \
        conf/dockerize/mtf/etc/config.xml.tmpl \
        /home/magento2/dockerize/

#==========================================
# Magento2 install
#==========================================
RUN chown -R magento2:magento2 $DOCKERIZE_TEMPLATES_PATH \
 && chown -R magento2:www-data /var/www/html/magento2/ \
 && gosu magento2 mkdir /home/magento2/.composer/ \
 && gosu magento2 dockerize -template $DOCKERIZE_TEMPLATES_PATH/auth.json.tmpl:/home/magento2/.composer/auth.json -template $DOCKERIZE_TEMPLATES_PATH/composer.json.tmpl:/var/www/html/magento2/composer.json \
 && gosu magento2 composer global require hirak/prestissimo \
 && gosu magento2 composer install --no-progress --profile \
 && chown -R magento2:www-data . \
 && find . -type d -exec chmod 770 {} \; \
 && find . -type f -exec chmod 660 {} \; \
 && chmod u+x bin/magento \
 && gosu magento2 sed -i -e"s/\"minimum-stability\": \"alpha\"/\"minimum-stability\": \"dev\"/g" composer.json

# magento and phpunit binaries to global path
ENV PATH=/var/www/html/magento2/dev/tests/functional/vendor/bin:/var/www/html/magento2/bin:$PATH
RUN echo "PATH=/var/www/html/magento2/dev/tests/functional/vendor/bin:/var/www/html/magento2/bin:$PATH" >> /home/magento2/.profile

ENTRYPOINT ["magento2-start"]
