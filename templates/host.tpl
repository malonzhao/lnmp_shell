################ HTTP SERVER ################
server {
	listen       80;
	server_name  {DOMAIN};
	root   {REMOTE_ROOT}/sites/{DOMAIN};
	access_log  {REMOTE_ROOT}/logs/www/{DOMAIN}.access.log;
	error_log  {REMOTE_ROOT}/logs/www/{DOMAIN}.error.log;
	location / {
		index  index.html index.htm index.php;
	}
	include {REMOTE_ROOT}/confs/nginx/modules/browser_cache.conf;
	include {REMOTE_ROOT}/confs/nginx/modules/errpages.conf;
#	include {REMOTE_ROOT}/confs/nginx/modules/https_redirect.conf;
#	include {REMOTE_ROOT}/confs/nginx/modules/php.conf;
}

############### HTTPS SERVER ###############
#server {
#	listen       443 ssl http2;
#	server_name  {DOMAIN};
#	root   {REMOTE_ROOT}/sites/{DOMAIN};
#	access_log  {REMOTE_ROOT}/logs/www/{DOMAIN}.access.log;
#	error_log  {REMOTE_ROOT}/logs/www/{DOMAIN}.error.log;
#	add_header  Strict-Transport-Security "max-age=31536000";
#	location / {
#		index  index.html index.htm index.php;
#	}
#	include {REMOTE_ROOT}/confs/nginx/modules/browser_cache.conf;
#	include {REMOTE_ROOT}/confs/nginx/modules/errpages.conf;
#	include {REMOTE_ROOT}/confs/nginx/modules/php.conf;
#	include {REMOTE_ROOT}/certs/{DOMAIN}.conf;
#}