#!/bin/bash

image_commit=""
blueprint_name=""
repo_server_ip=$(ip a show dev $(ip route | grep default | awk '{print $5}') | grep "inet " | awk '{print $2}' | awk -F / '{print $1}')
repo_server_port="8080"
kickstart_file=""

############################################################
# Help                                                     #
############################################################
Help()
{
   # Display Help
   echo "This Script creates a container with the ostree repo from an edge-commit image"
   echo
   echo "Syntax: $0 [-c <image ID>|-h <IP>|-p <port>|-k <KS file>|-u]]"
   echo ""
   echo "options:"
   echo "c     Image ID to be published (required)."
   echo "h     Repo server IP (default=$repo_server_ip)."
   echo "p     Repo server port (default=$repo_server_port)."
   echo "k     Kickstart file. If not defined kickstart.ks is autogenerated."
   echo
   echo "Example: $0 -c 125c1433-2371-4ae9-bda3-91efdbb35b92 -h 192.168.122.129 -p 8081 -k kickstart.v1.ks"
   echo ""
}



############################################################
############################################################
# Main program                                             #
############################################################
############################################################



############################################################
# Process the input options. Add options as needed.        #
############################################################
# Get the options
while getopts ":c:h:p:k:" option; do
   case $option in
      c)
         image_commit=$OPTARG;;
      h)
         repo_server_ip=$OPTARG;;
      p)
         repo_server_port=$OPTARG;;
      k)
         kickstart_file=$OPTARG;;
     \?) # Invalid option
         echo "Error: Invalid option"
         echo ""
         Help
         exit -1;;
   esac
done

if [ -z "$image_commit" ]
then
        echo ""
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo "You must define the Commit ID with option -c"
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo ""
        echo ""
        Help
        exit -1

fi

if [ -z "$kickstart_file" ]
then

cat <<EOFIN > kickstart.ks
lang en_US.UTF-8
keyboard us
timezone Etc/UTC --isUtc
text
zerombr
clearpart --all --initlabel
autopart
reboot
user --name=core --group=wheel

ostreesetup --nogpg --osname=rhel --remote=edge --url=http://${repo_server_ip}:${repo_server_port}/repo/ --ref=rhel/8/x86_64/edge

%post
cat << EOF > /etc/greenboot/check/required.d/check-dns.sh
#!/bin/bash

DNS_SERVER=$(grep nameserver /etc/resolv.conf | cut -f2 -d" ")
COUNT=0

# check DNS server is available
ping -c1 $DNS_SERVER
while [ $? != '0' ] && [ $COUNT -lt 10 ]; do
((COUNT++))
echo "Checking for DNS: Attempt $COUNT ."
sleep 10
ping -c 1 $DNS_SERVER
done
EOF
%end

EOFIN

kickstart_file="kickstart.ks"
fi


blueprint_name=$(composer-cli compose status | grep $image_commit | awk '{print $8}')



cat <<EOF > nginx.conf
events {
}
http {
    server{
        listen 8080;
        root /usr/share/nginx/html;
        location / {
            autoindex on;
            }
        }
     }
pid /run/nginx.pid;
daemon off;
EOF


cat <<EOF > Dockerfile
FROM registry.access.redhat.com/ubi8/ubi
RUN yum -y install nginx && yum clean all
ARG kickstart
ARG commit
ADD \$kickstart /usr/share/nginx/html/
ADD \$commit /usr/share/nginx/html/
ADD nginx.conf /etc/
EXPOSE 8080
CMD ["/usr/sbin/nginx", "-c", "/etc/nginx.conf"][root@image-builder tests]
EOF

############################################################
# Download the image.       
############################################################


echo ""
echo "Downloading image $image_commit..."



mkdir -p images
cd images
composer-cli compose image $image_commit
cd ..





############################################################
# Publish the image.       
############################################################


# Stop previous container

echo ""
echo "Stopping previous .."
echo ""


podman stop $(podman ps | grep 0.0.0.0:$repo_server_port | awk '{print $1}') 2>/dev/null


# Start repo container


echo ""
echo "Building and running the container serving the image..."


podman build -t ${blueprint_name}-repo:latest --build-arg kickstart=${kickstart_file} --build-arg commit=images/${image_commit}-commit.tar .
podman tag ${blueprint_name}-repo:latest ${blueprint_name}-repo:$image_commit
podman run --name ${blueprint_name}-repo-$image_commit -d -p  $repo_server_port:8080 ${blueprint_name}-repo:latest




echo ""
echo ""
echo "Install using standard RHEL ISO including this kernel argument:"
echo ""
echo "************************************************************************"
echo ""
echo "<kernel args> inst.ks=http://$repo_server_ip:$repo_server_port/${kickstart_file}"
echo ""
echo "************************************************************************"
echo ""
echo ""
echo "...or create a bootable auto-install ISO with 3-create-ISO.sh"
echo ""
echo ""









