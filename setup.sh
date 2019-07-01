#! /bin/bash
# This script is for automatic setting different WordPress with LAMP stack
# Usage: ./setup.sh {domain names} 
# E.g. ./setup.sh cole.com colethebest.com.au colewin.edu.au

# Check if the website name exists and is acceptable
#
# Existance check
if [ $# -eq "0" ]; then
	echo "Missing an argument for domain name. Please have a check"
	exit
fi

# Acceptance check by regular expression
# Required a naked website name, specifically not starting with "www."
# e.g. cole.com is acceptable while www.cole.com is acceptable
re_match='^([a-z0-9]+\.)*[a-z0-9]+\.[a-z]+'
re_not_match='^www\..*'
for domain in $@
do
	if ! [[ ! $domain =~ $re_not_match && $domain =~ $re_match ]]; then
		echo 'Required a naked domain name, specifically not starting with "www."'
		echo 'e.g. cole.com.au is acceptable while www.cole.com.au is not acceptable'
		echo "\"$domain\" is unacceptable, please try again"
		exit
	fi
done

echo "##################################################################"
echo "IMPORTANT! Please ensure your domains are good"
echo "current domain name: {$@}"
echo "press y/Y and enter to continue, other keys to exit..."
echo "##################################################################"
read IS_CONTINUE
if [ $IS_CONTINUE != 'y' ] && [ $IS_CONTINUE != 'Y' ]; then
	exit
fi

#--------------------------------------------------------------------------------
#				Install LAMP stack
#--------------------------------------------------------------------------------
echo "==============================================================="
echo "Install LAMP stack"
echo "==============================================================="

# Apache
echo "================="
echo "Installing Apache"
echo "================="
sudo apt-get update
sudo apt-get install apache2 -y
sudo systemctl restart apache2 
sudo ufw allow in "Apache Full"

# MySQL
echo "================="
echo "Installing MySQL"
echo "================="
sudo apt-get install mysql-server -y
echo "##################################################################"
echo "Important: Please enter your mysql password(not user pwd) in the following section, and security level 1 is recommended. Next, please choose yes to all the questions followed"
echo "##################################################################"
mysql_secure_installation

# PHP
echo "================="
echo "Installing PHP"
echo "================="
sudo apt-get install php libapache2-mod-php php-mcrypt php-mysql -y
REPLACE_TEXT="DirectoryIndex index.html index.cgi index.pl index.php index.xhtml index.htm"
REPLACE_WITH="DirectoryIndex index.php index.html index.cgi index.pl index.xhtml index.htm"
`sudo sed -i "s|${REPLACE_TEXT}|${REPLACE_WITH}|g" /etc/apache2/mods-enabled/dir.conf`
if [ "$?" -ne "0" ]; then
	echo "Something wrong with writing code into dir.conf"
	exit
fi
sudo systemctl restart apache2

echo "################################################################"
echo "LAMP Stack has been installed on your computer"
echo "################################################################"

#--------------------------------------------------------------------------------
#				  Install WordPress
#--------------------------------------------------------------------------------
echo "==============================================================="
echo "Install WordPress"
echo "==============================================================="
echo "Setup WordPress database"

# PHP extensions
sudo apt-get install php-curl php-gd php-mbstring php-mcrypt php-xml php-xmlrpc -y
sudo systemctl restart apache2

# Allow .htaccess
APPEND_HTASTR1="<Directory /var/www/html/>"
APPEND_HTASTR2="AllowOverride All"
APPEND_HTASTR3="</Directory>"
`sudo sed -i "$ a\${APPEND_HTASTR1}" /etc/apache2/apache2.conf`
`sudo sed -i "$ a\${APPEND_HTASTR2}" /etc/apache2/apache2.conf`
`sudo sed -i "$ a\${APPEND_HTASTR3}" /etc/apache2/apache2.conf`
sudo a2enmod rewrite
sudo systemctl restart apache2

#Download WordPress
sudo apt-get install curl -y
cd /tmp && curl -O https://wordpress.org/latest.tar.gz
cd /tmp && tar xzvf latest.tar.gz
touch /tmp/wordpress/.htaccess
chmod 660 /tmp/wordpress/.htaccess
sudo cp /tmp/wordpress/wp-config-sample.php /tmp/wordpress/wp-config.php
sudo mkdir /tmp/wordpress/wp-content/upgrade

# Ask whether need SSL installation
echo "Do you need SSL(https) installation?(y/Y for yes, other keys for no)"
read IS_SSL

# Start install database
echo "To install database for your websites, please enter your mysql password here"
read MYSQLPWD
	
until mysql -u root -p$MYSQLPWD -e ";" ; do
	read -p "Cannot connect, please enter your mysql password again: " MYSQLPWD
done

DOMAIN_REG=`echo "$1" | sed -r 's/\./_/g'`
DEFAULT_DBNAME="${DOMAIN_REG}"
DEFAULT_DBUSERNAME="${DOMAIN_REG}_user"
DEFAULT_DBPWD="(${DOMAIN_REG}_Pwd0)"

echo "##################################################################"
echo "IMPORTANT! Default setting for $1 is like:"
echo "Database name: ${DEFAULT_DBNAME}"
echo "Username: ${DEFAULT_DBUSERNAME}"
echo "Password: ${DEFAULT_DBPWD}"
echo "Other websites are SIMILAR, just replace the domain name."
echo "If you want to customise your setting, please answer anthing except y/Y in the NEXT question."
echo "##################################################################"
echo "Do you want to remain default settings?(y/Y for yes, else for no)"
read IS_DEFAULT

########1st iteration start
for domain in $@
do
	echo "##################################################################"
	echo "Start $domain configuration..."
	echo "##################################################################"
	DOMAIN_REG=`echo "${domain}" | sed -r 's/\./_/g'`
	DEFAULT_DBNAME="${DOMAIN_REG}"
	DEFAULT_DBUSERNAME="${DOMAIN_REG}_user"
	DEFAULT_DBPWD="(${DOMAIN_REG}_Pwd0)"

	if [ ${IS_DEFAULT} != "y" ] && [ ${IS_DEFAULT} != "Y" ]; then
		echo "Tell me your ideal website database's name"
		read DBNAME
		until mysql -u root -p$MYSQLPWD -Bse "CREATE DATABASE ${DBNAME} DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;" ; do
			read -p "Your database name has been used, please try another: " DBNAME
		done

		echo "Tell me your favourite username for ${DBNAME} database"
		read DBUSERNAME
		echo "Tell me your favourite password for ${DBNAME} database"
		read DBPWD
		until mysql -u root -p$MYSQLPWD -Bse "GRANT ALL ON ${DBNAME}.* TO '${DBUSERNAME}'@'localhost' IDENTIFIED BY '${DBPWD}';" ; do
            echo "Your username or password is not acceptable, please check the errors above and change your info"
            read -p "username for ${DBNAME}: " DBUSERNAME
            read -p "password: " DBPWD
        done
		mysql -u root -p$MYSQLPWD -Bse "FLUSH PRIVILEGES;"
	else
		mysql -u root -p$MYSQLPWD -Bse "CREATE DATABASE ${DEFAULT_DBNAME} DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;"
		mysql -u root -p$MYSQLPWD -Bse "GRANT ALL ON ${DEFAULT_DBNAME}.* TO '${DEFAULT_DBUSERNAME}'@'localhost' IDENTIFIED BY '${DEFAULT_DBPWD}';"
		mysql -u root -p$MYSQLPWD -Bse "FLUSH PRIVILEGES;"
	fi

	# Copy WordPress folder to each website
	WORDPRESS_DIR="/var/www/html/${domain}"
	sudo cp -a /tmp/wordpress/. "${WORDPRESS_DIR}"
	sudo chown -R ${USER}:www-data "${WORDPRESS_DIR}"
	sudo find "${WORDPRESS_DIR}" -type d -exec chmod g+s {} \;
	sudo chmod g+w "${WORDPRESS_DIR}/wp-content"
	sudo chmod -R g+w "${WORDPRESS_DIR}/wp-content/themes"
	sudo chmod -R g+w "${WORDPRESS_DIR}/wp-content/plugins"

	# Config WordPress wp-config.php
	WP_CONFIG_PHP_DIR="${WORDPRESS_DIR}/wp-config.php"

	WP_CONFIG_DBNAME=${DEFAULT_DBNAME}
	WP_CONFIG_DBUSERNAME=${DEFAULT_DBUSERNAME}
	WP_CONFIG_DBPWD=${DEFAULT_DBPWD}
	if [ ${IS_DEFAULT} != "y" ] && [ ${IS_DEFAULT} != "Y" ]; then
		WP_CONFIG_DBNAME=${DBNAME}
		WP_CONFIG_DBUSERNAME=${DBUSERNAME}
		WP_CONFIG_DBPWD=${DBPWD}
	fi
	
	DB_TEXT="define('DB_NAME', '${WP_CONFIG_DBNAME}');"
	DB_REPLACE_TEXT="define('DB_NAME', 'database_name_here');"
	`sudo sed -i "s|${DB_REPLACE_TEXT}|${DB_TEXT}|g" "${WP_CONFIG_PHP_DIR}"`
	DBUSER_TEXT="define('DB_USER', '${WP_CONFIG_DBUSERNAME}');"
	DBUSER_REPLACE_TEXT="define('DB_USER', 'username_here');"
	`sudo sed -i "s|${DBUSER_REPLACE_TEXT}|${DBUSER_TEXT}|g" "${WP_CONFIG_PHP_DIR}"`
	DBPWD_TEXT="define('DB_PASSWORD', '${WP_CONFIG_DBPWD}');"
	DBPWD_REPLACE_TEXT="define('DB_PASSWORD', 'password_here');"
	`sudo sed -i "s|${DBPWD_REPLACE_TEXT}|${DBPWD_TEXT}|g" "${WP_CONFIG_PHP_DIR}"`
	APPEND_WP_LINE="define('FS_METHOD', 'direct');"
	`sudo sed -i "$ a\${APPEND_WP_LINE}" "${WP_CONFIG_PHP_DIR}"`

	# Apache2 configuration file
	APACHE_CONFIG_DIR="/etc/apache2/sites-available/${domain}.conf"
	DEVELOP_DIR=${WORDPRESS_DIR}
	DOMAIN_REG=`echo "${domain}" | sed -r 's/\./\\\./g'`

	sudo touch "${APACHE_CONFIG_DIR}"
	echo -e "<VirtualHost *:80>" | sudo tee -a "${APACHE_CONFIG_DIR}"
	echo -e "\tServerName ${domain}" | sudo tee -a "${APACHE_CONFIG_DIR}"
	echo -e "\tServerAlias www.${domain}" | sudo tee -a "${APACHE_CONFIG_DIR}"
	echo -e "\tDocumentRoot ${DEVELOP_DIR}" | sudo tee -a "${APACHE_CONFIG_DIR}"
	echo -e "\t<Directory ${DEVELOP_DIR}>" | sudo tee -a "${APACHE_CONFIG_DIR}"
	echo -e "\t\tRequire all granted" | sudo tee -a "${APACHE_CONFIG_DIR}"
	echo -e "\t\tAllowOverride all" | sudo tee -a "${APACHE_CONFIG_DIR}"
	echo -e "\t</Directory>" | sudo tee -a "${APACHE_CONFIG_DIR}"
	echo -e "\tRewriteEngine on" | sudo tee -a "${APACHE_CONFIG_DIR}"
	echo -e "\tRewriteOptions inherit" | sudo tee -a "${APACHE_CONFIG_DIR}"
	echo -e "\tRewriteRule \\.(svn|git)(/)?\$ - [F]" | sudo tee -a "${APACHE_CONFIG_DIR}"
	if [ $IS_SSL = "y" ] || [ $IS_SSL = "Y" ]; then
		echo -e "\tRewriteCond %{HTTPS} off [OR]" | sudo tee -a "${APACHE_CONFIG_DIR}"
	fi
	echo -e "\tRewriteCond %{HTTP_HOST} ^www\.${DOMAIN_REG} [NC]" | sudo tee -a "${APACHE_CONFIG_DIR}"
	if [ $IS_SSL = "y" ] || [ $IS_SSL = "Y" ]; then
		echo -e "\tRewriteRule ^/(.*)\$ https://%{SERVER_NAME}/\${domain} [R,L]" | sudo tee -a "${APACHE_CONFIG_DIR}"
	else
		echo -e "\tRewriteRule ^/(.*)\$ http://%{SERVER_NAME}/\${domain} [R,L]" | sudo tee -a "${APACHE_CONFIG_DIR}"
	fi
	echo -e "\t<IfModule mod_headers.c>" | sudo tee -a "${APACHE_CONFIG_DIR}"
	echo -e "\t\tHeader set X-XSS-Protection \"1; mode=block\"" | sudo tee -a "${APACHE_CONFIG_DIR}"
	echo -e "\t\tHeader always append X-Frame-Options SAMEORIGIN" | sudo tee -a "${APACHE_CONFIG_DIR}"
	echo -e "\t</IfModule>" | sudo tee -a "${APACHE_CONFIG_DIR}"
	echo -e "</VirtualHost>" | sudo tee -a "${APACHE_CONFIG_DIR}"

	# Enable the site
	sudo apt-get install php-gd -y
	sudo a2ensite ${domain}
	sudo service apache2 reload
done
########1st iteration end

#SSL
if [ $IS_SSL != "y" ] && [ $IS_SSL != "Y" ]; then
	echo "#########################################################################"
	echo "CONGRATS! You have setup your websites{$@}, go and have a look!"
	echo "#########################################################################"
	exit
fi
echo "DOING SSL STUFF..."
sudo add-apt-repository ppa:certbot/certbot
sudo apt-get update
sudo apt-get install python-certbot-apache -y

########2nd iteration start
for domain in $@
do
	sudo certbot --apache -d ${domain}
done
########2nd iteration end

echo "#########################################################################"
echo "CONGRATS! You have setup your websites{$@}, go and have a look!"
echo "#########################################################################"

