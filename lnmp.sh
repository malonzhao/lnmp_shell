#!/bin/bash
LOCAL_ROOT=$(
  cd "$(dirname "$0")" || exit
  pwd
)
ACME_ROOT=$LOCAL_ROOT/acme
LOCAL_CERT=$ACME_ROOT/certs
LOCAL_CONF=$LOCAL_ROOT/confs
LOCAL_SERVICE=$LOCAL_ROOT/services
LOCAL_TEMPLATE=$LOCAL_ROOT/templates
REMOTE_ROOT=/wwwroot
REMOTE_BACKUP=$REMOTE_ROOT/backups
REMOTE_CERT=$REMOTE_ROOT/certs
REMOTE_CONF=$REMOTE_ROOT/confs
REMOTE_DATA=$REMOTE_ROOT/data
REMOTE_LOG=$REMOTE_ROOT/logs
REMOTE_RUN=$REMOTE_ROOT/run
REMOTE_SITE=$REMOTE_ROOT/sites
REMOTE_SOFT=$REMOTE_ROOT/softs
REMOTE_SERVICE=/etc/systemd/system

NGINX_VER="1.18.0"
PHP_VER="7.4.13"
MYSQL_VER="8.0.22"

get_host() {
  if [ -z "$REMOTE_HOST" ]; then
    read -r -p "(请输入一个主机（例如：root@localhost）: " REMOTE_HOST
    if [ -z "$REMOTE_HOST" ]; then
      echo "主机不能为空"
      exit
    fi
  fi
}

acme_install() {
  local_folder_create "$ACME_ROOT"
  read -r -p "请输入邮箱: " email
  if [ -z "$email" ]; then
    echo "邮箱不能为空"
    exit
  fi
  wget -O - https://raw.githubusercontent.com/acmesh-official/acme.sh/master/acme.sh || exit
  sh ./acme.sh --install -m "$email" --home "$ACME_ROOT" --config-home "$ACME_ROOT"/config --cert-home "$LOCAL_CERT"
  rm -rf acme.sh
}

common_libs_install() {
  ssh "$REMOTE_HOST" "apt update && apt upgrade -y && apt autoremove -y"
  ssh "$REMOTE_HOST" "apt install libssl-dev libzip-dev pkg-config -y"
}

