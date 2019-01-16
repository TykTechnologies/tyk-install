
# Basic install script/instructions for Tyk Pro (Gateway, Dashboard and Pump) for Centos7

# Version 1.2.0
# Peter Harris

# NOTE: There are some very simple manual steps at the bottom of this file

# The Dashboard requires a valid "On Premise" licence to be issued by Tyk.  Please visit https://tyk.io/ and push the "GET STARTED" button

# This script/instructions are intended to be used by a person with operational experience of Linux.
# All of the required components are installed onto a single platform and intended solely for simple evaluation purposes.
# There is very limited security provided and must NOT be used for production environments.


#Enable abort on error handling
#==============================
set -e


#Update platform
#===============
sudo yum upgrade -y
#nmtui


#Add utilites for debug
#======================
sudo yum install net-tools -y


#Redis
#=====
sudo yum install epel-release -y
sudo yum install redis -y
sudo systemctl restart redis


#Mongo
#=====
sudo sh -c "echo '
[mongodb-org-4.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/7Server/mongodb-org/4.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-4.0.asc
' > /etc/yum.repos.d/mongodb-org-4.0.repo"

sudo yum install mongodb-org -y
sudo systemctl restart mongod


#Dashboard
#=========
sudo sh -c "echo '
[tyk_tyk-dashboard]
name=tyk_tyk-dashboard
baseurl=https://packagecloud.io/tyk/tyk-dashboard/el/7/\$basearch
repo_gpgcheck=1
gpgcheck=0
enabled=1
gpgkey=https://packagecloud.io/tyk/tyk-dashboard/gpgkey
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
metadata_expire=300
' > /etc/yum.repos.d/tyk_tyk-dashboard.repo"

sudo yum install tyk-dashboard -y

sudo /opt/tyk-dashboard/install/setup.sh --listenport=3000 --redishost=localhost --redisport=6379 --mongo=mongodb://localhost/tyk_analytics --tyk_api_hostname=localhost --tyk_node_hostname=http://localhost --tyk_node_port=8080 --portal_root=/portal --domain=localhost

sudo systemctl restart tyk-dashboard


#Pump
#====
sudo sh -c "echo '
[tyk_tyk-pump]
name=tyk_tyk-pump
baseurl=https://packagecloud.io/tyk/tyk-pump/el/7/\$basearch
repo_gpgcheck=1
gpgcheck=0
enabled=1
gpgkey=https://packagecloud.io/tyk/tyk-pump/gpgkey
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
metadata_expire=300
' > /etc/yum.repos.d/tyk_tyk-pump.repo"

sudo yum install tyk-pump -y
sudo systemctl restart tyk-pump


#Gateway
#=======
sudo sh -c "echo '
[tyk_tyk-gateway]
name=tyk_tyk-gateway
baseurl=https://packagecloud.io/tyk/tyk-gateway/el/7/\$basearch
repo_gpgcheck=1
gpgcheck=0
enabled=1
gpgkey=https://packagecloud.io/tyk/tyk-gateway/gpgkey
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
metadata_expire=300
' > /etc/yum.repos.d/tyk_tyk-gateway.repo"

sudo yum install tyk-gateway -y

echo '
{
  "allow_insecure_configs": true,
  "listen_address": "",
  "listen_port": 8080,
  "secret": "352d20ee67be67f6340b4c0605b044b7",
  "node_secret": "352d20ee67be67f6340b4c0605b044b7",
  "template_path": "/opt/tyk-gateway/templates",
  "use_db_app_configs": true,
  "db_app_conf_options": {
    "connection_string": "http://localhost:3000"
  },
  "app_path": "/opt/tyk-gateway/apps",
  "middleware_path": "/opt/tyk-gateway/middleware",
  "storage": {
    "type": "redis",
    "host": "localhost",
    "port": 6379,
    "optimisation_max_idle": 2000,
    "optimisation_max_active": 4000
  },
  "enable_analytics": true,
  "analytics_config": {
    "type": "",
    "ignored_ips": []
  },
  "optimisations_use_async_session_write": true,
  "allow_master_keys": false,
  "policies": {
    "policy_source": "service",
    "policy_connection_string": "http://localhost:3000",
    "policy_record_name": "tyk_policies",
    "allow_explicit_policy_id": true
  },
  "hash_keys": true,
  "max_idle_connections_per_host": 500
}
' > /tmp/tyk.conf

sudo mv /tmp/tyk.conf /opt/tyk-gateway/tyk.conf

sudo systemctl restart tyk-gateway


#Enable start on boot
#====================
sudo systemctl enable redis
sudo systemctl enable mongod
sudo systemctl enable tyk-dashboard
sudo systemctl enable tyk-pump
sudo systemctl enable tyk-gateway

#Open firewall ports
#===================
sudo firewall-cmd --permanent --zone=public --add-port=3000/tcp
sudo firewall-cmd --permanent --zone=public --add-port=8080/tcp
sudo systemctl restart firewalld


#Check systen logging is operational
#===================================
journalctl --no-pager -n 5 -t tyk
journalctl --no-pager -n 5 -t tyk-analytics
journalctl --no-pager -n 5 -t tyk-pump

exit


#----------------------------------------------------------------------------------------------------------------------

#Manual config
#=============

Add the Tyk license by browsing to the Tyk Dashboard http://<Tyk Server IP>:3000
Add the license in the lower box


Enter the following command lines to configure the Tyk Dashboard "bootstrap" user and display their credentials
sudo systemctl restart redis
sudo systemctl restart mongod
sudo systemctl restart tyk-dashboard
sudo systemctl restart tyk-pump
sudo systemctl restart tyk-gateway
curl localhost:3000
/opt/tyk-dashboard/install/bootstrap.sh localhost


Browse to the Tyk Dashboard as before
Login to the Tyk Dasboard using the somewhat cryptic default login credentials generated above

Add a more memorable User -
    In the left-hand panel under the "System Management" heading, click on "Users" (The section headings fold away if clicked)
    In the right-hand panel headed "Users and Access", click on "Add User" in the top right hand corner
    Fill in First Name, Last Name, Email Address and Password.  Click on "Account is admin"
    Click on "Save" in the top right hand corner
    In the top of the window at the Right-hand end of the main Menu bar click on the current User and then click on logout

Login again to the Tyk Dashboard as the newly created memorable User, be sure to use the email address.


Config and test a Tyk Gateway API
=================================
Via the Tyk Dashboard

System Management -> APIs
  Press "Add New API" button
    API is active -> tick
    API Name -> api0
    Listen Path -> /api0    # note no trailing slash
    Strip the listen path -> tick
    Target URL -> http://httpbin.org/
    Disable rate limiting -> tick
    Disable quotas -> tick
    Authentication mode -> Open (Keyless)

    Press "Save" button


In a browser goto <Tyk Server IP>:8080/api0
The contents from the httpbin site will be displayed.

The Tyk Online documentation at https://tyk.io/docs/ is a good place to continue your evaluation of Tyk


