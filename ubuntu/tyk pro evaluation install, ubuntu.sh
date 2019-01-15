
# Basic install script/instructions for Tyk Pro (Gateway, Dashboard and Pump) for Ubuntu 18 and Mint 19

# Version 1.2.4
# Peter Harris

# NOTE: There are some very simple manual steps at the bottom of this file

# The Dashboard requires a valid "On Premise" licence to be issued by Tyk.  Please visit https://tyk.io/ and push the "GET STARTED" button

# This script/instructions are intended to be used by a person with operational experience of Linux.
# All of the required components are installed onto a single platform and intended solely for simple evaluation purposes.
# There is very limited security provided and must NOT be used for production environments.


#Update platform
#===============
sudo apt update
sudo apt upgrade -y

sudo apt install curl net-tools python -y


#Redis
#=====
sudo apt install -y redis-server
sudo service redis-server start


#Mongo, https://docs.mongodb.com/manual/tutorial/install-mongodb-on-ubuntu/
#=====
sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 9DA31620334BD75D9DCB49F368818C72E52529D4
echo "deb [ arch=amd64 ] https://repo.mongodb.org/apt/ubuntu bionic/mongodb-org/4.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-4.0.list
sudo apt update
sudo apt install -y mongodb-org

sudo service mongod start


#HTTPS Transport
================
sudo apt install -y apt-transport-https


#Dashboard
#=========
curl -s -S -L https://packagecloud.io/tyk/tyk-dashboard/gpgkey | sudo apt-key add -
echo "deb https://packagecloud.io/tyk/tyk-dashboard/ubuntu/ trusty main" | 
sudo tee /etc/apt/sources.list.d/tyk_tyk-dashboard.list
echo "deb-src https://packagecloud.io/tyk/tyk-dashboard/ubuntu/ trusty main" | sudo tee -a /etc/apt/sources.list.d/tyk_tyk-dashboard.list
sudo apt update
sudo apt install -y tyk-dashboard

sudo /opt/tyk-dashboard/install/setup.sh --listenport=3000 –redishost=localhost --redisport=6379 –mongo=mongodb://localhost/tyk_analytics --tyk_api_hostname=localhost --tyk_node_hostname=http://localhost --tyk_node_port=8080 --portal_root=/portal --domain=localhost

sudo service tyk-dashboard start


#Pump
#====
curl -s -S -L https://packagecloud.io/tyk/tyk-pump/gpgkey | sudo apt-key add -

echo "deb https://packagecloud.io/tyk/tyk-pump/ubuntu/ trusty main" | sudo tee /etc/apt/sources.list.d/tyk_tyk-pump.list
echo "deb-src https://packagecloud.io/tyk/tyk-pump/ubuntu/ trusty main" | sudo tee -a /etc/apt/sources.list.d/tyk_tyk-pump.list
sudo apt-get update
sudo apt-get install -y tyk-pump

sudo /opt/tyk-pump/install/setup.sh --redishost=localhost --redisport=6379 --mongo=mongodb://localhost/tyk_analytics

sudo service tyk-pump start


#Gateway
#=======
curl -s -S -L https://packagecloud.io/tyk/tyk-gateway/gpgkey | sudo apt-key add -
echo "deb https://packagecloud.io/tyk/tyk-gateway/ubuntu/ trusty main" | sudo tee /etc/apt/sources.list.d/tyk_tyk-gateway.list
echo "deb-src https://packagecloud.io/tyk/tyk-gateway/ubuntu/ trusty main" | sudo tee -a /etc/apt/sources.list.d/tyk_tyk-gateway.list
sudo apt update
sudo apt install -y tyk-gateway

sudo service tyk-gateway start


# The following will create a basic gateway config file

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

sudo service tyk-gateway restart


#Enable start on boot
#====================
sudo systemctl enable redis-server
sudo systemctl enable mongod
sudo systemctl enable tyk-dashboard
sudo systemctl enable tyk-pump
sudo systemctl enable tyk-gateway


#Check systen logging is operational
#===================================
journalctl --no-pager -n 5 -t tyk
journalctl --no-pager -n 5 -t tyk-analytics
journalctl --no-pager -n 5 -t tyk-pump

exit



#Manual config
#=============

Add the Tyk license by browsing to the Tyk Dashboard http://localhost:3000
Add the license in the lower box


Enter the following command lines to configure the Tyk Dashboard "bootstrap" user and display their credentials
sudo service redis-server restart
sudo service mongod restart
sudo service tyk-dashboard restart
sudo service tyk-pump restart
sudo service tyk-gateway restart
sudo /opt/tyk-dashboard/install/bootstrap.sh localhost


Browse to the Tyk Dashboard as before
Login to teh Tyk Dasboard using the somewhat cryptic default login credentials generated above

Add a more memorable User -
    In the left-hand panel under the "System Management" heading, click on "Users" (The section headings fold away if clicked)
    In the right-hand panel headed "Users and Access", click on "Add User" in the top right hand corner
    Fill in First Name, Last Name, Email Address and Password.  Click on "Account is admin"
    Click on "Save" in the top right hand corner
    In the top of the window at the Right-hand end of the main Menu bar click on the current User and then click on logout

Login as the newly created memorable User, be sure to use the email address.


Config and test a Tyk Gateway API
=================================
Login at localhost:3000 using the memorable admin credentials as before

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


In a browser goto "localhost:8080/api0"
The contents from the httpbin site will be displayed.

The Tyk Online documentation at https://tyk.io/docs/ is a good place to continue your evaluation of Tyk