get_domain() {
  if [ -z "$DOMAIN" ]; then
    read -r -p "(请输入一个域名: " DOMAIN
    if [ -z "$DOMAIN" ]; then
      echo "域名不能为空"
      exit
    fi
  fi
  for str in ${DOMAIN//./ }; do
    DOMAIN_REVERSED=$str$DOMAIN_REVERSED
  done
}

local_folder_create() {
  if [ ! -d "$1" ]; then mkdir -p "$1"; fi
}
remote_folder_create() {
  ssh "$REMOTE_HOST" "if [ ! -d $REMOTE_ROOT ]; then mkdir -p $REMOTE_ROOT; fi"
  ssh "$REMOTE_HOST" "if [ ! -d $REMOTE_CERT ]; then mkdir -p $REMOTE_CERT; fi"
  ssh "$REMOTE_HOST" "if [ ! -d $REMOTE_CONF ]; then mkdir -p $REMOTE_CONF; fi"
  ssh "$REMOTE_HOST" "if [ ! -d $REMOTE_DATA ]; then mkdir -p $REMOTE_DATA; fi"
  ssh "$REMOTE_HOST" "if [ ! -d $REMOTE_LOG ]; then mkdir -p $REMOTE_LOG; fi"
  ssh "$REMOTE_HOST" "if [ ! -d $REMOTE_RUN ]; then mkdir -p $REMOTE_RUN; fi"
  ssh "$REMOTE_HOST" "if [ ! -d $REMOTE_SOFT ]; then mkdir -p $REMOTE_SOFT; fi"
  ssh "$REMOTE_HOST" "if [ ! -d $REMOTE_BACKUP ]; then mkdir -p $REMOTE_BACKUP; fi"
}

remote_user_create() {
  ssh "$REMOTE_HOST" "useradd -m -d $REMOTE_SITE -s /usr/sbin/nologin www"
  ssh "$REMOTE_HOST" "useradd -r -s /bin/false mysql"
}

nginx_install() {
  ssh "$REMOTE_HOST" "apt install libpcre3-dev -y"
  ssh "$REMOTE_HOST" "cd $REMOTE_SOFT;
  if [ ! -f nginx-$NGINX_VER.tar.gz ];then curl -g http://nginx.org/download/nginx-$NGINX_VER.tar.gz -o nginx-$NGINX_VER.tar.gz -#; fi;
  if [ ! -d nginx-$NGINX_VER ];then tar zxvf nginx-$NGINX_VER.tar.gz && cd nginx-$NGINX_VER;fi;
  ./configure --prefix=$REMOTE_SOFT/nginx --conf-path=$REMOTE_CONF/nginx/nginx.conf --error-log-path=$REMOTE_LOG/nginx/error.log --pid-path=$REMOTE_RUN/nginx/nginx.pid --user=www --group=www --with-http_ssl_module --with-http_v2_module;
  make && make install;
  cd .. && rm -rf nginx-$NGINX_VER"
}

nginx_config() {
  ssh "$REMOTE_HOST" "mkdir -p $REMOTE_LOG/www"
  ssh "$REMOTE_HOST" "mkdir -p $REMOTE_CONF/nginx/vhosts"
  scp -r "$LOCAL_CONF"/nginx/* "$REMOTE_HOST":"$REMOTE_CONF"/nginx/
  scp "$LOCAL_SERVICE"/nginx.service "$REMOTE_HOST":"$REMOTE_SERVICE"
  ssh "$REMOTE_HOST" "sed -i 's/{REMOTE_ROOT}/\\$REMOTE_ROOT/g' $REMOTE_SERVICE/nginx.service"
  ssh "$REMOTE_HOST" "sed -i 's/{REMOTE_ROOT}/\\$REMOTE_ROOT/g' $REMOTE_CONF/nginx/modules/php.conf"
  ssh "$REMOTE_HOST" "systemctl enable nginx && systemctl start nginx"
}

nginx_restart() {
  ssh "$REMOTE_HOST" "systemctl restart nginx"
}

nginx_uninstall() {
  ssh "$REMOTE_HOST" "systemctl stop nginx && systemctl disable nginx"
  ssh "$REMOTE_HOST" "rm -rf $REMOTE_SOFT/nginx $REMOTE_LOG/nginx $REMOTE_RUN/nginx $REMOTE_SERVICE/nginx.service"
}

php_install() {
  ssh "$REMOTE_HOST" "apt install libxml++2.6-dev libsqlite3-dev libcurl4-openssl-dev libpng-dev libwebp-dev libjpeg-dev libxpm-dev libfreetype-dev libonig-dev libxslt1-dev -y"
  ssh "$REMOTE_HOST" "cd $REMOTE_SOFT;
  if [ ! -f php-$PHP_VER.tar.xz ];then curl -g https://www.php.net/distributions/php-$PHP_VER.tar.xz -o php-$PHP_VER.tar.xz -#; fi;
  if [ ! -d php-$PHP_VER ];then tar -Jxf php-$PHP_VER.tar.xz && cd php-$PHP_VER;fi;
  ./configure --prefix=$REMOTE_SOFT/php --exec-prefix=$REMOTE_SOFT/php --bindir=$REMOTE_SOFT/php/bin --sbindir=$REMOTE_SOFT/php/sbin --includedir=$REMOTE_SOFT/php/include --libdir=$REMOTE_SOFT/php/lib --mandir=$REMOTE_SOFT/php/man --sysconfdir=$REMOTE_CONF/php --with-config-file-path=$REMOTE_CONF/php --enable-bcmath --with-mhash --with-openssl --with-mysqli --with-pdo-mysql --enable-gd --with-iconv-dir --with-zlib --with-libdir=lib64 --with-zip --disable-debug --enable-shared --enable-xml --with-xsl --enable-mbregex --enable-mbstring --enable-ftp --enable-pcntl --enable-sockets --with-xmlrpc --enable-soap --with-pear --with-gettext --enable-session --with-curl --with-jpeg --with-freetype --with-webp --with-xpm --enable-opcache --enable-fileinfo --enable-fpm --with-fpm-user=www --with-fpm-group=www;
  make && make install;
  cd .. && rm -rf php-$PHP_VER"
}

php_config() {
  ssh "$REMOTE_HOST" "mkdir -p $REMOTE_LOG/php"
  ssh "$REMOTE_HOST" "mkdir -p $REMOTE_CONF/php"
  ssh "$REMOTE_HOST" "mkdir -p $REMOTE_RUN/php"
  scp -r "$LOCAL_CONF"/php/* "$REMOTE_HOST":"$REMOTE_CONF"/php
  scp "$LOCAL_SERVICE"/php-fpm.service "$REMOTE_HOST":"$REMOTE_SERVICE"
  ssh "$REMOTE_HOST" "sed -i 's/{REMOTE_ROOT}/\\$REMOTE_ROOT/g' $REMOTE_SERVICE/php-fpm.service"
  ssh "$REMOTE_HOST" "sed -i 's/{REMOTE_ROOT}/\\$REMOTE_ROOT/g' $REMOTE_CONF/php/php-fpm.conf"
  ssh "$REMOTE_HOST" "sed -i 's/{REMOTE_ROOT}/\\$REMOTE_ROOT/g' $REMOTE_CONF/php/php-fpm.d/www.conf"
  ssh "$REMOTE_HOST" "systemctl enable php-fpm && systemctl start php-fpm"
}

php_restart() {
  ssh "$REMOTE_HOST" "systemctl restart php-fpm"
}

php_uninstall() {
  ssh "$REMOTE_HOST" "systemctl stop php-fpm && systemctl disable php-fpm"
  ssh "$REMOTE_HOST" "rm -rf $REMOTE_SOFT/php* $REMOTE_LOG/php $REMOTE_RUN/php $REMOTE_SERVICE/php-fpm.service"
}

redis_install() {
  ssh "$REMOTE_HOST" "cd $REMOTE_SOFT;
  if [ ! -f redis-stable.tar.gz ]; then curl -g https://download.redis.io/redis-stable.tar.gz -o redis-stable.tar.gz -#; fi
  if [ ! -d redis-stable ];then tar zxvf redis-stable.tar.gz;fi;
  cd redis-stable/src && make && make PREFIX=$REMOTE_SOFT/redis install;
  cd ../.. && rm -rf redis-stable"
}

redis_config() {
  ssh "$REMOTE_HOST" "mkdir -p $REMOTE_LOG/redis"
  ssh "$REMOTE_HOST" "mkdir -p $REMOTE_CONF/redis"
  ssh "$REMOTE_HOST" "mkdir -p $REMOTE_RUN/redis"
  scp "$LOCAL_CONF"/redis/redis.conf "$REMOTE_HOST":"$REMOTE_CONF/redis/6379.conf"
  ssh "$REMOTE_HOST" "sed -i 's/{REMOTE_ROOT}/\\$REMOTE_ROOT/g' $REMOTE_CONF/redis/6379.conf"
  ssh "$REMOTE_HOST" "sed -i 's/{port}/6379/g' $REMOTE_CONF/redis/6379.conf"
  scp "$LOCAL_SERVICE"/redis.service "$REMOTE_HOST":"$REMOTE_SERVICE/redis-6379.service"
  ssh "$REMOTE_HOST" "sed -i 's/{REMOTE_ROOT}/\\$REMOTE_ROOT/g' $REMOTE_SERVICE/redis-6379.service"
  ssh "$REMOTE_HOST" "sed -i 's/{port}/6379/g' $REMOTE_SERVICE/redis-6379.service"
  ssh "$REMOTE_HOST" "systemctl enable redis-6379 && systemctl start redis-6379"
}

redis_uninstall() {
  ssh "$REMOTE_HOST" "systemctl stop redis-6379 && systemctl disable redis-6379"
  ssh "$REMOTE_HOST" "rm -rf $REMOTE_SOFT/redis $REMOTE_LOG/redis $REMOTE_RUN/redis $REMOTE_SERVICE/redis-6379.service"
}

mysql_install() {
  ssh "$REMOTE_HOST" "apt install gcc g++ cmake bison libboost-dev libncurses-dev zlib1g-dev git -y"
  ssh "$REMOTE_HOST" "cd $REMOTE_SOFT;
  if [ ! -f mysql-$MYSQL_VER.tar.gz ];then curl -g https://cdn.mysql.com/Downloads/MySQL-8.0/mysql-$MYSQL_VER.tar.gz -o mysql-$MYSQL_VER.tar.gz -#;fi;
  if [ ! -d mysql-$MYSQL_VER ];then tar zxvf mysql-$MYSQL_VER.tar.gz;fi;
  cd mysql-$MYSQL_VER;
  rm -rf bld && mkdir bld && cd bld;
  cmake .. -DCMAKE_BUILD_TYPE=Release -DFORCE_INSOURCE_BUILD=1 -DCMAKE_INSTALL_PREFIX=$REMOTE_SOFT/mysql -DMYSQL_DATADIR=$REMOTE_DATA/mysql -DSYSCONFDIR=$REMOTE_CONF/mysql -DDOWNLOAD_BOOST=1 -DWITH_BOOST=/usr/include/boost -DWITH_MYSQLX=0 -DWITH_UNIT_TESTS=0 -DINSTALL_MYSQLTESTDIR=;
  make && make install;
  cd .. && rm -rf mysql-$MYSQL_VER"
}

mysql_config() {
  ssh "$REMOTE_HOST" "mkdir -p $REMOTE_CONF/mysql && chown mysql:mysql $REMOTE_CONF/mysql"
  ssh "$REMOTE_HOST" "mkdir -p $REMOTE_DATA/mysql && chown mysql:mysql $REMOTE_DATA/mysql"
  ssh "$REMOTE_HOST" "mkdir -p $REMOTE_LOG/mysql && chown mysql:mysql $REMOTE_LOG/mysql"
  ssh "$REMOTE_HOST" "mkdir -p $REMOTE_RUN/mysql && chown mysql:mysql $REMOTE_RUN/mysql"
  scp -r "$LOCAL_CONF"/mysql/* "$REMOTE_HOST":"$REMOTE_CONF"/mysql
  ssh "$REMOTE_HOST" "sed -i 's/{REMOTE_ROOT}/\\$REMOTE_ROOT/g' $REMOTE_CONF/mysql/my.cnf"
  scp "$LOCAL_SERVICE"/mysql.service "$REMOTE_HOST":"$REMOTE_SERVICE"
  ssh "$REMOTE_HOST" "sed -i 's/{REMOTE_ROOT}/\\$REMOTE_ROOT/g' $REMOTE_SERVICE/mysql.service"
  ssh "$REMOTE_HOST" "cd $REMOTE_SOFT/mysql;
  bin/mysqld --initialize-insecure --user=mysql;
  bin/mysql_ssl_rsa_setup;"
  ssh "$REMOTE_HOST" "systemctl enable mysql && systemctl start mysql"
}

mysql_uninstall() {
  ssh "$REMOTE_HOST" "systemctl stop mysql && systemctl disable mysql"
  ssh "$REMOTE_HOST" "rm -rf $REMOTE_SOFT/mysql $REMOTE_LOG/mysql $REMOTE_RUN/mysql $REMOTE_SERVICE/mysql.service"
  ssh "$REMOTE_HOST" "userdel -r mysql && groupdel mysql"
}

cert_create() {
  "$ACME_ROOT"/acme.sh --issue --dns dns_ali -d "$DOMAIN" -d "*.$DOMAIN"
}

cert_update() {
  "$ACME_ROOT"/acme.sh --renew --dns dns_ali -d "$DOMAIN" -d "*.$DOMAIN"
}

cert_remove() {
  "$ACME_ROOT"/acme.sh --revoke --dns dns_ali -d "$DOMAIN" -d "*.$DOMAIN"
  "$ACME_ROOT"/acme.sh --remove --dns dns_ali -d "$DOMAIN" -d "*.$DOMAIN"
  rm -rf "$LOCAL_CERT/$DOMAIN"
}

cert_upload() {
  scp "$LOCAL_CERT/$DOMAIN/fullchain.cer" "$REMOTE_HOST":"$REMOTE_CERT/$DOMAIN.cer"
  scp "$LOCAL_CERT/$DOMAIN/$DOMAIN.key" "$REMOTE_HOST":"$REMOTE_CERT/$DOMAIN.key"
  scp "$LOCAL_TEMPLATE/ssl.tpl" "$REMOTE_HOST":"$REMOTE_CERT/$DOMAIN.conf"
  ssh "$REMOTE_HOST" "sed -i 's/{DOMAIN}/$DOMAIN/g' $REMOTE_CERT/$DOMAIN.conf"
  ssh "$REMOTE_HOST" "sed -i 's/{REMOTE_ROOT}/\\$REMOTE_ROOT/g' $REMOTE_CERT/$DOMAIN.conf"
}

site_create() {
  ssh "$REMOTE_HOST" "mkdir -p $REMOTE_SITE/$DOMAIN"
  scp -r "$LOCAL_TEMPLATE/errpages" "$REMOTE_HOST":"$REMOTE_SITE/$DOMAIN/"
  ssh "$REMOTE_HOST" "chown -R www:www $REMOTE_SITE/$DOMAIN"
  scp "$LOCAL_TEMPLATE"/host.tpl "$REMOTE_HOST":"$REMOTE_CONF/nginx/vhosts/$DOMAIN.conf"
  ssh "$REMOTE_HOST" "sed -i 's/{DOMAIN}/$DOMAIN/g' $REMOTE_CONF/nginx/vhosts/$DOMAIN.conf"
  ssh "$REMOTE_HOST" "sed -i 's/{REMOTE_ROOT}/\\$REMOTE_ROOT/g' $REMOTE_CONF/nginx/vhosts/$DOMAIN.conf"
}

site_backup() {
  suffix=$(date +%Y%m%d%H%M)
  ssh "$REMOTE_HOST" "cp -r $REMOTE_SITE/$DOMAIN $REMOTE_BACKUP/$DOMAIN-$suffix-www"
  ssh "$REMOTE_HOST" "if [ ! -d $REMOTE_BACKUP/$DOMAIN-$suffix-cert ];then mkdir -p $REMOTE_BACKUP/$DOMAIN-$suffix-cert; fi;"
  ssh "$REMOTE_HOST" "cp -r $REMOTE_CERT/$DOMAIN.* $REMOTE_BACKUP/$DOMAIN-$suffix-cert"
  ssh "$REMOTE_HOST" "cp $REMOTE_CONF/nginx/vhosts/$DOMAIN.conf $REMOTE_BACKUP/$DOMAIN-$suffix.conf"
}

site_remove() {
  ssh "$REMOTE_HOST" "rm -rf $REMOTE_SITE/$DOMAIN"
  ssh "$REMOTE_HOST" "rm -rf $REMOTE_CONF/nginx/vhosts/$DOMAIN.conf"
  ssh "$REMOTE_HOST" "rm -rf $REMOTE_CERT/$DOMAIN.*"
  ssh "$REMOTE_HOST" "rm -rf $REMOTE_LOG/www/$DOMAIN.*"
}

site_ssl_enable() {
  main "--create-cert"
  ssh "$REMOTE_HOST" "sed -i '18,\$s/^#//g' $REMOTE_CONF/nginx/vhosts/$DOMAIN.conf"
}

site_ssl_disable() {
  main "--remove-cert"
  ssh "$REMOTE_HOST" "sed -i '18,\$s/^/#/g' $REMOTE_CONF/nginx/vhosts/$DOMAIN.conf"
}

main() {
  case "$1" in
  -ni | --nginx-install)
    get_host
    remote_folder_create
    remote_user_create
    common_libs_install
    nginx_install
    nginx_config
    ;;
  -nr | --nginx-restart)
    get_host
    nginx_restart
    ;;
  -nu | --nginx-uninstall)
    get_host
    nginx_uninstall
    ;;
  -pi | --php-install)
    get_host
    remote_folder_create
    remote_user_create
    common_libs_install
    php_install
    php_config
    ;;
  -pr | --php-restart)
    get_host
    php_restart
    ;;
  -pu | --php-uninstall)
    get_host
    php_uninstall
    ;;
  -mi | --mysql-install)
    get_host
    remote_folder_create
    remote_user_create
    common_libs_install
    mysql_install
    mysql_config
    ;;
  -mu | --mysql-uninstall)
    get_host
    mysql_uninstall
    ;;
  -ri | --redis-install)
    get_host
    redis_install
    redis_config
    ;;
  -ru | --redis-uninstall)
    get_host
    redis_uninstall
    ;;
  -ai | --all-install)
    get_host
    main "-ni"
    main "-pi"
    main "-mi"
    main "-ri"
    ;;
  -au | --all-uninstall)
    get_host
    main "-nu"
    main "-pu"
    main "-mu"
    main "-ru"
    ;;
  -cc | --cert-create)
    get_domain
    cert_create
    main "-cs"
    ;;
  -cu | --cert-update)
    get_domain
    cert_update
    main "-cs"
    ;;
  -cr | --cert-remove)
    get_domain
    cert_remove
    ;;
  -ca | --cert-sync)
    get_domain
    get_host
    cert_upload
    nginx_restart
    ;;
  -sc | --site-create)
    get_domain
    get_host
    site_create
    nginx_restart
    ;;
  -sb | --site-backup)
    site_backup
    ;;
  -sr | --site-remove)
    get_domain
    get_host
    site_backup
    site_remove
    nginx_restart
    ;;
  -sse | --site-ssl-enable)
    get_domain
    get_host
    site_ssl_enable
    nginx_restart
    ;;
  -ssd | --site-ssl-disable)
    get_domain
    get_host
    site_disable_ssl
    nginx_restart
    ;;
  -ssc | --ssl-site-create)
    get_domain
    get_host
    site_create
    site_ssl_enable
    nginx_restart
    ;;
  -ssr | --ssl-site-remove)
    get_domain
    get_host
    site_ssl_disable
    site_backup
    site_remove
    nginx_restart
    ;;
  --acme-install)
    acme_install
    ;;
  --install)
    SHRC="$HOME/.${SHELL#/bin/}rc"
    if [ ! -f "$SHRC" ]; then touch "$SHRC"; fi
    echo "alias lnmp=$LOCAL_ROOT/lnmp.sh" >>"$SHRC"
    ;;
  *)
    echo "-ni, --nginx-install        Nginx安装"
    echo "-nr, --nginx-restart        Nginx重启"
    echo "-nu, --nginx-uninstall      Nginx卸载"
    echo "-pi, --php-install          PHP安装"
    echo "-pr, --php-restart          PHP重启"
    echo "-pu, --php-uninstall        PHP卸载"
    echo "-mi, --mysql-install        MySQL安装"
    echo "-mu, --mysql-uninstall      Mysql卸载"
    echo "-ri, --redis-install        Redis安装"
    echo "-ru, --redis-uninstall      Redis卸载"
    echo "-ai, --all-install          全部(Nginx+PHP+MySQL+Redis)安装"
    echo "-au, --all-uninstall        全部(Nginx+PHP+MySQL+Redis)卸载"
    echo "-cc, --cert-create          证书创建"
    echo "-cu, --cert-update          证书更新"
    echo "-cr, --cert-remove          证书删除"
    echo "-cs, --cert-sync            上传证书"
    echo "-sc, --site-create          站点创建"
    echo "-sb, --site-backup          站点备份"
    echo "-sr, --site-remove          站点移除"
    echo "-sse, --site-ssl-enable     站点SSL启用"
    echo "-ssd, --site-ssl-disable    站点SSL关闭"
    echo "-ssc, --ssl-site-create     SSL站点创建"
    echo "-ssr, --ssl-site-remove     SSL站点移除"
    echo "--acme-install              ACME.SH安装"
    echo "--install                   LNMP脚本安装"
    return 1
    ;;
  esac
  return 0
}
main "$@"
