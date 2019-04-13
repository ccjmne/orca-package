#!/bin/sh
set -e

export __OK='   [\033[0;32m ok \033[0m]'
export __KO='[\033[0;31m error \033[0m]'
export __NF=' [\033[1;34m info \033[0m]'

# Requires the ec2-orca-install IAM role to:
# - list the current instance's tags    from ec2
# - get client-specific configuration   from s3
# - access the Orca docker image        from ecr

printf "===============================================================================\n\
${__NF} Setting up Orca -- this will take a minute\
\n===============================================================================\n"

# Install message of the day w/ update instructions
cp ./motd /etc

# aws cli
apt-get update
apt-get install -y python-pip
pip install --upgrade awscli

# configure the CLIENT_ID environment variable using the "clientid" ec2 instance tag
aws ec2 describe-tags --filters "Name=resource-id,Values=`curl -s http://169.254.169.254/latest/meta-data/instance-id`" --region eu-west-1 > .ec2-instance-tags
apt-get install -y jq
export CLIENT_ID=`jq --raw-output ".Tags[] | select(.Key==\"clientid\") | .Value" .ec2-instance-tags`
echo "export CLIENT_ID=${CLIENT_ID}" > ~/.bash_profile
printf "===============================================================================\n\
${__NF} Setting up Orca for client: \033[1;34m${CLIENT_ID:?}\033[0m\
\n===============================================================================\n"

# configuration files
aws s3 cp s3://orca-clients/${CLIENT_ID}.conf orca.conf
sed -i *.conf -e "s/\${clientid}/${CLIENT_ID:?}/g"
printf "===============================================================================\n\
${__OK} Configuration files loaded\
\n===============================================================================\n"

# nginx
apt-get install -y nginx
cp nginx.conf /etc/nginx/conf.d/default.conf
printf "===============================================================================\n\
${__OK} NGINX installation completed\
\n===============================================================================\n"

# let's encrypt's certificates w/ certbot
# see https://certbot.eff.org/#ubuntuxenial-nginx
apt-get install -y software-properties-common
add-apt-repository -y ppa:certbot/certbot
apt-get update
apt-get install -y python-certbot-nginx
certbot --nginx --config certbot.conf --non-interactive
service nginx restart
printf "===============================================================================\n\
${__OK} Let's Encrypt certificates installed\
\n===============================================================================\n"

# docker
# see https://store.docker.com/editions/community/docker-ce-server-ubuntu
apt-get -y install apt-transport-https ca-certificates curl
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository \
	"deb [arch=amd64] https://download.docker.com/linux/ubuntu \
	$(lsb_release -cs) \
	stable"
apt-get update
apt-get -y install docker-ce

# set up auto-restart on crash for the docker daemon
systemctl enable docker.service
mkdir -p /etc/systemd/system/docker.service.d
cat > /etc/systemd/system/docker.service.d/override.conf <<EOF
[Service]
Restart=always
RestartSec=3
EOF

systemctl daemon-reload
printf "===============================================================================\n\
${__OK} Docker installation completed\
\n===============================================================================\n"

# orca
# TODO: I'm sure there's a more straightforward way to do that,
# but then again maybe CLIENT_ID wouldn't be set if it weren't within a new bash session.
cat ./update.sh | bash
