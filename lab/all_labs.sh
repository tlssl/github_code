Clear
menu_option_one() {

#!/bin/bash

AWS_ACCESS_KEY_ID=$(security find-generic-password -a $USER -s AWS_ACCESS_KEY_ID -w aws.secrets)
AWS_SECRET_ACCESS_KEY=$(security find-generic-password -a $USER -s AWS_SECRET_ACCESS_KEY -w aws.secrets)
AWS_DEFAULT_REGION=$(security find-generic-password -a $USER -s AWS_DEFAULT_REGION -w aws.secrets)

# Run aws configure with the provided values
aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID"
aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY"
aws configure set default.region "$AWS_DEFAULT_REGION"

# Set AWS region
AWS_REGION=$(security find-generic-password -a $USER -s AWS_DEFAULT_REGION -w aws.secrets)

# Set instance configurations
INSTANCE_TYPE="t2.medium"
KEY_NAME="mrudloff-keypair"
SECURITY_GROUP_ID="sg-09dae9711b0b7e305"
VPC_ID="vpc-3409ac5f"
SUBNET_ID="subnet-2d915d46"

# Prompt the user to choose the AMI
clear
echo "Which AMI would you like to deploy?"
echo "1. Ubuntu 24.04"
echo "2. Ubuntu 22.04"
echo "3. Ubuntu 18.04"
read -p "Enter your choice (1,2  or 3): " choice

# Set the AMI_ID based on the user's choice
case $choice in 
  1)
    AMI_ID="ami-09040d770ffe2224f"
    echo "Selected AMI: Ubuntu 24.04"
    ;;
  2)
    AMI_ID="ami-0b8b44ec9a8f90422"
    echo "Selected AMI: Ubuntu 22.04"
    ;;
  3)
    AMI_ID="ami-0e4c27be5484b93d6"
    echo "Selected AMI: Ubuntu 18.04"
    ;;
  *)
    echo "Invalid choice. Defaulting to Ubuntu 22.04."
    AMI_ID="ami-0e4c27be5484b93d6"
    ;;
esac

# Ansible Specific Path Variables
ansible_automation_path="/Users/michaelrudloff/Dropbox/vscode/ansible_automation"
ansible_certs_path="/Users/michaelrudloff/Dropbox/vscode/ansible_automation/certs"
ansible_tlmfiles_path="/Users/michaelrudloff/Dropbox/vscode/ansible_automation/tlmfiles"
ansible_templates_path="/Users/michaelrudloff/Dropbox/vscode/ansible_automation/templates"
ansible_hosts_path="/Users/michaelrudloff/Dropbox/vscode/ansible_automation/upload_to_ansible_host"
ansible_hosts_local_path="/Users/michaelrudloff/Dropbox/vscode/ansible_automation"
ansible_key_file="/Users/michaelrudloff/Dropbox/vscode/key"

# Create mrudloff-ansible-server instance
ANSIBLE_SERVER_INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SECURITY_GROUP_ID" \
    --subnet-id "$SUBNET_ID" \
    --associate-public-ip-address \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=mrudloff-ansible-server}]' \
    --query 'Instances[0].InstanceId' \
    --output text \
    --region "$AWS_REGION")
echo "Ansible Environment is being created. Please wait..."
echo 
echo "The environment will consist of the following:"
echo "1. Ansible Server"
echo "2. Ansible Client"
echo
echo "The Ansible Client will have Apache with self-signed TLS installed and configured"
echo
echo "mrudloff-ansible-server instance ID: $ANSIBLE_SERVER_INSTANCE_ID"

# Create mrudloff-puppet-client instance
ANSIBLE_CLIENT_INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SECURITY_GROUP_ID" \
    --subnet-id "$SUBNET_ID" \
    --associate-public-ip-address \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=mrudloff-ansible-client}]' \
    --query 'Instances[0].InstanceId' \
    --output text \
    --region "$AWS_REGION")
echo "mrudloff-ansible-client instance ID: $ANSIBLE_CLIENT_INSTANCE_ID"

# Get Public DNS name and Private IP address of instances
ANSIBLE_SERVER_PUBLIC_DNS=$(aws ec2 describe-instances \
    --instance-ids "$ANSIBLE_SERVER_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicDnsName' \
    --output text \
    --region "$AWS_REGION")
ANSIBLE_SERVER_PRIVATE_IP=$(aws ec2 describe-instances \
    --instance-ids "$ANSIBLE_SERVER_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' \
    --output text \
    --region "$AWS_REGION")

ANSIBLE_CLIENT_PUBLIC_DNS=$(aws ec2 describe-instances \
    --instance-ids "$ANSIBLE_CLIENT_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicDnsName' \
    --output text \
    --region "$AWS_REGION")
ANSIBLE_CLIENT_PRIVATE_IP=$(aws ec2 describe-instances \
    --instance-ids "$ANSIBLE_CLIENT_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' \
    --output text \
    --region "$AWS_REGION")

echo
echo "The following ec2 instances have been created:"
echo
echo "Host: mrudloff-ansible-server"
echo "Public DNS: $ANSIBLE_SERVER_PUBLIC_DNS"
echo "Private IP: $ANSIBLE_SERVER_PRIVATE_IP"
echo
echo "Host: mrudloff-ansible-client"
echo "Public DNS: $ANSIBLE_CLIENT_PUBLIC_DNS"
echo "Private IP: $ANSIBLE_CLIENT_PRIVATE_IP"

# Get instance IDs of the newly created Puppet instances
ANSIBLE_SERVER_INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=mrudloff-ansible-server" "Name=instance-state-name,Values=running" --query "Reservations[*].Instances[*].[InstanceId]" --output text --region "$AWS_REGION")
ANSIBLE_CLIENT_INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=mrudloff-ansible-client" "Name=instance-state-name,Values=running" --query "Reservations[*].Instances[*].[InstanceId]" --output text --region "$AWS_REGION")

# Declare array of Ansible instance IDs
INSTANCE_IDS=("$ANSIBLE_SERVER_INSTANCE_ID" "$ANSIBLE_CLIENT_INSTANCE_ID")

# Wait for 3 minutes to give the Ansible instances some time to initialize
echo
duration=180
while [ $duration -gt 0 ]; do
    printf "\rWaiting %02d seconds for Ansible instances to initialize before checking again..." $duration
    sleep 1
    ((duration--))
done

# Wait for each Ansible instances to pass status checks
for INSTANCE_ID in "${INSTANCE_IDS[@]}"; do
    INSTANCE_STATUS=""
    while [ -z "$INSTANCE_STATUS" ] || [ "$INSTANCE_STATUS" != "ok" ]; do
        echo 
        echo "Checking status of ec2 instances"
        INSTANCE_STATUS=$(aws ec2 describe-instance-status --instance-ids $INSTANCE_ID --query 'InstanceStatuses[0].InstanceStatus.Status' --output text)
        echo "Instance status: $INSTANCE_STATUS"
        INSTANCE_STATUS=$(aws ec2 describe-instance-status --instance-ids $INSTANCE_ID --query 'InstanceStatuses[0].InstanceStatus.Status' --output text)
        if [ -z "$INSTANCE_STATUS" ] || [ "$INSTANCE_STATUS" != "ok" ]; then
            echo
            duration2=15
            while [ $duration2 -gt 0 ]; do
            printf "\rInstances are not ready yet. Waiting for %02d seconds before checking again." $duration2
            sleep 1
            ((duration2--))
            done
        fi
    done
done
echo
echo "All instances have passed status checks and are ready to use."

# Ensure SSH Keys are being accepted / skipped
export ANSIBLE_HOST_KEY_CHECKING=False

# Create Ansible Configuration and Playbook
echo 
echo "Creating Ansible Configuration and Playbook"

# Define the instance names before attempting to retrieve their IPs
INSTANCE_NAMES=("mrudloff-ansible-server" "mrudloff-ansible-client")

# Declare global variables for public DNS names to ensure they're available for all parts of the script
ANSIBLE_SERVER_PUBLIC_DNS=""
ANSIBLE_CLIENT_PUBLIC_DNS=""

# Retrieve the public DNS names of the running instances
for INSTANCE_NAME in "${INSTANCE_NAMES[@]}"; do
    INSTANCE_DETAILS=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=running" --query 'Reservations[*].Instances[*].[PublicDnsName]' --output text)
    if [ "$INSTANCE_NAME" == "mrudloff-ansible-server" ]; then
        ANSIBLE_SERVER_PUBLIC_DNS=$INSTANCE_DETAILS
    elif [ "$INSTANCE_NAME" == "mrudloff-ansible-client" ]; then
        ANSIBLE_CLIENT_PUBLIC_DNS=$INSTANCE_DETAILS  
    fi
done



# Configure Ansible hosts
configure_ansible_hosts() {
    echo "Configuring Ansible hosts file..."

    # Check and delete existing hosts file
    if [ -f "$ansible_hosts_local_path/ansiblehosts" ]; then
        rm $ansible_hosts_local_path/ansiblehosts
    fi

    # Create hosts file
    cat << EOF > $ansible_hosts_local_path/ansiblehosts
[ansibleserver]
mrudloff-ansible-server ansible_host=$ANSIBLE_SERVER_PUBLIC_DNS ansible_user=ubuntu ansible_ssh_private_key_file=/Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem

[ansibleclient]
mrudloff-ansible-client ansible_host=$ANSIBLE_CLIENT_PUBLIC_DNS ansible_user=ubuntu ansible_ssh_private_key_file=/Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem
EOF
}

# Prompt the user for the domain name
# read -p "Domain used for the certificate used for the Ansible client? " ansible_domain_name


# Configure Apache templates
configure_ansible_apache_templates() {
    echo "Configuring Apache templates..."

    # Create templates directory if it doesn't exist
    mkdir -p $ansible_templates_path

    # Check and delete existing apache-ssl.conf.j2 file
    if [ -f "$ansible_templates_path/ansible-apache-ssl.conf.j2" ]; then
        rm $ansible_templates_path/ansible-apache-ssl.conf.j2
    fi

    # Create Ansible Client apache-ssl.conf.j2 file
    cat << EOF > $ansible_templates_path/ansible-apache-ssl.conf.j2
<VirtualHost *:443>
    #ServerName $ansible_domain_name
    ServerName $ANSIBLE_CLIENT_PUBLIC_DNS
    DocumentRoot /var/www/html
    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/ansible-apache-selfsigned.crt
    SSLCertificateKeyFile /etc/ssl/private/ansible-apache-selfsigned.key
</VirtualHost>
EOF

    # Check and delete existing Ansible Client apache-redirect.conf.j2 file
    if [ -f "$ansible_templates_path/ansible-apache-redirect.conf.j2" ]; then
        rm $ansible_templates_path/ansible-apache-redirect.conf.j2
    fi

    # Create Ansible Client apache-redirect.conf.j2 file
    cat << EOF > $ansible_templates_path/ansible-apache-redirect.conf.j2
<VirtualHost *:80>
    #ServerName $ansible_domain_name
    ServerName $ANSIBLE_CLIENT_PUBLIC_DNS
    Redirect permanent / https://$ANSIBLE_CLIENT_PUBLIC_DNS/
</VirtualHost>
EOF
}

# Configure Ansible hosts
configure_remote_ansible_hosts() {
    echo "Configuring remote Ansible hosts file..."

    # Check and delete existing hosts file
    if [ -f "$ansible_hosts_path/hosts" ]; then
        rm $ansible_hosts_path/hosts
    fi

    # Create hosts file
    cat << EOF > $ansible_hosts_path/hosts

[hosts]
mrudloff-ansible-client ansible_host=$ANSIBLE_CLIENT_PUBLIC_DNS ansible_user=ubuntu ansible_ssh_private_key_file=/etc/ansible/aws_keypair.pem
EOF
}

# Create Puppet Client self-signed certificates
create_selfsigned_certificates() {
    echo "Creating self-signed certificates..."

    # Create certs directory if it doesn't exist
    mkdir -p $ansible_certs_path

    # Create self-signed certificates for Ansible client apache server
    openssl req -x509 -newkey rsa:4096 -keyout $ansible_certs_path/ansible-apache-selfsigned.key -out $ansible_certs_path/ansible-apache-selfsigned.crt -days 365 -nodes -subj "/C=GB/ST=Cambs/L=Ely/O=Digicert/OU=Product/CN=AnsibleClient/emailAddress=michael.rudloff@digicert.com" 
}

# Configure Ansible playbook
configure_ansible_playbook() {
    echo "Configuring Ansible playbook..."

    # Check and delete existing playbook file
    if [ -f "$ansible_hosts_local_path/ansible_server.yml" ]; then
        rm $ansible_hosts_local_path/ansible_server.yml
    fi

    # Create playbook file
    cat << EOF > $ansible_hosts_local_path/ansible_server.yml
---
- hosts: all
  become: yes
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: /Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem
  tasks:
    - name: Update apt cache
      apt:
        update_cache: yes

    - name: Install build-essential package
      apt:
        name: build-essential
        state: present
    - name: Upgrade packages
      apt:
        upgrade: yes  

- hosts: ansibleclient
  become: yes
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: /Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem
    #apache_server_name: $ansible_domain_name
    apache_server_name: $ANSIBLE_CLIENT_PUBLIC_DNS
    apache_document_root: /var/www/html  
  tasks:
    - name: Install Apache
      apt:
        name: apache2
        state: latest
    - name: Create /etc/ssl/private/ directory
      file:
        path: /etc/ssl/private/
        state: directory
        owner: root
        group: root
        mode: '0700'

    - name: Create /etc/ssl/certs/ directory
      file:
        path: /etc/ssl/certs/
        state: directory
        owner: root
        group: root
        mode: '0755'

    - name: Copy files to remote server
      copy:
        src: "$ansible_certs_path/{{ item }}"
        dest: "/etc/ssl/private/{{ item }}"
      with_items:
        - ansible-apache-selfsigned.key

    - name: Copy files to remote server
      copy:
        src: "$ansible_certs_path/{{ item }}"
        dest: "/etc/ssl/certs/{{ item }}"
      with_items:
        - ansible-apache-selfsigned.crt

    - name: Enable Apache2 modules
      apache2_module:
        name: "{{ item }}"
        state: present
      loop:
        - ssl
        - rewrite
   
    - name: Configure Apache2 for HTTPS
      template:
        src: $ansible_templates_path/ansible-apache-ssl.conf.j2
        dest: /etc/apache2/sites-available/default-ssl.conf
      notify: Restart Apache2

    - name: Enable Apache2 default SSL virtual host
      command: a2ensite default-ssl

    - name: Configure Apache2 to redirect HTTP to HTTPS
      template:
        src: $ansible_templates_path/ansible-apache-redirect.conf.j2
        dest: /etc/apache2/sites-available/000-default.conf
      notify: Restart Apache2

  handlers:
    - name: Restart Apache2
      service:
        name: apache2
        state: restarted

- hosts: ansibleserver
  become: yes
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: /Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem
  tasks:
    - name: Add Ansible Repository
      apt_repository:
        repo: ppa:ansible/ansible
        state: present

    - name: Update apt cache
      apt:
        update_cache: yes
    
    - name: Install Ansible package
      apt:
        name: ansible
        state: present    
       
    - name: Copy tlm files to remote server
      copy:
        src: "$ansible_tlmfiles_path/{{ item }}"
        dest: "/etc/ansible/{{ item }}"
      with_items:
        - DigiCertTLMAgentGPOInstaller.tar.gz
    

    - name: Copy Ansible files to remote server
      copy:
        src: "$ansible_hosts_path/{{ item }}"
        dest: "/etc/ansible/{{ item }}"
      with_items:
        - hosts
        - main.yml
        - var.yml

    - name: Copy SSH Key to remote server
      copy:
        src: "$ansible_key_file/{{ item }}"
        dest: "/etc/ansible/{{ item }}"
      with_items:
        - aws_keypair.pem

    - name: Add host_key_checking setting to ansible.cfg
      lineinfile:
        path: /etc/ansible/ansible.cfg
        line: "[defaults]\nhost_key_checking = False"
        insertafter: EOF
        create: yes

    - name: Set permissions for AWS private key file
      file:
        path: /etc/ansible/aws_keypair.pem
        mode: 0600

    - name: Run remote Ansible Playbook to deploy TLM Agent
      command: /usr/bin/ansible-playbook -i /etc/ansible/hosts /etc/ansible/main.yml    

EOF
}

# Call the functions
configure_ansible_hosts
configure_remote_ansible_hosts
configure_ansible_playbook
create_selfsigned_certificates
configure_ansible_apache_templates

# Running Playbook
export ANSIBLE_HOST_KEY_CHECKING=False
ansible-playbook -i $ansible_hosts_local_path/ansiblehosts $ansible_hosts_local_path/ansible_server.yml

  exit
}
menu_option_two() {

#!/bin/bash

AWS_ACCESS_KEY_ID=$(security find-generic-password -a $USER -s AWS_ACCESS_KEY_ID -w aws.secrets)
AWS_SECRET_ACCESS_KEY=$(security find-generic-password -a $USER -s AWS_SECRET_ACCESS_KEY -w aws.secrets)
AWS_DEFAULT_REGION=$(security find-generic-password -a $USER -s AWS_DEFAULT_REGION -w aws.secrets)

# Run aws configure with the provided values
aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID"
aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY"
aws configure set default.region "$AWS_DEFAULT_REGION"

# Set AWS region
AWS_REGION=$(security find-generic-password -a $USER -s AWS_DEFAULT_REGION -w aws.secrets)

# Set instance configurations
INSTANCE_TYPE="t2.medium"
KEY_NAME="mrudloff-keypair"
SECURITY_GROUP_ID="sg-09dae9711b0b7e305"
VPC_ID="vpc-3409ac5f"
SUBNET_ID="subnet-2d915d46"

# Prompt the user to choose the AMI
clear
echo "Which AMI would you like to deploy?"
echo "1. Ubuntu 24.04"
echo "2. Ubuntu 22.04"
echo "3. Ubuntu 18.04"
read -p "Enter your choice (1,2  or 3): " choice

# Set the AMI_ID based on the user's choice
case $choice in 
  1)
    AMI_ID="ami-09040d770ffe2224f"
    echo "Selected AMI: Ubuntu 24.04"
    ;;
  2)
    AMI_ID="ami-0b8b44ec9a8f90422"
    echo "Selected AMI: Ubuntu 22.04"
    ;;
  3)
    AMI_ID="ami-0e4c27be5484b93d6"
    echo "Selected AMI: Ubuntu 18.04"
    ;;
  *)
    echo "Invalid choice. Defaulting to Ubuntu 22.04."
    AMI_ID="ami-0e4c27be5484b93d6"
    ;;
esac

# Puppet Specific Path Variables
puppet_automation_path="/Users/michaelrudloff/Dropbox/vscode/puppet_automation"
puppet_certs_path="/Users/michaelrudloff/Dropbox/vscode/puppet_automation/certs"
puppet_tlmfiles_path="/Users/michaelrudloff/Dropbox/vscode/puppet_automation/tlmfiles"
puppet_templates_path="/Users/michaelrudloff/Dropbox/vscode/puppet_automation/templates"
puppet_hosts_path="/Users/michaelrudloff/Dropbox/vscode/puppet_automation/upload_to_ansible_host"
puppet_hosts_local_path="/Users/michaelrudloff/Dropbox/vscode/puppet_automation"
puppet_key_file="/Users/michaelrudloff/Dropbox/vscode/key"

# Create the mrudloff-puppet-server ec2 instances
PUPPET_SERVER_INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SECURITY_GROUP_ID" \
    --subnet-id "$SUBNET_ID" \
    --associate-public-ip-address \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=mrudloff-puppet-server}]' \
    --query 'Instances[0].InstanceId' \
    --output text \
    --region "$AWS_REGION")

echo "Puppet Environment is being created. Please wait..."
echo 
echo "The environment will consist of the following:"
echo "1. Puppet Server"
echo "2. Puppet Client"
echo
echo "The Puppet Client will have Apache with self-signed TLS installed and configured"
echo
echo "mrudloff-puppet-server instance ID: $PUPPET_SERVER_INSTANCE_ID"

# Create mrudloff-puppet-client instance
PUPPET_CLIENT_INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SECURITY_GROUP_ID" \
    --subnet-id "$SUBNET_ID" \
    --associate-public-ip-address \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=mrudloff-puppet-client}]' \
    --query 'Instances[0].InstanceId' \
    --output text \
    --region "$AWS_REGION")
echo "mrudloff-puppet-client instance ID: $PUPPET_CLIENT_INSTANCE_ID"
echo 

# Get the public DNS and private IP addresses of the Puppet ec2 instances
PUPPET_SERVER_PUBLIC_DNS=$(aws ec2 describe-instances \
    --instance-ids "$PUPPET_SERVER_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicDnsName' \
    --output text \
    --region "$AWS_REGION")
PUPPET_SERVER_PRIVATE_IP=$(aws ec2 describe-instances \
    --instance-ids "$PUPPET_SERVER_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' \
    --output text \
    --region "$AWS_REGION")

PUPPET_CLIENT_PUBLIC_DNS=$(aws ec2 describe-instances \
    --instance-ids "$PUPPET_CLIENT_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicDnsName' \
    --output text \
    --region "$AWS_REGION")
PUPPET_CLIENT_PRIVATE_IP=$(aws ec2 describe-instances \
    --instance-ids "$PUPPET_CLIENT_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' \
    --output text \
    --region "$AWS_REGION")
echo
echo "The following ec2 instances have been created:"
echo
echo "Host: mrudloff-puppet-server"
echo "Public DNS: $PUPPET_SERVER_PUBLIC_DNS"
echo "Private IP: $PUPPET_SERVER_PRIVATE_IP"
echo
echo "Host: mrudloff-puppet-client"
echo "Public DNS: $PUPPET_CLIENT_PUBLIC_DNS"
echo "Private IP: $PUPPET_CLIENT_PRIVATE_IP"

# Get instance IDs of the newly created Puppet instances
PUPPET_SERVER_INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=mrudloff-puppet-server" "Name=instance-state-name,Values=running" --query "Reservations[*].Instances[*].[InstanceId]" --output text --region "$AWS_REGION")
PUPPET_CLIENT_INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=mrudloff-puppet-client" "Name=instance-state-name,Values=running" --query "Reservations[*].Instances[*].[InstanceId]" --output text --region "$AWS_REGION")

# Declare array of Puppet instance IDs
INSTANCE_IDS=("$PUPPET_SERVER_INSTANCE_ID" "$PUPPET_CLIENT_INSTANCE_ID")

# Wait for 3 minutes to give the Puppet instances some time to initialize
echo
duration=180
while [ $duration -gt 0 ]; do
    printf "\rWaiting %02d seconds for Puppet instances to initialize before checking again..." $duration
    sleep 1
    ((duration--))
done

# Wait for each Puppet instance to pass status checks
for INSTANCE_ID in "${INSTANCE_IDS[@]}"; do
    INSTANCE_STATUS=""
    while [ -z "$INSTANCE_STATUS" ] || [ "$INSTANCE_STATUS" != "ok" ]; do
        echo 
        echo "Checking status of ec2 instances"
        INSTANCE_STATUS=$(aws ec2 describe-instance-status --instance-ids $INSTANCE_ID --query 'InstanceStatuses[0].InstanceStatus.Status' --output text)
        echo "Instance status: $INSTANCE_STATUS"
        INSTANCE_STATUS=$(aws ec2 describe-instance-status --instance-ids $INSTANCE_ID --query 'InstanceStatuses[0].InstanceStatus.Status' --output text)
        if [ -z "$INSTANCE_STATUS" ] || [ "$INSTANCE_STATUS" != "ok" ]; then
            echo
            duration2=15
            while [ $duration2 -gt 0 ]; do
            printf "\rInstances are not ready yet. Waiting for %02d seconds before checking again." $duration2
            sleep 1
            ((duration2--))
            done
        fi
    done
done
echo
echo "All instances have passed status checks and are ready to use."

# Ensure SSH Keys are being accepted / skipped
export PUPPET_HOST_KEY_CHECKING=False

# Create Puppet Configuration and Playbook
echo 
echo "Creating Puppet Configuration and Playbook"

# Define the instance names before attempting to retrieve their IPs
INSTANCE_NAMES=("mrudloff-puppet-server" "mrudloff-puppet-client")

# Declare global variables for public DNS names to ensure they're available for all parts of the script
PUPPET_SERVER_PUBLIC_DNS=""
PUPPET_CLIENT_PUBLIC_DNS=""

# Retrieve the public DNS names of the running instances
for INSTANCE_NAME in "${INSTANCE_NAMES[@]}"; do
    INSTANCE_DETAILS=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=running" --query 'Reservations[*].Instances[*].[PublicDnsName]' --output text)
    if [ "$INSTANCE_NAME" == "mrudloff-puppet-server" ]; then
        PUPPET_SERVER_PUBLIC_DNS=$INSTANCE_DETAILS
    elif [ "$INSTANCE_NAME" == "mrudloff-puppet-client" ]; then
        PUPPET_CLIENT_PUBLIC_DNS=$INSTANCE_DETAILS  
    fi
done

# Configure Puppet hosts
configure_puppet_hosts() {
    echo 
    echo "Configuring Ansible hosts file cppchosts to deploy Puppet using Ansible..."

    # Check and delete existing hosts file
    if [ -f "$puppet_automation_path/puppethosts" ]; then
        rm $puppet_automation_path/puppethosts
    fi

    # Create hosts file
    cat << EOF > $puppet_automation_path/puppethosts
[puppetserver]
mrudloff-puppet-server ansible_host=$PUPPET_SERVER_PUBLIC_DNS ansible_user=ubuntu ansible_ssh_private_key_file=/Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem

[puppetclient]
mrudloff-puppet-client ansible_host=$PUPPET_CLIENT_PUBLIC_DNS ansible_user=ubuntu ansible_ssh_private_key_file=/Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem
EOF
}

# Prompt the user for the domain name
# read -p "Domain used for the certificate used for the Puppet Client? " puppet_domain_name

# Configure Apache templates
configure_apache_templates() {
    echo "Configuring Apache templates..."

    # Create templates directory if it doesn't exist
    mkdir -p $puppet_templates_path

    # Check and delete existing Puppet Client apache-redirect.conf.j2 file
    if [ -f "$puppet_templates_path/puppet-apache-redirect.conf.j2" ]; then
        rm $puppet_templates_path/puppet-apache-redirect.conf.j2
    fi

    # Create Puppet Client apache-redirect.conf.j2 file
    cat << EOF > $puppet_templates_path/puppet-apache-redirect.conf.j2
<VirtualHost *:80>
    ServerName $PUPPET_CLIENT_PUBLIC_DNS
    Redirect permanent / https://$PUPPET_CLIENT_PUBLIC_DNS/
</VirtualHost>
EOF
}

    # Check and delete existing apache-ssl.conf.j2 file
    if [ -f "$puppet_templates_path/puppet-apache-ssl.conf.j2" ]; then
        rm $puppet_templates_path/puppet-apache-ssl.conf.j2
    fi

    # Create Puppet Client apache-ssl.conf.j2 file
    cat << EOF > $puppet_templates_path/puppet-apache-ssl.conf.j2
<VirtualHost *:443>
    ServerName $PUPPET_CLIENT_PUBLIC_DNS
    DocumentRoot /var/www/html
    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/puppet-apache-selfsigned.crt
    SSLCertificateKeyFile /etc/ssl/private/puppet-apache-selfsigned.key
</VirtualHost>
EOF


# Create Puppet Client self-signed certificates
create_selfsigned_certificates() {
    echo "Creating self-signed certificates..."

    # Create certs directory if it doesn't exist
    mkdir -p $puppet_certs_path

    # Create self-signed certificates for puppet client apache server
    openssl req -x509 -newkey rsa:4096 -keyout $puppet_certs_path/puppet-apache-selfsigned.key -out $puppet_certs_path/puppet-apache-selfsigned.crt -days 365 -nodes -subj "/C=GB/ST=Cambs/L=Ely/O=Digicert/OU=Product/CN=PuppetClient/emailAddress=michael.rudloff@digicert.com" 
}

# Configure Puppet playbook
configure_puppet_playbook() {
    echo "Configuring Puppet playbook..."

    # Check and delete existing playbook file
    if [ -f "$puppet_automation_path/puppet_server.yml" ]; then
        rm $puppet_automation_path/puppet_server.yml
    fi

    # Create playbook file
    cat << EOF > $puppet_automation_path/puppet_server.yml
---
- hosts: all
  become: yes
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: /Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem
  tasks:

    - name: Add lines to /etc/hosts
      ansible.builtin.lineinfile:
        path: /etc/hosts
        line: "{{ item }}"
      loop:
        - "$PUPPET_SERVER_PRIVATE_IP mrudloff-puppet-server mrudloff-puppet-server.us-east-2.compute.internal puppet"
        - "$PUPPET_CLIENT_PRIVATE_IP mrudloff-puppet-client mrudloff-puppet-client.us-east-2.compute.internal"

    - name: Update apt cache
      apt:
        update_cache: yes

    - name: Install build-essential package
      apt:
        name: build-essential
        state: present
    - name: Upgrade packages
      apt:
        upgrade: yes  

- hosts: puppetserver
  become: yes
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: /Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem
  tasks:
    - name: Set hostname using hostnamectl
      ansible.builtin.command:
        cmd: hostnamectl set-hostname mrudloff-puppet-server.us-east-2.compute.internal
      become: yes

    - name: Update apt cache
      apt:
        update_cache: yes

    - name: Download Puppet Server package
      get_url:
        url: https://apt.puppetlabs.com/puppet8-release-jammy.deb
        dest: /tmp/puppet8-release-jammy.deb

    - name: Install Puppet Server package
      apt:
        deb: /tmp/puppet8-release-jammy.deb

    - name: Install Puppet Server
      apt:
        name: puppetserver
        state: present
        update_cache: yes

    - name: Replace JAVA_ARGS in puppetserver defaults
      lineinfile:
        path: /etc/default/puppetserver
        regexp: 'JAVA_ARGS="-Xms2g -Xmx2g -Djruby.logger.class=com.puppetlabs.jruby_utils.jruby.Slf4jLogger"'
        line: 'JAVA_ARGS="-Xms1g -Xmx1g -Djruby.logger.class=com.puppetlabs.jruby_utils.jruby.Slf4jLogger"'

    - name: Start and enable Puppet Server
      systemd:
        name: puppetserver
        state: started
        enabled: yes
 
    - name: Ensure the directory /etc/puppetlabs/code/environments/production/modules/tlmagent/files/ exists
      ansible.builtin.file:
        path: /etc/puppetlabs/code/environments/production/modules/tlmagent/files/
        state: directory

    - name: Ensure the directory /etc/puppetlabs/code/environments/production/modules/tlmagent/manifests/ exists
      ansible.builtin.file:
        path: /etc/puppetlabs/code/environments/production/modules/tlmagent/manifests/
        state: directory
 
    - name: Copy tlm files to remote server
      copy:
        src: "$puppet_tlmfiles_path/{{ item }}"
        dest: "/etc/puppetlabs/code/environments/production/modules/tlmagent/files/{{ item }}"
      with_items:
        - DigiCertTLMAgentGPOInstaller.tar.gz

    - name: Copy Puppet files to remote server
      copy:
        src: "$puppet_tlmfiles_path/{{ item }}"
        dest: "/etc/puppetlabs/code/environments/production/modules/tlmagent/manifests/{{ item }}"
      with_items:
        - init.pp
 
    - name: Copy Puppet files to remote server
      copy:
        src: "$puppet_tlmfiles_path/{{ item }}"
        dest: "/etc/puppetlabs/code/environments/production/manifests/{{ item }}"
      with_items:
        - site.pp    

- hosts: puppetclient
  become: yes
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: /Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem
    apache_server_name: $PUPPET_CLIENT_PUBLIC_DNS
    apache_document_root: /var/www/html  
  tasks:
    - name: Install Apache
      apt:
        name: apache2
        state: latest
    - name: Create /etc/ssl/private/ directory
      file:
        path: /etc/ssl/private/
        state: directory
        owner: root
        group: root
        mode: '0700'

    - name: Create /etc/ssl/certs/ directory
      file:
        path: /etc/ssl/certs/
        state: directory
        owner: root
        group: root
        mode: '0755'

    - name: Copy files to remote server
      copy:
        src: "$puppet_certs_path/{{ item }}"
        dest: "/etc/ssl/private/{{ item }}"
      with_items:
        - puppet-apache-selfsigned.key

    - name: Copy files to remote server
      copy:
        src: "$puppet_certs_path/{{ item }}"
        dest: "/etc/ssl/certs/{{ item }}"
      with_items:
        - puppet-apache-selfsigned.crt

    - name: Enable Apache2 modules
      apache2_module:
        name: "{{ item }}"
        state: present
      loop:
        - ssl
        - rewrite
   
    - name: Configure Apache2 for HTTPS
      template:
        src: $puppet_templates_path/puppet-apache-ssl.conf.j2
        dest: /etc/apache2/sites-available/default-ssl.conf
      notify: Restart Apache2

    - name: Enable Apache2 default SSL virtual host
      command: a2ensite default-ssl

    - name: Configure Apache2 to redirect HTTP to HTTPS
      template:
        src: $puppet_templates_path/puppet-apache-redirect.conf.j2
        dest: /etc/apache2/sites-available/000-default.conf
      notify: Restart Apache2

    - name: Set hostname using hostnamectl
      ansible.builtin.command:
        cmd: hostnamectl set-hostname mrudloff-puppet-client.us-east-2.compute.internal
      become: yes 

    - name: Download Puppet Agent package
      get_url:
        url: https://apt.puppetlabs.com/puppet8-release-jammy.deb
        dest: /tmp/puppet8-release-jammy.deb

    - name: Install Puppet Agent package
      apt:
        deb: /tmp/puppet8-release-jammy.deb

    - name: Install Puppet Agent
      apt:
        name: puppet-agent
        state: present
        update_cache: yes

    - name: Update puppet.conf with server and certname
      blockinfile:
        path: /etc/puppetlabs/puppet/puppet.conf
        block: |
          [main]
          certname = mrudloff-puppet-client
          server = puppet
          [agent]
          server = puppet
          ca_server = puppet

    - name: Start and enable Puppet service
      systemd:
        name: puppet
        state: started
        enabled: yes

  handlers:
    - name: Restart Apache2
      service:
        name: apache2
        state: restarted

- hosts: puppetserver
  become: yes
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: /Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem
  tasks:
    - name: Run the Puppetserver CA sign command
      command: /opt/puppetlabs/bin/puppetserver ca sign --all
      become: yes 

EOF
}

# Call the functions
configure_puppet_hosts
configure_apache_templates
create_selfsigned_certificates
configure_puppet_playbook

# Running Playbook
export ANSIBLE_HOST_KEY_CHECKING=False
ansible-playbook -i $puppet_automation_path/puppethosts $puppet_automation_path/puppet_server.yml

  exit
}

menu_option_three() {

#!/bin/bash

AWS_ACCESS_KEY_ID=$(security find-generic-password -a $USER -s AWS_ACCESS_KEY_ID -w aws.secrets)
AWS_SECRET_ACCESS_KEY=$(security find-generic-password -a $USER -s AWS_SECRET_ACCESS_KEY -w aws.secrets)
AWS_DEFAULT_REGION=$(security find-generic-password -a $USER -s AWS_DEFAULT_REGION -w aws.secrets)

# Run aws configure with the provided values
aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID"
aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY"
aws configure set default.region "$AWS_DEFAULT_REGION"

# Set AWS region
AWS_REGION=$(security find-generic-password -a $USER -s AWS_DEFAULT_REGION -w aws.secrets)

# Set instance configurations
INSTANCE_TYPE="t2.medium"
KEY_NAME="mrudloff-keypair"
SECURITY_GROUP_ID="sg-09dae9711b0b7e305"
VPC_ID="vpc-3409ac5f"
SUBNET_ID="subnet-2d915d46"

# Prompt the user to choose the AMI
clear
echo "Which AMI would you like to deploy?"
echo "1. Ubuntu 24.04"
echo "2. Ubuntu 22.04"
echo "3. Ubuntu 18.04"
read -p "Enter your choice (1,2  or 3): " choice

# Set the AMI_ID based on the user's choice
case $choice in 
  1)
    AMI_ID="ami-09040d770ffe2224f"
    echo "Selected AMI: Ubuntu 24.04"
    ;;
  2)
    AMI_ID="ami-0b8b44ec9a8f90422"
    echo "Selected AMI: Ubuntu 22.04"
    ;;
  3)
    AMI_ID="ami-0e4c27be5484b93d6"
    echo "Selected AMI: Ubuntu 18.04"
    ;;
  *)
    echo "Invalid choice. Defaulting to Ubuntu 22.04."
    AMI_ID="ami-0e4c27be5484b93d6"
    ;;
esac

# Chef Specific Path Variables
chef_automation_path="/Users/michaelrudloff/Dropbox/vscode/chef_automation"
chef_certs_path="/Users/michaelrudloff/Dropbox/vscode/chef_automation/certs"
chef_tlmfiles_path="/Users/michaelrudloff/Dropbox/vscode/chef_automation/tlmfiles"
chef_templates_path="/Users/michaelrudloff/Dropbox/vscode/chef_automation/templates"
chef_hosts_path="/Users/michaelrudloff/Dropbox/vscode/chef_automation/upload_to_ansible_host"
chef_hosts_local_path="/Users/michaelrudloff/Dropbox/vscode/chef_automation"
chef_key_file="/Users/michaelrudloff/Dropbox/vscode/key"

# Create the mrudloff-chef-server ec2 instances
CHEF_SERVER_INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SECURITY_GROUP_ID" \
    --subnet-id "$SUBNET_ID" \
    --associate-public-ip-address \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=mrudloff-chef-server}]' \
    --query 'Instances[0].InstanceId' \
    --output text \
    --region "$AWS_REGION")

echo "Chef Environment is being created. Please wait..."
echo 
echo "The environment will consist of the following:"
echo "1. Chef Server"
echo "2. Chef Workstation"
echo "3. Chef Managed Node"
echo
echo "The Chef Managed Node will have Apache with self-signed TLS installed and configured"
echo
echo "mrudloff-chef-server instance ID: $CHEF_SERVER_INSTANCE_ID"

CHEF_WORKSTATION_INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SECURITY_GROUP_ID" \
    --subnet-id "$SUBNET_ID" \
    --associate-public-ip-address \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=mrudloff-chef-workstation}]' \
    --query 'Instances[0].InstanceId' \
    --output text \
    --region "$AWS_REGION")
echo "mrudloff-chef-workstation instance ID: $CHEF_WORKSTATION_INSTANCE_ID"

CHEF_NODE_INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SECURITY_GROUP_ID" \
    --subnet-id "$SUBNET_ID" \
    --associate-public-ip-address \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=mrudloff-chef-node}]' \
    --query 'Instances[0].InstanceId' \
    --output text \
    --region "$AWS_REGION")
echo "mrudloff-chef-node instance ID: $CHEF_NODE_INSTANCE_ID"

# Get the public DNS and private IP addresses of the Chef ec2 instances
CHEF_SERVER_PUBLIC_DNS=$(aws ec2 describe-instances \
    --instance-ids "$CHEF_SERVER_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicDnsName' \
    --output text \
    --region "$AWS_REGION")
CHEF_SERVER_PRIVATE_IP=$(aws ec2 describe-instances \
    --instance-ids "$CHEF_SERVER_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' \
    --output text \
    --region "$AWS_REGION")
CHEF_WORKSTATION_PUBLIC_DNS=$(aws ec2 describe-instances \
    --instance-ids "$CHEF_WORKSTATION_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicDnsName' \
    --output text \
    --region "$AWS_REGION")
CHEF_WORKSTATION_PRIVATE_IP=$(aws ec2 describe-instances \
    --instance-ids "$CHEF_WORKSTATION_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' \
    --output text \
    --region "$AWS_REGION")    
CHEF_NODE_PUBLIC_DNS=$(aws ec2 describe-instances \
    --instance-ids "$CHEF_NODE_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicDnsName' \
    --output text \
    --region "$AWS_REGION")
CHEF_NODE_PRIVATE_IP=$(aws ec2 describe-instances \
    --instance-ids "$CHEF_NODE_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' \
    --output text \
    --region "$AWS_REGION")
echo
echo "The following ec2 instances have been created:"
echo
echo "Host: mrudloff-chef-server"
echo "Public DNS: $CHEF_SERVER_PUBLIC_DNS"
echo "Private IP: $CHEF_SERVER_PRIVATE_IP"
echo
echo "Host: mrudloff-chef-workstation"
echo "Public DNS: $CHEF_WORKSTATION_PUBLIC_DNS"
echo "Private IP: $CHEF_WORKSTATION_PRIVATE_IP"
echo
echo "Host: mrudloff-chef-node"
echo "Public DNS: $CHEF_NODE_PUBLIC_DNS"
echo "Private IP: $CHEF_NODE_PRIVATE_IP"

# Get instance IDs of the newly created Chef instances
CHEF_SERVER_INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=mrudloff-chef-server" "Name=instance-state-name,Values=running" --query "Reservations[*].Instances[*].[InstanceId]" --output text --region "$AWS_REGION")
CHEF_WORKSTATION_INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=mrudloff-chef-workstation" "Name=instance-state-name,Values=running" --query "Reservations[*].Instances[*].[InstanceId]" --output text --region "$AWS_REGION")
CHEF_NODE_INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=mrudloff-chef-node" "Name=instance-state-name,Values=running" --query "Reservations[*].Instances[*].[InstanceId]" --output text --region "$AWS_REGION")

# Declare array of Chef instance IDs
INSTANCE_IDS=("$CHEF_SERVER_INSTANCE_ID" "$CHEF_WORKSTATION_INSTANCE_ID" "$CHEF_NODE_INSTANCE_ID")

# Wait for 3 minutes to give the Chef instances some time to initialize
echo
duration=180
while [ $duration -gt 0 ]; do
    printf "\rWaiting %02d seconds for Chef instances to initialize before checking again..." $duration
    sleep 1
    ((duration--))
done

# Wait for each Chef instance to pass status checks
for INSTANCE_ID in "${INSTANCE_IDS[@]}"; do
    INSTANCE_STATUS=""
    while [ -z "$INSTANCE_STATUS" ] || [ "$INSTANCE_STATUS" != "ok" ]; do
        echo 
        echo "Checking status of ec2 instances"
        INSTANCE_STATUS=$(aws ec2 describe-instance-status --instance-ids $INSTANCE_ID --query 'InstanceStatuses[0].InstanceStatus.Status' --output text)
        echo "Instance status: $INSTANCE_STATUS"
        INSTANCE_STATUS=$(aws ec2 describe-instance-status --instance-ids $INSTANCE_ID --query 'InstanceStatuses[0].InstanceStatus.Status' --output text)
        if [ -z "$INSTANCE_STATUS" ] || [ "$INSTANCE_STATUS" != "ok" ]; then
            echo
            duration2=15
            while [ $duration2 -gt 0 ]; do
            printf "\rInstances are not ready yet. Waiting for %02d seconds before checking again." $duration2
            sleep 1
            ((duration2--))
            done
        fi
    done
done
echo
echo "All instances have passed status checks and are ready to use."

# Ensure SSH Keys are being accepted / skipped
export CHEF_HOST_KEY_CHECKING=False

# Create Chef Configuration and Playbook
echo 
echo "Creating Chef Configuration and Playbook"

# Define the instance names before attempting to retrieve their IPs
INSTANCE_NAMES=("mrudloff-chef-server" "mrudloff-chef-workstation" "mrudloff-chef-node")

# Declare global variables for public DNS names to ensure they're available for all parts of the script
CHEF_SERVER_PUBLIC_DNS=""
CHEF_WORKSTATION_PUBLIC_DNS=""
CHEF_NODE_PUBLIC_DNS=""

# Retrieve the public DNS names of the running instances
for INSTANCE_NAME in "${INSTANCE_NAMES[@]}"; do
    INSTANCE_DETAILS=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=running" --query 'Reservations[*].Instances[*].[PublicDnsName]' --output text)
    if [ "$INSTANCE_NAME" == "mrudloff-chef-server" ]; then
        CHEF_SERVER_PUBLIC_DNS=$INSTANCE_DETAILS
    elif [ "$INSTANCE_NAME" == "mrudloff-chef-workstation" ]; then
        CHEF_WORKSTATION_PUBLIC_DNS=$INSTANCE_DETAILS   
    elif [ "$INSTANCE_NAME" == "mrudloff-chef-node" ]; then
        CHEF_NODE_PUBLIC_DNS=$INSTANCE_DETAILS          
    fi
done

# Configure Chef hosts
configure_chef_hosts() {
    echo 
    echo "Configuring Ansible hosts file hosts to deploy Chef using Ansible..."

    # Check and delete existing hosts file
    if [ -f "$chef_automation_path/hosts" ]; then
        rm $chef_automation_path/hosts
    fi

    # Create hosts file
    cat << EOF > $chef_automation_path/hosts
[chefserver]
mrudloff-chef-server ansible_host=$CHEF_SERVER_PUBLIC_DNS ansible_user=ubuntu ansible_ssh_private_key_file=/Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem

[chefworkstation]
mrudloff-chef-workstation ansible_host=$CHEF_WORKSTATION_PUBLIC_DNS ansible_user=ubuntu ansible_ssh_private_key_file=/Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem

[chefnode]
mrudloff-chef-node ansible_host=$CHEF_NODE_PUBLIC_DNS ansible_user=ubuntu ansible_ssh_private_key_file=/Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem
EOF
}

# Prompt the user for the domain name
# read -p "Domain used for the certificate used for the Puppet Client? " puppet_domain_name

# Configure Apache templates
configure_apache_templates() {
    echo "Configuring Apache templates..."

    # Create templates directory if it doesn't exist
    mkdir -p $chef_templates_path

    # Check and delete existing Chef Client apache-redirect.conf.j2 file
    if [ -f "$chef_templates_path/chef-apache-redirect.conf.j2" ]; then
        rm $chef_templates_path/chef-apache-redirect.conf.j2
    fi

    # Create Chef Client apache-redirect.conf.j2 file
    cat << EOF > $chef_templates_path/chef-apache-redirect.conf.j2
<VirtualHost *:80>
    ServerName $CHEF_NODE_PUBLIC_DNS
    Redirect permanent / https://$CHEF_NODE_PUBLIC_DNS/
</VirtualHost>
EOF
}

    # Check and delete existing apache-ssl.conf.j2 file
    if [ -f "$chef_templates_path/chef-apache-ssl.conf.j2" ]; then
        rm $chef_templates_path/chef-apache-ssl.conf.j2
    fi

    # Create Chef Client apache-ssl.conf.j2 file
    cat << EOF > $chef_templates_path/chef-apache-ssl.conf.j2
<VirtualHost *:443>
    ServerName $CHEF_NODE_PUBLIC_DNS
    DocumentRoot /var/www/html
    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/chef-apache-selfsigned.crt
    SSLCertificateKeyFile /etc/ssl/private/chef-apache-selfsigned.key
</VirtualHost>
EOF


# Create Chef Client self-signed certificates
create_selfsigned_certificates() {
    echo "Creating self-signed certificates..."

    # Create certs directory if it doesn't exist
    mkdir -p $chef_certs_path

    # Create self-signed certificates for Chef client apache server
    openssl req -x509 -newkey rsa:4096 -keyout $chef_certs_path/chef-apache-selfsigned.key -out $chef_certs_path/chef-apache-selfsigned.crt -days 365 -nodes -subj "/C=GB/ST=Cambs/L=Ely/O=Digicert/OU=Product/CN=mrudloff-chef-node/emailAddress=michael.rudloff@digicert.com" 
}

# Configure Chef playbook
configure_chef_playbook() {
    echo "Configuring Chef playbook..."

    # Check and delete existing playbook file
    if [ -f "$chef_automation_path/chef_server.yml" ]; then
        rm $chef_automation_path/chef_server.yml
    fi

    # Create playbook file
    cat << EOF > $chef_automation_path/chef_server.yml
---
- hosts: all
  become: yes
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: /Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem
  tasks:
    - name: Add lines to /etc/hosts
      ansible.builtin.lineinfile:
        path: /etc/hosts
        line: "{{ item }}"
      loop:
        - "$CHEF_SERVER_PRIVATE_IP mrudloff-chef-server mrudloff-chef-server.us-east-2.compute.internal"
        - "$CHEF_WORKSTATION_PRIVATE_IP mrudloff-chef-workstation mrudloff-chef-workstation.us-east-2.compute.internal"
        - "$CHEF_NODE_PRIVATE_IP mrudloff-chef-node mrudloff-chef-node.us-east-2.compute.internal"
    - name: Update apt cache
      apt:
        update_cache: yes
    - name: Install build-essential package
      apt:
        name: build-essential
        state: present
    - name: Upgrade packages
      apt:
        upgrade: yes

- hosts: chefserver
  become: yes
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: /Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem
  tasks:
    - name: Set hostname using hostnamectl
      ansible.builtin.command:
        cmd: hostnamectl set-hostname mrudloff-chef-server.us-east-2.compute.internal
      become: yes

    - name: Install Pre-Reqs
      apt:
        name:
          - curl
          - wget
          - gnupg2
        state: present
        update_cache: yes

    - name: Backup SSH Configuration
      command: cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

    - name: Edit SSH Configuration - PermitRootLogin
      lineinfile:
        path: /etc/ssh/sshd_config
        regexp: '^#?PermitRootLogin'
        line: 'PermitRootLogin yes'

    - name: Edit SSH Configuration - PubkeyAuthentication
      lineinfile:
        path: /etc/ssh/sshd_config
        regexp: '^#?PubkeyAuthentication'
        line: 'PubkeyAuthentication yes'

    - name: Restart SSH
      systemd:
        name: ssh
        state: restarted

    - name: Generate new SSH key pair
      ansible.builtin.openssh_keypair:
        path: /root/.ssh/id_rsa
        type: rsa
        size: 4096
        comment: "root@mrudloff-chef-server"
        force: true        
        
    - name: Copy public key to /home/ubuntu
      copy:
        src: /root/.ssh/id_rsa.pub
        dest: /home/ubuntu/id_rsa.pub
        owner: ubuntu
        group: ubuntu
        mode: '0644'
        remote_src: yes

- hosts: chefworkstation
  become: yes
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: /Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem
  tasks:
    - name: Set hostname using hostnamectl
      ansible.builtin.command:
        cmd: hostnamectl set-hostname mrudloff-chef-workstation.us-east-2.compute.internal
      become: yes

    - name: Generate new SSH key pair
      ansible.builtin.openssh_keypair:
        path: /root/.ssh/id_rsa
        type: rsa
        size: 4096
        comment: "root@mrudloff-chef-workstation"
        force: true        
    - name: Copy public key to /home/ubuntu
      copy:
        src: /root/.ssh/id_rsa.pub
        dest: /home/ubuntu/id_rsa.pub
        owner: ubuntu
        group: ubuntu
        mode: '0644'
        remote_src: yes      

- hosts: chefnode
  become: yes
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: /Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem
  tasks:
    - name: Set hostname using hostnamectl
      ansible.builtin.command:
        cmd: hostnamectl set-hostname mrudloff-chef-node.us-east-2.compute.internal
      become: yes
    - name: Install Apache
      apt:
        name: apache2
        state: latest
    - name: Create /etc/ssl/private/ directory
      file:
        path: /etc/ssl/private/
        state: directory
        owner: root
        group: root
        mode: '0700'

    - name: Create /etc/ssl/certs/ directory
      file:
        path: /etc/ssl/certs/
        state: directory
        owner: root
        group: root
        mode: '0755'

    - name: Copy files to remote server
      copy:
        src: "$chef_certs_path/{{ item }}"
        dest: "/etc/ssl/private/{{ item }}"
      with_items:
        - chef-apache-selfsigned.key

    - name: Copy files to remote server
      copy:
        src: "$chef_certs_path/{{ item }}"
        dest: "/etc/ssl/certs/{{ item }}"
      with_items:
        - chef-apache-selfsigned.crt

    - name: Enable Apache2 modules
      apache2_module:
        name: "{{ item }}"
        state: present
      loop:
        - ssl
        - rewrite
 
    - name: Configure Apache2 for HTTPS
      template:
        src: $chef_templates_path/chef-apache-ssl.conf.j2
        dest: /etc/apache2/sites-available/default-ssl.conf
      notify: Restart Apache2

    - name: Enable Apache2 default SSL virtual host
      command: a2ensite default-ssl

    - name: Configure Apache2 to redirect HTTP to HTTPS
      template:
        src: $chef_templates_path/chef-apache-redirect.conf.j2
        dest: /etc/apache2/sites-available/000-default.conf
      notify: Restart Apache2

    - name: Generate new SSH key pair
      ansible.builtin.openssh_keypair:
        path: /root/.ssh/id_rsa
        type: rsa
        size: 4096
        comment: "root@mrudloff-chef-node"
        force: true         
    - name: Copy public key to /home/ubuntu
      copy:
        src: /root/.ssh/id_rsa.pub
        dest: /home/ubuntu/id_rsa.pub
        owner: ubuntu
        group: ubuntu
        mode: '0644'
        remote_src: yes

  handlers:
    - name: Restart Apache2
      service:
        name: apache2
        state: restarted

- hosts: localhost
  become: no
  vars:
    remote_user: ubuntu
    remote_host: $CHEF_SERVER_PUBLIC_DNS
    remote_file: /home/ubuntu/id_rsa.pub
    local_dest: /Users/michaelrudloff/Dropbox/vscode/SSH_Keys_For_Deployed_Servers/chef_server.pub
    ssh_key: /Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem
  tasks:
    - name: Copy public key from remote server using scp
      shell: |
        scp -i {{ ssh_key }} {{ remote_user }}@{{ remote_host }}:{{ remote_file }} {{ local_dest }}
      delegate_to: localhost
      ignore_errors: no
      register: scp_copy

    - name: Debug SCP output
      debug:
        var: scp_copy.stdout_lines

    - name: Debug SCP error
      debug:
        var: scp_copy.stderr_lines

- hosts: localhost
  become: no
  vars:
    remote_user: ubuntu
    remote_host: $CHEF_WORKSTATION_PUBLIC_DNS
    remote_file: /home/ubuntu/id_rsa.pub
    local_dest: /Users/michaelrudloff/Dropbox/vscode/SSH_Keys_For_Deployed_Servers/chef_workstation.pub
    ssh_key: /Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem
  tasks:
    - name: Copy public key from remote server using scp
      shell: |
        scp -i {{ ssh_key }} {{ remote_user }}@{{ remote_host }}:{{ remote_file }} {{ local_dest }}
      delegate_to: localhost
      ignore_errors: no
      register: scp_copy

    - name: Debug SCP output
      debug:
        var: scp_copy.stdout_lines

    - name: Debug SCP error
      debug:
        var: scp_copy.stderr_lines

- hosts: localhost
  become: no
  vars:
    remote_user: ubuntu
    remote_host: $CHEF_NODE_PUBLIC_DNS
    remote_file: /home/ubuntu/id_rsa.pub
    local_dest: /Users/michaelrudloff/Dropbox/vscode/SSH_Keys_For_Deployed_Servers/chef_node.pub
    ssh_key: /Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem
  tasks:
    - name: Copy public key from remote server using scp
      shell: |
        scp -i {{ ssh_key }} {{ remote_user }}@{{ remote_host }}:{{ remote_file }} {{ local_dest }}
      delegate_to: localhost
      ignore_errors: no
      register: scp_copy

    - name: Debug SCP output
      debug:
        var: scp_copy.stdout_lines

    - name: Debug SCP error
      debug:
        var: scp_copy.stderr_lines


- hosts: chefserver
  become: yes
  vars:
    local_files:      
      - "/Users/michaelrudloff/Dropbox/vscode/SSH_Keys_For_Deployed_Servers/chef_workstation.pub"
      - "/Users/michaelrudloff/Dropbox/vscode/SSH_Keys_For_Deployed_Servers/chef_node.pub"
    remote_temp_dir: "/tmp/ssh_keys"
    remote_final_path: "/root/.ssh/authorized_keys"
    remote_hosts:
      - mrudloff-chef-workstation
      - mrudloff-chef-node        
  tasks:
    - name: Create temporary directory on the remote server
      ansible.builtin.file:
        path: "{{ remote_temp_dir }}"
        state: directory

    - name: Copy local files to remote server's temporary directory
      ansible.builtin.copy:
        src: "{{ item }}"
        dest: "{{ remote_temp_dir }}/{{ item | basename }}"
      loop: "{{ local_files }}"
      loop_control:
        label: "{{ item }}"

    - name: Append content of the temporary files to the remote authorized_keys file
      ansible.builtin.shell: |
        cat {{ remote_temp_dir }}/*.pub >> "{{ remote_final_path }}"

    - name: Remove specific line from /root/.ssh/authorized_keys
      ansible.builtin.lineinfile:
        path: /root/.ssh/authorized_keys
        line: >-
          no-port-forwarding,no-agent-forwarding,no-X11-forwarding,
          command="echo 'Please login as the user \"ubuntu\" rather than the user \"root\".'; echo; sleep 10; exit 142"
        state: absent       

    - name: Ensure known_hosts contains the remote hosts
      ansible.builtin.shell: ssh-keyscan {{ item }} >> /root/.ssh/known_hosts
      with_items: "{{ remote_hosts }}"
      ignore_errors: yes 

- hosts: chefworkstation
  become: yes
  vars:
    local_files:
      - "/Users/michaelrudloff/Dropbox/vscode/SSH_Keys_For_Deployed_Servers/chef_server.pub"
      - "/Users/michaelrudloff/Dropbox/vscode/SSH_Keys_For_Deployed_Servers/chef_node.pub"
    remote_temp_dir: "/tmp/ssh_keys"
    remote_final_path: "/root/.ssh/authorized_keys"
    remote_hosts:
      - mrudloff-chef-server
      - mrudloff-chef-node        
  tasks:
    - name: Create temporary directory on the remote server
      ansible.builtin.file:
        path: "{{ remote_temp_dir }}"
        state: directory

    - name: Copy local files to remote server's temporary directory
      ansible.builtin.copy:
        src: "{{ item }}"
        dest: "{{ remote_temp_dir }}/{{ item | basename }}"
      loop: "{{ local_files }}"
      loop_control:
        label: "{{ item }}"

    - name: Append content of the temporary files to the remote authorized_keys file
      ansible.builtin.shell: |
        cat {{ remote_temp_dir }}/*.pub >> "{{ remote_final_path }}"

    - name: Remove specific line from /root/.ssh/authorized_keys
      ansible.builtin.lineinfile:
        path: /root/.ssh/authorized_keys
        line: >-
          no-port-forwarding,no-agent-forwarding,no-X11-forwarding,
          command="echo 'Please login as the user \"ubuntu\" rather than the user \"root\".'; echo; sleep 10; exit 142"
        state: absent   

    - name: Ensure known_hosts contains the remote hosts
      ansible.builtin.shell: ssh-keyscan {{ item }} >> /root/.ssh/known_hosts
      with_items: "{{ remote_hosts }}"
      ignore_errors: yes

- hosts: chefnode
  become: yes
  vars:
    local_files:
      - "/Users/michaelrudloff/Dropbox/vscode/SSH_Keys_For_Deployed_Servers/chef_server.pub"
      - "/Users/michaelrudloff/Dropbox/vscode/SSH_Keys_For_Deployed_Servers/chef_workstation.pub"
    remote_temp_dir: "/tmp/ssh_keys"
    remote_final_path: "/root/.ssh/authorized_keys"
    remote_hosts:
      - mrudloff-chef-server
      - mrudloff-chef-workstation    
  tasks:
    - name: Create temporary directory on the remote server
      ansible.builtin.file:
        path: "{{ remote_temp_dir }}"
        state: directory

    - name: Copy local files to remote server's temporary directory
      ansible.builtin.copy:
        src: "{{ item }}"
        dest: "{{ remote_temp_dir }}/{{ item | basename }}"
      loop: "{{ local_files }}"
      loop_control:
        label: "{{ item }}"

    - name: Append content of the temporary files to the remote authorized_keys file
      ansible.builtin.shell: |
        cat {{ remote_temp_dir }}/*.pub >> "{{ remote_final_path }}"

    - name: Remove specific line from /root/.ssh/authorized_keys
      ansible.builtin.lineinfile:
        path: /root/.ssh/authorized_keys
        line: >-
          no-port-forwarding,no-agent-forwarding,no-X11-forwarding,
          command="echo 'Please login as the user \"ubuntu\" rather than the user \"root\".'; echo; sleep 10; exit 142"
        state: absent

    - name: Ensure known_hosts contains the remote hosts
      ansible.builtin.shell: ssh-keyscan {{ item }} >> /root/.ssh/known_hosts
      with_items: "{{ remote_hosts }}"
      ignore_errors: yes         

- hosts: chefserver
  become: yes
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: /Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem
  tasks:
    - name: Download Chef Server binaries
      get_url:
        url: https://packages.chef.io/files/stable/chef-server/15.9.38/ubuntu/22.04/chef-server-core_15.9.38-1_amd64.deb
        dest: /tmp/chef-server-core_15.9.38-1_amd64.deb

    - name: Install Chef Server binaries
      apt:
        deb: /tmp/chef-server-core_15.9.38-1_amd64.deb

    - name: Configure Chef Server
      command: chef-server-ctl reconfigure --chef-license=accept

    - name: Create Chef Certificate Directory
      file:
        path: "{{ ansible_env.HOME }}/.chef"
        state: directory
        mode: '0755'

    - name: Create Chef User
      ansible.builtin.command: >
        chef-server-ctl user-create
        chef
        Michael
        Rudloff
        michael.rudloff@digicert.com
        'P4SSw0rd123!'
        --filename /root/.chef/chef.pem
      register: create_user_output
      changed_when: "'WARN' not in create_user_output.stderr"

    - name: Check if organization exists
      ansible.builtin.shell: chef-server-ctl org-list
      register: org_list_output

    - name: Create Org and associate User if not exists
      ansible.builtin.command: >
        chef-server-ctl org-create
        digicert
        "Digicert"
        --association_user chef
        --filename /root/.chef/digicert.pem
      when: "'digicert' not in org_list_output.stdout"
      register: create_org_output
      changed_when: "'WARN' not in create_org_output.stderr"

    - name: Debug output of org creation
      ansible.builtin.debug:
        msg: "Organization 'digicert' exists; not recreated"
      when: "'digicert' in org_list_output.stdout"
    
- hosts: chefworkstation
  become: yes
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: /Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem
  tasks:
    - name: Download Chef Workstation binaries
      get_url:
        url: https://packages.chef.io/files/stable/chef-workstation/24.6.1066/ubuntu/22.04/chef-workstation_24.6.1066-1_amd64.deb
        dest: /tmp/chef-workstation_24.6.1066-1_amd64.deb

    - name: Install Chef Workstation binaries
      apt:
        deb: /tmp/chef-workstation_24.6.1066-1_amd64.deb

    - name: Generate Chef Repo
      command: chef generate repo ~/chef-repo --chef-license=accept
      args:
        creates: ~/chef-repo

    - name: Create .chef folder under repo
      file:
        path: ~/chef-repo/.chef
        state: directory

- hosts: chefserver
  gather_facts: no
  become: yes
  become_user: root
  tasks:
    - name: Copy chef.pem to workstation
      ansible.builtin.command:
        cmd: scp /root/.chef/chef.pem root@mrudloff-chef-workstation:/root/chef-repo/.chef/

    - name: Copy digicert.pem to workstation
      ansible.builtin.command:
        cmd: scp /root/.chef/digicert.pem root@mrudloff-chef-workstation:/root/chef-repo/.chef

- hosts: chefworkstation
  become: yes
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: /Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem
  tasks:
    - name: Ensure .chef directory exists
      file:
        path: /root/chef-repo/.chef
        state: directory
        mode: '0755'

    - name: Create the config.rb file
      copy:
        dest: /root/chef-repo/.chef/config.rb
        content: |
          current_dir = File.dirname(__FILE__)
          log_level                :info
          log_location             STDOUT
          node_name                'chef'
          client_key               "/root/chef-repo/.chef/chef.pem"
          validation_client_name   'digicert-validator'
          validation_key           "digicert-validator.pem"
          chef_server_url          'https://mrudloff-chef-server/organizations/digicert'
          cache_type               'BasicFile'
          cache_options( :path => "#{ENV['HOME']}/.chef/checksums" )
          cookbook_path            ["#{current_dir}/../cookbooks"]

    - name: Run knife ssl fetch
      shell: |
        cd /root/chef-repo/
        knife ssl fetch -c /root/chef-repo/.chef/config.rb

    - name: Change directory and run knife bootstrap
      shell: |
        cd /root/chef-repo/.chef
        yes | knife bootstrap mrudloff-chef-node --ssh-user root --sudo --ssh-identity-file /root/.ssh/id_rsa --node-name mrudloff-chef-node

    - name: Change directory and generate cookbook
      shell: |
        cd /root/chef-repo/cookbooks
        yes | chef generate cookbook tlmagent

    - name: Ensure target directory exists
      file:
        path: /root/chef-repo/cookbooks/tlmagent/files
        state: directory
        mode: '0755'        

    - name: Ensure target directory exists
      file:
        path: /root/chef-repo/cookbooks/tlmagent/files/default/
        state: directory
        mode: '0755' 

- hosts: localhost
  become: no
  tasks:        
    - name: Upload DigiCertTLMAgentGPOInstaller to workstation
      shell: |
        scp -i /Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem /Users/michaelrudloff/Dropbox/vscode/chef_automation/tlmfiles/DigiCertTLMAgentGPOInstaller.tar.gz ubuntu@$CHEF_WORKSTATION_PUBLIC_DNS:/home/ubuntu/

- hosts: chefworkstation
  become: yes  
  tasks:  
    - name: Move TLM Agent installer to cookbook directory
      command: mv /home/ubuntu/DigiCertTLMAgentGPOInstaller.tar.gz /root/chef-repo/cookbooks/tlmagent/files/default/

- name: Create default.rb recipe for tlmagent cookbook
  hosts: chefworkstation
  become: yes
  tasks:
    - name: Ensure the tlmagent directory exists
      ansible.builtin.file:
        path: ~/chef-repo/cookbooks/tlmagent/recipes
        state: directory
        mode: '0755'

    - name: Create default.rb file
      ansible.builtin.copy:
        dest: /root/chef-repo/cookbooks/tlmagent/recipes/default.rb
        content: |
          #
          # Cookbook:: tlmagent
          # Recipe:: default
          #
          # Copyright:: 2024, The Authors, All Rights Reserved.
          #
          # Cookbook:: tlm_agent
          # Recipe:: default
          #

          # Define variables
          bundle_name = 'tlm_agent_3.0.11_linux64.tar.gz'
          alias_name = 'mrudloff-chef-client'
          businessUnit = '542bce5b-9a54-41df-a054-fe977133ee09'
          proxy = '' # Define the proxy if required

          # Create the directory with proper permissions
          directory '/opt/digicert' do
            owner 'root'
            group 'root'
            mode '0755'
            action :create
          end

          # Upload the installer file
          cookbook_file '/opt/digicert/DigiCertTLMAgentGPOInstaller.tar.gz' do
            source 'DigiCertTLMAgentGPOInstaller.tar.gz'
            owner 'root'
            group 'root'
            mode '0644'
            action :create
          end

          # Extract the installer file
          execute 'extract_installer' do
            command 'tar xzf /opt/digicert/DigiCertTLMAgentGPOInstaller.tar.gz -C /opt/digicert'
            action :run
            not_if { ::File.directory?('/opt/digicert/DigiCertTLMAgentGPOInstaller') }
          end

          # Make the installation script executable
          file '/opt/digicert/DigiCertTLMAgentGPOInstaller/silentInstaller-by-companion-lnx.sh' do
            mode '0755'
            action :create
          end

          # Execute the installation script with the defined variables
          execute 'run_installer' do
            command <<-EOH
              /opt/digicert/DigiCertTLMAgentGPOInstaller/silentInstaller-by-companion-lnx.sh \
              AGENT_BUNDLE_NAME=#{bundle_name} \
              BUSINESS_UNIT_ID=#{businessUnit} \
              ALIASNAME=#{alias_name} \
              PROXY=#{proxy}
            EOH
            action :run
          end    

    - name: Change directory and knife recipe run list and upload cookbook
      shell: |
        cd ~/chef-repo/cookbooks/tlmagent
        knife node run_list add mrudloff-chef-node 'recipe[tlmagent]'    
        knife cookbook upload tlmagent

- hosts: chefnode
  become: yes  
  tasks:  
    - name: Execute recipe
      shell: |
        chef-client            
                  
EOF
}

# Call the functions
configure_chef_hosts
configure_apache_templates
create_selfsigned_certificates
configure_chef_playbook



# Running Playbook
export ANSIBLE_HOST_KEY_CHECKING=False
ansible-playbook -i $chef_automation_path/hosts $chef_automation_path/chef_server.yml 


  exit
}


menu_option_four() {

#!/bin/bash

AWS_ACCESS_KEY_ID=$(security find-generic-password -a $USER -s AWS_ACCESS_KEY_ID -w aws.secrets)
AWS_SECRET_ACCESS_KEY=$(security find-generic-password -a $USER -s AWS_SECRET_ACCESS_KEY -w aws.secrets)
AWS_DEFAULT_REGION=$(security find-generic-password -a $USER -s AWS_DEFAULT_REGION -w aws.secrets)

# Run aws configure with the provided values
aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID"
aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY"
aws configure set default.region "$AWS_DEFAULT_REGION"

# Set AWS region
AWS_REGION=$(security find-generic-password -a $USER -s AWS_DEFAULT_REGION -w aws.secrets)

# Set instance configurations
INSTANCE_TYPE="t2.medium"
KEY_NAME="mrudloff-keypair"
SECURITY_GROUP_ID="sg-09dae9711b0b7e305"
VPC_ID="vpc-3409ac5f"
SUBNET_ID="subnet-2d915d46"

# Prompt the user to choose the AMI
clear
echo "Which AMI would you like to deploy?"
echo "1. Ubuntu 24.04 (not supported yet)"
echo "2. Ubuntu 22.04 (use THIS ONE)"
echo "3. Ubuntu 18.04 (not supported yet)"
read -p "Enter your choice (1,2  or 3): " choice

# Set the AMI_ID based on the user's choice
case $choice in 
  1)
    AMI_ID="ami-09040d770ffe2224f"
    echo "Selected AMI: Ubuntu 24.04"
    ;;
  2)
    AMI_ID="ami-0b8b44ec9a8f90422"
    echo "Selected AMI: Ubuntu 22.04"
    ;;
  3)
    AMI_ID="ami-0e4c27be5484b93d6"
    echo "Selected AMI: Ubuntu 18.04"
    ;;
  *)
    echo "Invalid choice. Defaulting to Ubuntu 22.04."
    AMI_ID="ami-0e4c27be5484b93d6"
    ;;
esac


# HAP Specific Path Variables
hap_config_path="/Users/michaelrudloff/Dropbox/vscode/haproxy_automation/config"
hap_certs_path="/Users/michaelrudloff/Dropbox/vscode/haproxy_automation/certs"
hap_templates_path="/Users/michaelrudloff/Dropbox/vscode/haproxy_automation/templates"
hap_key_file="/Users/michaelrudloff/Dropbox/vscode/key"

# Create mrudloff-hap-server instance
HAP_SERVER_INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SECURITY_GROUP_ID" \
    --subnet-id "$SUBNET_ID" \
    --associate-public-ip-address \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=mrudloff-hap-server}]' \
    --query 'Instances[0].InstanceId' \
    --output text \
    --region "$AWS_REGION")
echo "HAProxy Environment is being created. Please wait..."
echo 
echo "The environment will consist of the following:"
echo "1. HAProxy Server (OSS)"
echo "2. Loadbalanced Web Server (Web1) with Apache and Index Page"
echo "3. Loadbalanced Web Server (Web2) with Apache and Index Page"
echo
echo "The HAProxy Server will terminate TLS with a self-signed TLS certificate"
echo "HAProxy Server will also have the acme client installed and config updated accordingly"
echo
echo "mrudloff-hap-server instance ID: $HAP_SERVER_INSTANCE_ID"

# Create mrudloff-hap-web1 instance
HAP_WEB1_INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SECURITY_GROUP_ID" \
    --subnet-id "$SUBNET_ID" \
    --associate-public-ip-address \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=mrudloff-hap-web1}]' \
    --query 'Instances[0].InstanceId' \
    --output text \
    --region "$AWS_REGION")
echo "mrudloff-hap-web1 instance ID: $HAP_WEB1_INSTANCE_ID"

# Create mrudloff-hap-web2 instance
HAP_WEB2_INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SECURITY_GROUP_ID" \
    --subnet-id "$SUBNET_ID" \
    --associate-public-ip-address \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=mrudloff-hap-web2}]' \
    --query 'Instances[0].InstanceId' \
    --output text \
    --region "$AWS_REGION")
echo "mrudloff-hap-web2 instance ID: $HAP_WEB2_INSTANCE_ID"


# Get Public DNS name and Private IP address of instances
HAP_SERVER_PUBLIC_DNS=$(aws ec2 describe-instances \
    --instance-ids "$HAP_SERVER_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicDnsName' \
    --output text \
    --region "$AWS_REGION")
HAP_SERVER_PRIVATE_IP=$(aws ec2 describe-instances \
    --instance-ids "$HAP_SERVER_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' \
    --output text \
    --region "$AWS_REGION")

HAP_WEB1_PUBLIC_DNS=$(aws ec2 describe-instances \
    --instance-ids "$HAP_WEB1_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicDnsName' \
    --output text \
    --region "$AWS_REGION")
HAP_WEB1_PRIVATE_IP=$(aws ec2 describe-instances \
    --instance-ids "$HAP_WEB1_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' \
    --output text \
    --region "$AWS_REGION")

HAP_WEB2_PUBLIC_DNS=$(aws ec2 describe-instances \
    --instance-ids "$HAP_WEB2_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicDnsName' \
    --output text \
    --region "$AWS_REGION")
HAP_WEB2_PRIVATE_IP=$(aws ec2 describe-instances \
    --instance-ids "$HAP_WEB2_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' \
    --output text \
    --region "$AWS_REGION")


echo
echo "The following ec2 instances have been created:"
echo
echo "Host: mrudloff-hap-server"
echo "Public DNS: $HAP_SERVER_PUBLIC_DNS"
echo "Private IP: $HAP_SERVER_PRIVATE_IP"
echo
echo "Host: mrudloff-hap-web1"
echo "Public DNS: $HAP_WEB1_PUBLIC_DNS"
echo "Private IP: $HAP_WEB1_PRIVATE_IP"
echo
echo "Host: mrudloff-hap-web2"
echo "Public DNS: $HAP_WEB2_PUBLIC_DNS"
echo "Private IP: $HAP_WEB2_PRIVATE_IP"
  
# Get instance IDs of the newly created Puppet instances
HAP_SERVER_INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=mrudloff-hap-server" "Name=instance-state-name,Values=running" --query "Reservations[*].Instances[*].[InstanceId]" --output text --region "$AWS_REGION")
HAP_WEB1_INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=mrudloff-hap-web1" "Name=instance-state-name,Values=running" --query "Reservations[*].Instances[*].[InstanceId]" --output text --region "$AWS_REGION")
HAP_WEB2_INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=mrudloff-hap-web2" "Name=instance-state-name,Values=running" --query "Reservations[*].Instances[*].[InstanceId]" --output text --region "$AWS_REGION")

# Declare array of Ansible instance IDs
INSTANCE_IDS=("$HAP_SERVER_INSTANCE_ID" "$HAP_WEB1_INSTANCE_ID" "$HAP_WEB2_INSTANCE_ID")

# Wait for 3 minutes to give the Ansible instances some time to initialize
echo
duration=180
while [ $duration -gt 0 ]; do
    printf "\rWaiting %02d seconds for Ansible instances to initialize before checking again..." $duration
    sleep 1
    ((duration--))
done

# Wait for each Ansible instances to pass status checks
for INSTANCE_ID in "${INSTANCE_IDS[@]}"; do
    INSTANCE_STATUS=""
    while [ -z "$INSTANCE_STATUS" ] || [ "$INSTANCE_STATUS" != "ok" ]; do
        echo 
        echo "Checking status of ec2 instances"
        INSTANCE_STATUS=$(aws ec2 describe-instance-status --instance-ids $INSTANCE_ID --query 'InstanceStatuses[0].InstanceStatus.Status' --output text)
        echo "Instance status: $INSTANCE_STATUS"
        INSTANCE_STATUS=$(aws ec2 describe-instance-status --instance-ids $INSTANCE_ID --query 'InstanceStatuses[0].InstanceStatus.Status' --output text)
        if [ -z "$INSTANCE_STATUS" ] || [ "$INSTANCE_STATUS" != "ok" ]; then
            echo
            duration2=15
            while [ $duration2 -gt 0 ]; do
            printf "\rInstances are not ready yet. Waiting for %02d seconds before checking again." $duration2
            sleep 1
            ((duration2--))
            done
        fi
    done
done
echo
echo "All instances have passed status checks and are ready to use."

# Ensure SSH Keys are being accepted / skipped
export ANSIBLE_HOST_KEY_CHECKING=False  
  
  
# Create HAP Configuration and Playbook
echo 
echo "Creating HAP Configuration and Playbook"

# Define the instance names before attempting to retrieve their IPs
INSTANCE_NAMES=("mrudloff-hap-server" "mrudloff-hap-web1" "mrudloff-hap-web2")

# Declare global variables for public DNS names to ensure they're available for all parts of the script
HAP_SERVER_PUBLIC_DNS=""
HAP_WEB1_PUBLIC_DNS=""
HAP_WEB2_PUBLIC_DNS=""

# Retrieve the public DNS names of the running instances
for INSTANCE_NAME in "${INSTANCE_NAMES[@]}"; do
    INSTANCE_DETAILS=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=running" --query 'Reservations[*].Instances[*].[PublicDnsName]' --output text)
    if [ "$INSTANCE_NAME" == "mrudloff-hap-server" ]; then
        HAP_SERVER_PUBLIC_DNS=$INSTANCE_DETAILS
    elif [ "$INSTANCE_NAME" == "mrudloff-hap-web1" ]; then
        HAP_WEB1_PUBLIC_DNS=$INSTANCE_DETAILS 
    elif [ "$INSTANCE_NAME" == "mrudloff-hap-web2" ]; then
        HAP_WEB2_PUBLIC_DNS=$INSTANCE_DETAILS   
    fi
done  

# Configure Ansible HAP hosts
configure_hap_hosts() {
    echo "Configuring Ansible hosts file..."

    # Check and delete existing hosts file
    if [ -f "$hap_config_path/ansiblehosts" ]; then
        rm $hap_config_path/ansiblehosts
    fi

    # Create hosts file
    cat << EOF > $hap_config_path/ansiblehosts
[hapserver]
mrudloff-hap-server ansible_host=$HAP_SERVER_PUBLIC_DNS ansible_user=ubuntu ansible_ssh_private_key_file=/Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem

[hapweb1]
mrudloff-hap-web1 ansible_host=$HAP_WEB1_PUBLIC_DNS ansible_user=ubuntu ansible_ssh_private_key_file=/Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem

[hapweb2]
mrudloff-hap-web2 ansible_host=$HAP_WEB2_PUBLIC_DNS ansible_user=ubuntu ansible_ssh_private_key_file=/Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem

EOF
}  

# Configure haproxy.cfg
configure_hap_config() {
    echo "Configuring haproxy.cfg ..."

    # Check and delete existing haproxy.cfg file
    if [ -f "$hap_config_path/haproxy.cfg" ]; then
        rm $hap_config_path/haproxy.cfg
    fi

    # Create haproxy.cfg file
    cat << EOF > $hap_config_path/haproxy.cfg
global
	log /dev/log	local0
	log /dev/log	local1 notice
	chroot /var/lib/haproxy
	stats socket /run/haproxy/admin.sock mode 660 level admin
	stats timeout 30s
	user haproxy
	group haproxy
	daemon

	# Default SSL material locations
    ca-base /etc/haproxy/certs
    crt-base /etc/haproxy/certs

	# See: https://ssl-config.mozilla.org/#server=haproxy&server-version=2.0.3&config=intermediate
        ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384
        ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
        ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets

defaults
	log	global
	mode	http
	option	httplog
	option	dontlognull
        timeout connect 5000
        timeout client  50000
        timeout server  50000
	errorfile 400 /etc/haproxy/errors/400.http
	errorfile 403 /etc/haproxy/errors/403.http
	errorfile 408 /etc/haproxy/errors/408.http
	errorfile 500 /etc/haproxy/errors/500.http
	errorfile 502 /etc/haproxy/errors/502.http
	errorfile 503 /etc/haproxy/errors/503.http
	errorfile 504 /etc/haproxy/errors/504.http


frontend fe_main
    bind *:80
    bind *:443 ssl crt /etc/haproxy/certs/hap-apache-selfsigned.pem
    mode http
    redirect scheme https code 301 if !{ ssl_fc }
    default_backend be_app

backend be_app
    balance roundrobin
    server hap_web1 $HAP_WEB1_PRIVATE_IP:80 check
    server hap_web2 $HAP_WEB2_PRIVATE_IP:80 check
EOF
}  

# Call the functions
configure_hap_config

#Prompt the user for the domain name
read -p "Domain used for the certificate used for the HAP Web clients? " hap_domain_name


# Configure Apache templates
configure_hap_apache_templates() {
    echo "Configuring Apache templates..."

    # Create templates directory if it doesn't exist
    mkdir -p $hap_templates_path

    # Check and delete existing apache-ssl.conf.j2 file
    if [ -f "$hap_templates_path/hap-apache-http.conf.j2" ]; then
        rm $hap_templates_path/hap-apache-http.conf.j2
    fi

    # Create Ansible Client apache-ssl.conf.j2 file
    cat << EOF > $hap_templates_path/hap-apache-http.conf.j2
<VirtualHost *:80>
    ServerName $hap_domain_name
    #ServerName $HAP_SERVER_PUBLIC_DNS
    DocumentRoot /var/www/html
</VirtualHost>
EOF
}

# Create Puppet Client self-signed certificates
create_hap_selfsigned_certificates() {
    echo "Creating self-signed certificates..."

    # Create certs directory if it doesn't exist
    mkdir -p $hap_certs_path

    # Create self-signed certificates for Ansible client apache server
    openssl req -x509 -newkey rsa:4096 -keyout $hap_certs_path/hap-apache-selfsigned-key.pem -out $hap_certs_path/hap-apache-selfsigned-cer.pem -days 365 -nodes -subj "/C=GB/ST=Cambs/L=Ely/O=Digicert/OU=Product/CN=$hap_domain_name/emailAddress=michael.rudloff@digicert.com" 
    cat $hap_certs_path/hap-apache-selfsigned-cer.pem $hap_certs_path/hap-apache-selfsigned-key.pem > $hap_certs_path/hap-apache-selfsigned.pem
}



# Configure Ansible playbook
configure_ansible_playbook() {
    echo "Configuring Ansible playbook..."

    # Check and delete existing playbook file
    if [ -f "$hap_config_path/ansible_server.yml" ]; then
        rm $hap_config_path/ansible_server.yml
    fi

    # Create playbook file
    cat << EOF > $hap_config_path/ansible_server.yml
---
- hosts: all
  become: yes
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: /Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem
  tasks:
    - name: Update apt cache
      apt:
        update_cache: yes

    - name: Install build-essential package
      apt:
        name: build-essential
        state: present
    - name: Upgrade packages
      apt:
        upgrade: yes  

- hosts: hapweb1, hapweb2
  become: yes
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: /Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem
    apache_server_name: $hap_domain_name
    #apache_server_name: $HAP_SERVER_PUBLIC_DNS
    apache_document_root: /var/www/html  
  tasks:
    - name: Install Apache
      apt:
        name: apache2
        state: latest
   
    - name: Configure Apache2 for HTTP
      template:
        src: $hap_templates_path/hap-apache-http.conf.j2
        dest: /etc/apache2/sites-available/default.conf
      notify: Restart Apache2

    - name: Enable Apache2 default virtual host
      command: a2ensite default

  handlers:
    - name: Restart Apache2
      service:
        name: apache2
        state: restarted

    - name: Ensure old index.html is removed
      file:
        path: /var/www/html/index.html
        state: absent    

- hosts: hapweb1
  become: yes
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: /Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem
    apache_server_name: $hap_domain_name
    #apache_server_name: $HAP_SERVER_PUBLIC_DNS
    apache_document_root: /var/www/html  
  tasks:
    - name: Copy new index.html to remote server
      copy:
        src: "$hap_templates_path/web1/{{ item }}"
        dest: "/var/www/html/{{ item }}"
      with_items:
        - index.html

- hosts: hapweb2
  become: yes
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: /Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem
    apache_server_name: $hap_domain_name
    #apache_server_name: $HAP_SERVER_PUBLIC_DNS
    apache_document_root: /var/www/html  
  tasks:
    - name: Copy new index.html to remote server
      copy:
        src: "$hap_templates_path/web2/{{ item }}"
        dest: "/var/www/html/{{ item }}"
      with_items:
        - index.html

- hosts: hapserver
  become: yes
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: /Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem 
  tasks:
    - name: Add HAProxy PPA
      apt_repository:
        repo: ppa:vbernat/haproxy-2.8
        state: present

    - name: Update apt cache
      apt:
        update_cache: yes
    
    - name: Install HAProxy and socat
      apt:
        name:
          - haproxy=2.8.*
          - socat
        state: present
    
    - name: Create directory for HAProxy certificates
      file:
        path: /etc/haproxy/certs
        state: directory
        owner: haproxy
        group: haproxy
        mode: '0770'

    - name: Copy certificate to remote server
      copy:
        src: "$hap_certs_path/{{ item }}"
        dest: "/etc/haproxy/certs/{{ item }}"
      with_items:
        - hap-apache-selfsigned.pem

    - name: Ensure old haproxy.cfg is removed
      file:
        path: /etc/haproxy/haproxy.cfg
        state: absent   

    - name: Copy new haproxy.cfg and acme files to remote server
      copy:
        src: "$hap_config_path/{{ item }}"
        dest: "/etc/haproxy/{{ item }}"
        mode: "u+x,g+x,o+x"
      with_items:
        - haproxy.cfg
        - 01-haproxy.sh
        - 02-haproxy.sh
        - 03-haproxy.sh

    - name: wait and restart haproxy
      pause:
        minutes: 1
      notify: restart haproxy

    - name: restart haproxy
      service:
        name: haproxy
        state: restarted

EOF
}

# Call the functions
configure_hap_hosts 
configure_hap_apache_templates
create_hap_selfsigned_certificates
configure_ansible_playbook

# Running Playbook
export ANSIBLE_HOST_KEY_CHECKING=False
ansible-playbook -i $hap_config_path/ansiblehosts $hap_config_path/ansible_server.yml

  exit
}




menu_option_five() {
# AWS EKS Cluster + Istio
AWS_ACCESS_KEY_ID=$(security find-generic-password -a $USER -s AWS_ACCESS_KEY_ID -w aws.secrets)
AWS_SECRET_ACCESS_KEY=$(security find-generic-password -a $USER -s AWS_SECRET_ACCESS_KEY -w aws.secrets)
AWS_DEFAULT_REGION=$(security find-generic-password -a $USER -s AWS_DEFAULT_REGION -w aws.secrets)

# Run aws configure with the provided values
aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID"
aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY"
aws configure set default.region "$AWS_DEFAULT_REGION"

# Set AWS region
AWS_REGION=$(security find-generic-password -a $USER -s AWS_DEFAULT_REGION -w aws.secrets)

# Create EKS 
eksctl create cluster -f /Users/michaelrudloff/Dropbox/vscode/ekscluster-config.yaml  

# Set Context to new EKS Cluster
aws eks --region $AWS_REGION update-kubeconfig --name mrudloff-istio-lab

# Deploy Cert Manager
 #kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.5/cert-manager.yaml
# duration=600
# while [ $duration -gt 0 ]; do
#     printf "\rInstalling Cert-Manager - ready in %02d seconds ..." $duration
#     sleep 1
#     ((duration--))
# done
# # Create istio Namespace
#kubectl create namespace istio-system
# duration=5
# while [ $duration -gt 0 ]; do
#     printf "\rCreate istio namespace - ready in %02d seconds ..." $duration
#     sleep 1
#     ((duration--))
# done
# # Add ACME Secret
#kubectl create secret generic digicert-acme-hmac --from-literal secret=OWQ0MDEyYjA1YWNjZDI3MTE4ZDAwNTFkYzliYTFjMjY1OTllMzdiMGJkNjJhYzA1ZjAxYWIyMmIxMmEwZjljYQ -n istio-system
# duration=5
# while [ $duration -gt 0 ]; do
#     printf "\rCreate ACME secret - ready in %02d seconds ..." $duration
#     sleep 1
#     ((duration--))
# done
# # Deploy Issuer
#kubectl apply -f issuer.yaml
# duration=5
# while [ $duration -gt 0 ]; do
#     printf "\rCreate Issuer - ready in %02d seconds ..." $duration
#     sleep 1
#     ((duration--))
# done
# # Create Secret with Root CA
#kubectl create secret generic -n cert-manager istio-root-ca --from-file=ca.pem=ca.pem
# duration=
# while [ $duration -gt 0 ]; do
#     printf "\rCreate root ca secret - ready in %02d seconds ..." $duration
#     sleep 1
#     ((duration--))
# done
# # Deploy istio-csr
#helm repo add jetstack https://charts.jetstack.io
#helm repo update
#helm install -n cert-manager cert-manager-istio-csr jetstack/cert-manager-istio-csr \
# 	--set "app.certmanager.issuer.name=digicert-acme-issuer" \
# 	--set "app.tls.rootCAFile=/var/run/secrets/istio-csr/ca.pem" \
# 	--set "volumeMounts[0].name=root-ca" \
# 	--set "volumeMounts[0].mountPath=/var/run/secrets/istio-csr" \
# 	--set "volumes[0].name=root-ca" \
# 	--set "volumes[0].secret.secretName=istio-root-ca"
# duration=20
# while [ $duration -gt 0 ]; do
#     printf "\rInstall istio-csr - ready in %02d seconds ..." $duration
#     sleep 1
#     ((duration--))
# done
# # Deploy Istio
#curl -sSL https://raw.githubusercontent.com/cert-manager/website/7f5b2be9dd67831574b9bde2407bed4a920b691c/content/docs/tutorials/istio-csr/example/istio-config-getting-started.yaml > istio-install-config.yaml
#istioctl install -f istio-install-config.yaml
# duration=600
# while [ $duration -gt 0 ]; do
#     printf "\rInstall istio - ready in %02d seconds ..." $duration
#     sleep 1
#     ((duration--))
# done
# # Set testing environment variables
#export NAMESPACE=default
#export APP=productpage
#export ISTIO_VERSION=$(istioctl version -o json | jq -r '.meshVersion[0].Info.version')
# duration=5
# while [ $duration -gt 0 ]; do
#     printf "\rSet environment variables - ready in %02d seconds ..." $duration
#     sleep 1
#     ((duration--))
# done
# # Inject default namespace to enable mtls
#kubectl label namespace $NAMESPACE istio-injection=enabled --overwrite
# duration=5
# while [ $duration -gt 0 ]; do
#     printf "\rInject namespace for mtls - ready in %02d seconds ..." $duration
#     sleep 1
#     ((duration--))
# done
# Deploy Testing Application 'bookinfo'
#kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.21/samples/bookinfo/platform/kube/bookinfo.yaml
#duration=60
#while [ $duration -gt 0 ]; do
#    printf "\rDeploy Testing App - Bookinfo - ready in %02d seconds ..." $duration
#    sleep 1
#    ((duration--))
#done
# Check certificates of 'bookinfo'
#kubectl get pods -o jsonpath='{range.items[*]}{.metadata.name}{"\n"}{end}' | xargs -I{} sh -c 'echo "Pod: {}"; istioctl proxy-config secret {} ; echo'

#/Users/michaelrudloff/.ssh/ansible_files/kubeconfig.sh
exit
}


menu_option_six() {

#!/bin/bash

AWS_ACCESS_KEY_ID=$(security find-generic-password -a $USER -s AWS_ACCESS_KEY_ID -w aws.secrets)
AWS_SECRET_ACCESS_KEY=$(security find-generic-password -a $USER -s AWS_SECRET_ACCESS_KEY -w aws.secrets)
AWS_DEFAULT_REGION=$(security find-generic-password -a $USER -s AWS_DEFAULT_REGION -w aws.secrets)

# Run aws configure with the provided values
aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID"
aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY"
aws configure set default.region "$AWS_DEFAULT_REGION"

# Set AWS region
AWS_REGION=$(security find-generic-password -a $USER -s AWS_DEFAULT_REGION -w aws.secrets)

# Set instance configurations
INSTANCE_TYPE="t2.medium"
KEY_NAME="mrudloff-keypair"
SECURITY_GROUP_ID="sg-09dae9711b0b7e305"
VPC_ID="vpc-3409ac5f"
SUBNET_ID="subnet-2d915d46"

# Prompt the user to choose the AMI
clear
echo "Which AMI would you like to deploy?"
echo "1. Ubuntu 24.04"
echo "2. Ubuntu 22.04"
echo "3. Ubuntu 18.04"
read -p "Enter your choice (1,2  or 3): " choice

# Set the AMI_ID based on the user's choice
case $choice in 
  1)
    AMI_ID="ami-09040d770ffe2224f"
    echo "Selected AMI: Ubuntu 24.04"
    ;;
  2)
    AMI_ID="ami-0b8b44ec9a8f90422"
    echo "Selected AMI: Ubuntu 22.04"
    ;;
  3)
    AMI_ID="ami-0e4c27be5484b93d6"
    echo "Selected AMI: Ubuntu 18.04"
    ;;
  *)
    echo "Invalid choice. Defaulting to Ubuntu 22.04."
    AMI_ID="ami-0e4c27be5484b93d6"
    ;;
esac

# Ubuntu Specific Path Variables
ubuntu_automation_path=/Users/michaelrudloff/Dropbox/vscode/ubuntu_automation
ubuntu_automation_apache_path=/Users/michaelrudloff/Dropbox/vscode/ubuntu_automation/apache
ubuntu_automation_apache_template_path=/Users/michaelrudloff/Dropbox/vscode/ubuntu_automation/apache/templates
ubuntu_key_file="/Users/michaelrudloff/Dropbox/vscode/key"
ubuntu_automation_tlmfiles_path="/Users/michaelrudloff/Dropbox/vscode/ubuntu_automation/tlmfiles"

# Create the Ubuntu server ec2 instances
UBUNTU_SERVER_INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SECURITY_GROUP_ID" \
    --subnet-id "$SUBNET_ID" \
    --associate-public-ip-address \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=mrudloff-ubuntu-server}]' \
    --query 'Instances[0].InstanceId' \
    --output text \
    --region "$AWS_REGION")

echo "Ubuntu Server is being created. Please wait..."
echo 
echo "The server will consist of the following:"
echo "1. Ubuntu Server"
echo "2. NO Apache Web Server"
echo "3. NO Self-Signed TLS"
echo "4. NO TLM Agent"
echo
#echo "The Puppet Client will have Apache with self-signed TLS installed and configured"
#echo
echo "mrudloff-ubuntu-server instance ID: $UBUNTU_SERVER_INSTANCE_ID"


# Get the public DNS and private IP addresses of the Puppet ec2 instances
UBUNTU_SERVER_PUBLIC_DNS=$(aws ec2 describe-instances \
    --instance-ids "$UBUNTU_SERVER_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicDnsName' \
    --output text \
    --region "$AWS_REGION")
UBUNTU_SERVER_PRIVATE_IP=$(aws ec2 describe-instances \
    --instance-ids "$UBUNTU_SERVER_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' \
    --output text \
    --region "$AWS_REGION")

echo
echo "The following ec2 instance has been created:"
echo
echo "Host: mrudloff-ubuntu-server"
echo "Public DNS: $UBUNTU_SERVER_PUBLIC_DNS"
echo "Private IP: $UBUNTU_SERVER_PRIVATE_IP"

# Get instance IDs of the newly created Ubuntu instance
UBUNTU_SERVER_INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=mrudloff-ubuntu-server" "Name=instance-state-name,Values=running" --query "Reservations[*].Instances[*].[InstanceId]" --output text --region "$AWS_REGION")

# Declare array of Ubuntu instance IDs
INSTANCE_IDS=("$UBUNTU_SERVER_INSTANCE_ID" )

# Wait for 3 minutes to give the Ubuntu instances some time to initialize
echo
duration=180
while [ $duration -gt 0 ]; do
    printf "\rWaiting %02d seconds for Ubuntu instance to initialize before checking again..." $duration
    sleep 1
    ((duration--))
done

# Wait for each Ubuntu instance to pass status checks
for INSTANCE_ID in "${INSTANCE_IDS[@]}"; do
    INSTANCE_STATUS=""
    while [ -z "$INSTANCE_STATUS" ] || [ "$INSTANCE_STATUS" != "ok" ]; do
        echo 
        echo "Checking status of ec2 instances"
        INSTANCE_STATUS=$(aws ec2 describe-instance-status --instance-ids $INSTANCE_ID --query 'InstanceStatuses[0].InstanceStatus.Status' --output text)
        echo "Instance status: $INSTANCE_STATUS"
        INSTANCE_STATUS=$(aws ec2 describe-instance-status --instance-ids $INSTANCE_ID --query 'InstanceStatuses[0].InstanceStatus.Status' --output text)
        if [ -z "$INSTANCE_STATUS" ] || [ "$INSTANCE_STATUS" != "ok" ]; then
            echo
            duration2=15
            while [ $duration2 -gt 0 ]; do
            printf "\rInstances are not ready yet. Waiting for %02d seconds before checking again." $duration2
            sleep 1
            ((duration2--))
            done
        fi
    done
done
echo
echo "The instance has passed status checks and is ready to use."

# Ensure SSH Keys are being accepted / skipped
export ANSIBLE_HOST_KEY_CHECKING=False

# Create Ansible Configuration and Playbook
echo 
echo "Creating Ansible Configuration and Playbook"

# Define the instance names before attempting to retrieve their IPs
INSTANCE_NAMES=("mrudloff-ubuntu-server")

# Declare global variables for public DNS names to ensure they're available for all parts of the script
UBUNTU_SERVER_PUBLIC_DNS=""
UBUNTU_CLIENT_PUBLIC_DNS=""

# Retrieve the public DNS names of the running instances
for INSTANCE_NAME in "${INSTANCE_NAMES[@]}"; do
    INSTANCE_DETAILS=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=running" --query 'Reservations[*].Instances[*].[PublicDnsName]' --output text)
    if [ "$INSTANCE_NAME" == "mrudloff-ubuntu-server" ]; then
        UBUNTU_SERVER_PUBLIC_DNS=$INSTANCE_DETAILS
    fi
done


exit
}

menu_option_seven() {

#!/bin/bash

AWS_ACCESS_KEY_ID=$(security find-generic-password -a $USER -s AWS_ACCESS_KEY_ID -w aws.secrets)
AWS_SECRET_ACCESS_KEY=$(security find-generic-password -a $USER -s AWS_SECRET_ACCESS_KEY -w aws.secrets)
AWS_DEFAULT_REGION=$(security find-generic-password -a $USER -s AWS_DEFAULT_REGION -w aws.secrets)

# Run aws configure with the provided values
aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID"
aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY"
aws configure set default.region "$AWS_DEFAULT_REGION"

# Set AWS region
AWS_REGION=$(security find-generic-password -a $USER -s AWS_DEFAULT_REGION -w aws.secrets)

# Set instance configurations
INSTANCE_TYPE="t2.medium"
KEY_NAME="mrudloff-keypair"
SECURITY_GROUP_ID="sg-09dae9711b0b7e305"
VPC_ID="vpc-3409ac5f"
SUBNET_ID="subnet-2d915d46"

# Prompt the user to choose the AMI
clear
echo "Which AMI would you like to deploy?"
echo "1. Ubuntu 24.04 (not supported yet)"
echo "2. Ubuntu 22.04 (use THIS ONE)"
echo "3. Ubuntu 18.04 (not supported yet)"
read -p "Enter your choice (1,2  or 3): " choice

# Set the AMI_ID based on the user's choice
case $choice in 
  1)
    AMI_ID="ami-09040d770ffe2224f"
    echo "Selected AMI: Ubuntu 24.04"
    ;;
  2)
    AMI_ID="ami-0b8b44ec9a8f90422"
    echo "Selected AMI: Ubuntu 22.04"
    ;;
  3)
    AMI_ID="ami-0e4c27be5484b93d6"
    echo "Selected AMI: Ubuntu 18.04"
    ;;
  *)
    echo "Invalid choice. Defaulting to Ubuntu 22.04."
    AMI_ID="ami-0e4c27be5484b93d6"
    ;;
esac

exit
}

menu_option_eight() {

#!/bin/bash

AWS_ACCESS_KEY_ID=$(security find-generic-password -a $USER -s AWS_ACCESS_KEY_ID -w aws.secrets)
AWS_SECRET_ACCESS_KEY=$(security find-generic-password -a $USER -s AWS_SECRET_ACCESS_KEY -w aws.secrets)
AWS_DEFAULT_REGION=$(security find-generic-password -a $USER -s AWS_DEFAULT_REGION -w aws.secrets)

# Run aws configure with the provided values
aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID"
aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY"
aws configure set default.region "$AWS_DEFAULT_REGION"

# Set AWS region
AWS_REGION=$(security find-generic-password -a $USER -s AWS_DEFAULT_REGION -w aws.secrets)

# Set instance configurations
INSTANCE_TYPE="t2.medium"
KEY_NAME="mrudloff-keypair"
SECURITY_GROUP_ID="sg-09dae9711b0b7e305"
VPC_ID="vpc-3409ac5f"
SUBNET_ID="subnet-2d915d46"

# Prompt the user to choose the AMI
clear
echo "Which AMI would you like to deploy?"
echo "1. Ubuntu 24.04"
echo "2. Ubuntu 22.04"
echo "3. Ubuntu 18.04"
read -p "Enter your choice (1,2  or 3): " choice

# Set the AMI_ID based on the user's choice
case $choice in 
  1)
    AMI_ID="ami-09040d770ffe2224f"
    echo "Selected AMI: Ubuntu 24.04"
    ;;
  2)
    AMI_ID="ami-0b8b44ec9a8f90422"
    echo "Selected AMI: Ubuntu 22.04"
    ;;
  3)
    AMI_ID="ami-0e4c27be5484b93d6"
    echo "Selected AMI: Ubuntu 18.04"
    ;;
  *)
    echo "Invalid choice. Defaulting to Ubuntu 22.04."
    AMI_ID="ami-0e4c27be5484b93d6"
    ;;
esac

# Ubuntu Specific Path Variables
ubuntu_automation_path=/Users/michaelrudloff/Dropbox/vscode/ubuntu_automation
ubuntu_automation_apache_path=/Users/michaelrudloff/Dropbox/vscode/ubuntu_automation/apache
ubuntu_automation_apache_template_path=/Users/michaelrudloff/Dropbox/vscode/ubuntu_automation/apache/templates
ubuntu_key_file="/Users/michaelrudloff/Dropbox/vscode/key"
ubuntu_automation_tlmfiles_path="/Users/michaelrudloff/Dropbox/vscode/ubuntu_automation/tlmfiles"

# Create the Ubuntu server ec2 instances
UBUNTU_SERVER_INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SECURITY_GROUP_ID" \
    --subnet-id "$SUBNET_ID" \
    --associate-public-ip-address \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=mrudloff-ubuntu-server}]' \
    --query 'Instances[0].InstanceId' \
    --output text \
    --region "$AWS_REGION")

echo "Ubuntu Server is being created. Please wait..."
echo 
echo "The server will consist of the following:"
echo "1. Ubuntu Server"
echo "2. Apache Web Server"
echo "3. Self-Signed TLS"
echo "4. TLM Agent"
echo
#echo "The Puppet Client will have Apache with self-signed TLS installed and configured"
#echo
echo "mrudloff-ubuntu-server instance ID: $UBUNTU_SERVER_INSTANCE_ID"


# Get the public DNS and private IP addresses of the Puppet ec2 instances
UBUNTU_SERVER_PUBLIC_DNS=$(aws ec2 describe-instances \
    --instance-ids "$UBUNTU_SERVER_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicDnsName' \
    --output text \
    --region "$AWS_REGION")
UBUNTU_SERVER_PRIVATE_IP=$(aws ec2 describe-instances \
    --instance-ids "$UBUNTU_SERVER_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' \
    --output text \
    --region "$AWS_REGION")

echo
echo "The following ec2 instance has been created:"
echo
echo "Host: mrudloff-ubuntu-server"
echo "Public DNS: $UBUNTU_SERVER_PUBLIC_DNS"
echo "Private IP: $UBUNTU_SERVER_PRIVATE_IP"

# Get instance IDs of the newly created Ubuntu instance
UBUNTU_SERVER_INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=mrudloff-ubuntu-server" "Name=instance-state-name,Values=running" --query "Reservations[*].Instances[*].[InstanceId]" --output text --region "$AWS_REGION")

# Declare array of Ubuntu instance IDs
INSTANCE_IDS=("$UBUNTU_SERVER_INSTANCE_ID" )

# Wait for 3 minutes to give the Ubuntu instances some time to initialize
echo
duration=180
while [ $duration -gt 0 ]; do
    printf "\rWaiting %02d seconds for Ubuntu instance to initialize before checking again..." $duration
    sleep 1
    ((duration--))
done

# Wait for each Ubuntu instance to pass status checks
for INSTANCE_ID in "${INSTANCE_IDS[@]}"; do
    INSTANCE_STATUS=""
    while [ -z "$INSTANCE_STATUS" ] || [ "$INSTANCE_STATUS" != "ok" ]; do
        echo 
        echo "Checking status of ec2 instances"
        INSTANCE_STATUS=$(aws ec2 describe-instance-status --instance-ids $INSTANCE_ID --query 'InstanceStatuses[0].InstanceStatus.Status' --output text)
        echo "Instance status: $INSTANCE_STATUS"
        INSTANCE_STATUS=$(aws ec2 describe-instance-status --instance-ids $INSTANCE_ID --query 'InstanceStatuses[0].InstanceStatus.Status' --output text)
        if [ -z "$INSTANCE_STATUS" ] || [ "$INSTANCE_STATUS" != "ok" ]; then
            echo
            duration2=15
            while [ $duration2 -gt 0 ]; do
            printf "\rInstances are not ready yet. Waiting for %02d seconds before checking again." $duration2
            sleep 1
            ((duration2--))
            done
        fi
    done
done
echo
echo "The instance has passed status checks and is ready to use."

# Ensure SSH Keys are being accepted / skipped
export ANSIBLE_HOST_KEY_CHECKING=False

# Create Ansible Configuration and Playbook
echo 
echo "Creating Ansible Configuration and Playbook"

# Define the instance names before attempting to retrieve their IPs
INSTANCE_NAMES=("mrudloff-ubuntu-server")

# Declare global variables for public DNS names to ensure they're available for all parts of the script
UBUNTU_SERVER_PUBLIC_DNS=""
UBUNTU_CLIENT_PUBLIC_DNS=""

# Retrieve the public DNS names of the running instances
for INSTANCE_NAME in "${INSTANCE_NAMES[@]}"; do
    INSTANCE_DETAILS=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=running" --query 'Reservations[*].Instances[*].[PublicDnsName]' --output text)
    if [ "$INSTANCE_NAME" == "mrudloff-ubuntu-server" ]; then
        UBUNTU_SERVER_PUBLIC_DNS=$INSTANCE_DETAILS
    fi
done

# Configure Ansible host
configure_ansible_hosts() {
    echo 
    echo "Configuring Ansible hosts file ubuntuhosts to deploy Ubuntu with Apache..."

    # Check and delete existing hosts file
    if [ -f "$ubuntu_automation_path/ubuntuhosts" ]; then
        rm $ubuntu_automation_path/ubuntuhosts
    fi

    # Create hosts file
    cat << EOF > $ubuntu_automation_path/ubuntuhosts
[ubuntuserver]
mrudloff-ubuntu-server ansible_host=$UBUNTU_SERVER_PUBLIC_DNS ansible_user=ubuntu ansible_ssh_private_key_file=$ubuntu_key_file/aws_keypair.pem ansible_ssh_common_args='-o StrictHostKeyChecking=no'
                                    
EOF
}

# Prompt the user for the domain name
 read -p "Domain used for Apache and the Certificate? " domain_name

# Configure Apache templates
configure_apache_templates() {
    echo "Configuring Apache templates..."

    # Create templates directory if it doesn't exist
    mkdir -p $ubuntu_automation_apache_template_path

    # Check and delete existing apache-redirect.conf.j2 file
    if [ -f "$ubuntu_automation_apache_template_path/ubuntu-apache-redirect.conf.j2" ]; then
        rm $ubuntu_automation_apache_template_path/ubuntu-apache-redirect.conf.j2
    fi

    # Create Puppet Client apache-redirect.conf.j2 file
    cat << EOF > $ubuntu_automation_apache_template_path/ubuntu-apache-redirect.conf.j2
<VirtualHost *:80>
    ServerName $domain_name
    Redirect permanent / https://$domain_name/
</VirtualHost>
EOF
}

    # Check and delete existing apache-ssl.conf.j2 file
    if [ -f "$ubuntu_automation_apache_template_path/ubuntu-apache-ssl.conf.j2" ]; then
        rm $ubuntu_automation_apache_template_path/ubuntu-apache-ssl.conf.j2
    fi

    # Create apache-ssl.conf.j2 file
    cat << EOF > $ubuntu_automation_apache_template_path/ubuntu-apache-ssl.conf.j2
<VirtualHost *:443>
    ServerName $domain_name
    DocumentRoot /var/www/html
    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/ubuntu-apache-selfsigned.crt
    SSLCertificateKeyFile /etc/ssl/private/ubuntu-apache-selfsigned.key
</VirtualHost>
EOF


BUSINESS_UNIT_ID=542bce5b-9a54-41df-a054-fe977133ee09
AGENT_BUNDLE_NAME=tlm_agent_3.0.11_linux64.tar.gz
ALIASNAME=$domain_name
PROXY=''

# Create Puppet Client self-signed certificates
create_selfsigned_certificates() {
    echo "Creating self-signed certificates..."

    # Create certs directory if it doesn't exist
    mkdir -p $ubuntu_automation_apache_path

    # Create self-signed certificates for puppet client apache server
    openssl req -x509 -newkey rsa:4096 -keyout $ubuntu_automation_apache_path/ubuntu-apache-selfsigned.key -out $ubuntu_automation_apache_path/ubuntu-apache-selfsigned.crt -days 365 -nodes -subj "/C=GB/ST=Cambs/L=Ely/O=Digicert/OU=Product/CN=$domain_name/emailAddress=michael.rudloff@digicert.com" 
}

# Configure Puppet playbook
configure_ansible_playbook() {
    echo "Configuring Ansible playbook..."

    # Check and delete existing playbook file
    if [ -f "$ubuntu_automation_path/ubuntu_server.yml" ]; then
        rm $ubuntu_automation_path/ubuntu_server.yml
    fi

    # Create playbook file
    cat << EOF > $ubuntu_automation_path/ubuntu_server.yml
---
- hosts: all
  become: yes
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: /Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem
  tasks:

    - name: Update apt cache
      apt:
        update_cache: yes

    - name: Install build-essential package
      apt:
        name: build-essential
        state: present

    - name: Install certbot
      apt:
        name: certbot
        state: present

    - name: Install certbot and apache plugin
      apt:
        name: python3-certbot-apache
        state: present        

    - name: Upgrade packages
      apt:
        upgrade: yes  
 
    - name: Copy tlm files to remote server
      copy:
        src: "$ubuntu_automation_tlmfiles_path/{{ item }}"
        dest: "/home/ubuntu/{{ item }}"
      with_items:
        - DigiCertTLMAgentGPOInstaller.tar.gz

- hosts: ubuntuserver
  become: yes
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: /Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem
    apache_server_name: $domain_name
    apache_document_root: /var/www/html  
  tasks:
    - name: Install Apache
      apt:
        name: apache2
        state: latest
    - name: Create /etc/ssl/private/ directory
      file:
        path: /etc/ssl/private/
        state: directory
        owner: root
        group: root
        mode: '0700'

    - name: Create /etc/ssl/certs/ directory
      file:
        path: /etc/ssl/certs/
        state: directory
        owner: root
        group: root
        mode: '0755'

    - name: Copy files to remote server
      copy:
        src: "$ubuntu_automation_apache_path/{{ item }}"
        dest: "/etc/ssl/private/{{ item }}"
      with_items:
        - ubuntu-apache-selfsigned.key

    - name: Copy files to remote server
      copy:
        src: "$ubuntu_automation_apache_path/{{ item }}"
        dest: "/etc/ssl/certs/{{ item }}"
      with_items:
        - ubuntu-apache-selfsigned.crt

    - name: Enable Apache2 modules
      apache2_module:
        name: "{{ item }}"
        state: present
      loop:
        - ssl
        - rewrite
   
    - name: Configure Apache2 for HTTPS
      template:
        src: $ubuntu_automation_apache_template_path/ubuntu-apache-ssl.conf.j2
        dest: /etc/apache2/sites-available/default-ssl.conf
      notify: Restart Apache2

    - name: Enable Apache2 default SSL virtual host
      command: a2ensite default-ssl

    - name: Configure Apache2 to redirect HTTP to HTTPS
      template:
        src: $ubuntu_automation_apache_template_path/ubuntu-apache-redirect.conf.j2
        dest: /etc/apache2/sites-available/000-default.conf
      notify: Restart Apache2


  handlers:
    - name: Restart Apache2
      service:
        name: apache2
        state: restarted

- hosts: ubuntuserver
  become: yes
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: /Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem    
  tasks:
    - name: "Ensure the destination directory exists"
      ansible.builtin.file:
        path: /opt/digicert
        state: directory
        mode: '0755'
      become: yes
    - name: "Extracting the tar on the remote machine"
      ansible.builtin.unarchive:
        src: /home/ubuntu/DigiCertTLMAgentGPOInstaller.tar.gz
        dest: /opt/digicert
        remote_src: yes
        creates: /opt/digicert/DigiCertTLMAgentGPOInstaller/extracted_file_or_directory  # Use this to avoid re-extraction if the operation has already been done
      become: yes

    - name: "Making the script executable"
      ansible.builtin.file:
        path: /opt/digicert/DigiCertTLMAgentGPOInstaller/silentInstaller-by-companion-lnx.sh
        mode: '0755'
        state: file
      become: yes

    - name: "Executing the script on the remote machine"
      ansible.builtin.shell:
        cmd: "/opt/digicert/DigiCertTLMAgentGPOInstaller/silentInstaller-by-companion-lnx.sh AGENT_BUNDLE_NAME=$AGENT_BUNDLE_NAME BUSINESS_UNIT_ID=$BUSINESS_UNIT_ID ALIASNAME=$ALIASNAME PROXY=$PROXY"
        executable: /bin/bash
      become: yes

      

EOF
}

# Call the functions
configure_ansible_hosts
configure_apache_templates
create_selfsigned_certificates
configure_ansible_playbook

# Running Playbook
export ANSIBLE_HOST_KEY_CHECKING=False
ansible-playbook -i $ubuntu_automation_path/ubuntuhosts $ubuntu_automation_path/ubuntu_server.yml

# Prompt the user
read -p "Connect to server via SSH ? (yes/no): " user_input
user_input=$(echo "$user_input" | tr '[:upper:]' '[:lower:]')

# Check the user input and proceed accordingly
if [[ "$user_input" == "yes" || "$user_input" == "y" ]]; then
    echo "Connecting to the server..."
ssh -i /Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem ubuntu@$UBUNTU_SERVER_PUBLIC_DNS -o StrictHostKeyChecking=no
else
    echo "Connection cancelled."
fi
exit
}

menu_option_nine() {

#!/bin/bash

AWS_ACCESS_KEY_ID=$(security find-generic-password -a $USER -s AWS_ACCESS_KEY_ID -w aws.secrets)
AWS_SECRET_ACCESS_KEY=$(security find-generic-password -a $USER -s AWS_SECRET_ACCESS_KEY -w aws.secrets)
AWS_DEFAULT_REGION=$(security find-generic-password -a $USER -s AWS_DEFAULT_REGION -w aws.secrets)

# Run aws configure with the provided values
aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID"
aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY"
aws configure set default.region "$AWS_DEFAULT_REGION"

# Set AWS region
AWS_REGION=$(security find-generic-password -a $USER -s AWS_DEFAULT_REGION -w aws.secrets)

# Set instance configurations
INSTANCE_TYPE="t2.medium"
KEY_NAME="mrudloff-keypair"
SECURITY_GROUP_ID="sg-09dae9711b0b7e305"
VPC_ID="vpc-3409ac5f"
SUBNET_ID="subnet-2d915d46"

# Prompt the user to choose the AMI
clear
echo "Which AMI would you like to deploy?"
echo "1. Ubuntu 24.04"
echo "2. Ubuntu 22.04"
echo "3. Ubuntu 18.04"
read -p "Enter your choice (1,2  or 3): " choice

# Set the AMI_ID based on the user's choice
case $choice in 
  1)
    AMI_ID="ami-09040d770ffe2224f"
    echo "Selected AMI: Ubuntu 24.04"
    ;;
  2)
    AMI_ID="ami-0b8b44ec9a8f90422"
    echo "Selected AMI: Ubuntu 22.04"
    ;;
  3)
    AMI_ID="ami-0e4c27be5484b93d6"
    echo "Selected AMI: Ubuntu 18.04"
    ;;
  *)
    echo "Invalid choice. Defaulting to Ubuntu 22.04."
    AMI_ID="ami-0e4c27be5484b93d6"
    ;;
esac

# Ubuntu Specific Path Variables
salt_automation_path="/Users/michaelrudloff/Dropbox/vscode/salt_automation"
salt_certs_path="/Users/michaelrudloff/Dropbox/vscode/salt_automation/certs"
salt_tlmfiles_path="/Users/michaelrudloff/Dropbox/vscode/salt_automation/tlmfiles"
salt_templates_path="/Users/michaelrudloff/Dropbox/vscode/salt_automation/templates"
salt_hosts_path="/Users/michaelrudloff/Dropbox/vscode/salt_automation/upload_to_salt_host"
salt_hosts_local_path="/Users/michaelrudloff/Dropbox/vscode/salt_automation"
salt_key_file="/Users/michaelrudloff/Dropbox/vscode/key"

# Create mrudloff-salt-master instance
SALT_MASTER_INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SECURITY_GROUP_ID" \
    --subnet-id "$SUBNET_ID" \
    --associate-public-ip-address \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=mrudloff-salt-master}]' \
    --query 'Instances[0].InstanceId' \
    --output text \
    --region "$AWS_REGION")
echo "Salt Environment is being created. Please wait..."
echo 
echo "The environment will consist of the following:"
echo "1. Salt Master"
echo "2. Salt Minion"
echo
echo "The Salt Minion will have Apache with self-signed TLS installed and configured"
echo
echo "mrudloff-salt-master instance ID: $SALT_MASTER_INSTANCE_ID"

# Create mrudloff-puppet-client instance
SALT_MINION_INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SECURITY_GROUP_ID" \
    --subnet-id "$SUBNET_ID" \
    --associate-public-ip-address \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=mrudloff-salt-minion}]' \
    --query 'Instances[0].InstanceId' \
    --output text \
    --region "$AWS_REGION")
echo "mrudloff-salt-minion instance ID: $SALT_MINION_INSTANCE_ID"

# Get Public DNS name and Private IP address of instances
SALT_MASTER_PUBLIC_DNS=$(aws ec2 describe-instances \
    --instance-ids "$SALT_MASTER_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicDnsName' \
    --output text \
    --region "$AWS_REGION")
SALT_MASTER_PRIVATE_IP=$(aws ec2 describe-instances \
    --instance-ids "$SALT_MASTER_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' \
    --output text \
    --region "$AWS_REGION")

SALT_MINION_PUBLIC_DNS=$(aws ec2 describe-instances \
    --instance-ids "$SALT_MINION_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicDnsName' \
    --output text \
    --region "$AWS_REGION")
SALT_MINION_PRIVATE_IP=$(aws ec2 describe-instances \
    --instance-ids "$SALT_MINION_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' \
    --output text \
    --region "$AWS_REGION")

echo
echo "The following ec2 instances have been created:"
echo
echo "Host: mrudloff-salt-master"
echo "Public DNS: $SALT_MASTER_PUBLIC_DNS"
echo "Private IP: $SALT_MASTER_PRIVATE_IP"
echo
echo "Host: mrudloff-salt-minion"
echo "Public DNS: $SALT_MINION_PUBLIC_DNS"
echo "Private IP: $SALT_MINION_PRIVATE_IP"

# Get instance IDs of the newly created Puppet instances
SALT_MASTER_INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=mrudloff-salt-master" "Name=instance-state-name,Values=running" --query "Reservations[*].Instances[*].[InstanceId]" --output text --region "$AWS_REGION")
SALT_MINION_INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=mrudloff-salt-minion" "Name=instance-state-name,Values=running" --query "Reservations[*].Instances[*].[InstanceId]" --output text --region "$AWS_REGION")

# Declare array of Ansible instance IDs
INSTANCE_IDS=("$SALT_MASTER_INSTANCE_ID" "$SALT_MINION_INSTANCE_ID")

# Wait for 3 minutes to give the Ansible instances some time to initialize
echo
duration=180
while [ $duration -gt 0 ]; do
    printf "\rWaiting %02d seconds for Ansible instances to initialize before checking again..." $duration
    sleep 1
    ((duration--))
done

# Wait for each Ansible instances to pass status checks
for INSTANCE_ID in "${INSTANCE_IDS[@]}"; do
    INSTANCE_STATUS=""
    while [ -z "$INSTANCE_STATUS" ] || [ "$INSTANCE_STATUS" != "ok" ]; do
        echo 
        echo "Checking status of ec2 instances"
        INSTANCE_STATUS=$(aws ec2 describe-instance-status --instance-ids $INSTANCE_ID --query 'InstanceStatuses[0].InstanceStatus.Status' --output text)
        echo "Instance status: $INSTANCE_STATUS"
        INSTANCE_STATUS=$(aws ec2 describe-instance-status --instance-ids $INSTANCE_ID --query 'InstanceStatuses[0].InstanceStatus.Status' --output text)
        if [ -z "$INSTANCE_STATUS" ] || [ "$INSTANCE_STATUS" != "ok" ]; then
            echo
            duration2=15
            while [ $duration2 -gt 0 ]; do
            printf "\rInstances are not ready yet. Waiting for %02d seconds before checking again." $duration2
            sleep 1
            ((duration2--))
            done
        fi
    done
done
echo
echo "All instances have passed status checks and are ready to use."

# Ensure SSH Keys are being accepted / skipped
export ANSIBLE_HOST_KEY_CHECKING=False

# Create Ansible Configuration and Playbook
echo 
echo "Creating Ansible Configuration and Playbook"

# Define the instance names before attempting to retrieve their IPs
INSTANCE_NAMES=("mrudloff-salt-master" "mrudloff-salt-minion")

# Declare global variables for public DNS names to ensure they're available for all parts of the script
SALT_MASTER_PUBLIC_DNS=""
SALT_MINION_PUBLIC_DNS=""

# Retrieve the public DNS names of the running instances
for INSTANCE_NAME in "${INSTANCE_NAMES[@]}"; do
    INSTANCE_DETAILS=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=running" --query 'Reservations[*].Instances[*].[PublicDnsName]' --output text)
    if [ "$INSTANCE_NAME" == "mrudloff-salt-master" ]; then
        SALT_MASTER_PUBLIC_DNS=$INSTANCE_DETAILS
    elif [ "$INSTANCE_NAME" == "mrudloff-salt-minion" ]; then
        SALT_MINION_PUBLIC_DNS=$INSTANCE_DETAILS  
    fi
done



# Configure Ansible hosts
configure_ansible_hosts() {
    echo "Configuring Ansible hosts file..."

    # Check and delete existing hosts file
    if [ -f "$salt_hosts_local_path/salthosts" ]; then
        rm $salt_hosts_local_path/salthosts
    fi

    # Create hosts file
    cat << EOF > $salt_hosts_local_path/salthosts
[saltmaster]
mrudloff-salt-master ansible_host=$SALT_MASTER_PUBLIC_DNS ansible_user=ubuntu ansible_ssh_private_key_file=/Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem

[saltminion]
mrudloff-salt-minion ansible_host=$SALT_MINION_PUBLIC_DNS ansible_user=ubuntu ansible_ssh_private_key_file=/Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem
EOF
}

# Prompt the user for the domain name
# read -p "Domain used for the certificate used for the Salt Minion? " apache_domain_name


# Configure Apache templates
configure_ansible_apache_templates() {
    echo "Configuring Apache templates..."

    # Create templates directory if it doesn't exist
    mkdir -p $salt_templates_path

    # Check and delete existing apache-ssl.conf.j2 file
    if [ -f "$salt_templates_path/ansible-apache-ssl.conf.j2" ]; then
        rm $salt_templates_path/ansible-apache-ssl.conf.j2
    fi

    # Create Ansible Client apache-ssl.conf.j2 file
    cat << EOF > $salt_templates_path/ansible-apache-ssl.conf.j2
<VirtualHost *:443>
    ServerName $SALT_MINION_PUBLIC_DNS
    DocumentRoot /var/www/html
    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/ansible-apache-selfsigned.crt
    SSLCertificateKeyFile /etc/ssl/private/ansible-apache-selfsigned.key
</VirtualHost>
EOF

    # Check and delete existing Ansible Client apache-redirect.conf.j2 file
    if [ -f "$salt_templates_path/ansible-apache-redirect.conf.j2" ]; then
        rm $salt_templates_path/ansible-apache-redirect.conf.j2
    fi

    # Create Ansible Client apache-redirect.conf.j2 file
    cat << EOF > $salt_templates_path/ansible-apache-redirect.conf.j2
<VirtualHost *:80>
    ServerName $SALT_MINION_PUBLIC_DNS
    Redirect permanent / https://$SALT_MINION_PUBLIC_DNS/
</VirtualHost>
EOF
}

# Create Puppet Client self-signed certificates
create_selfsigned_certificates() {
    echo "Creating self-signed certificates..."

    # Create certs directory if it doesn't exist
    mkdir -p $salt_certs_path

    # Create self-signed certificates for Ansible client apache server
    openssl req -x509 -newkey rsa:4096 -keyout $salt_certs_path/ansible-apache-selfsigned.key -out $salt_certs_path/ansible-apache-selfsigned.crt -days 365 -nodes -subj "/C=GB/ST=Cambs/L=Ely/O=Digicert/OU=Product/CN=saltminion/emailAddress=michael.rudloff@digicert.com" 
}

# Configure Ansible playbook
configure_ansible_playbook() {
    echo "Configuring Ansible playbook..."

    # Check and delete existing playbook file
    if [ -f "$salt_hosts_local_path/salt.yml" ]; then
        rm $salt_hosts_local_path/salt.yml
    fi

    # Create playbook file
    cat << EOF > $salt_hosts_local_path/salt.yml
---
- hosts: all
  become: yes
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: /Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem
  tasks:
    - name: Update apt cache
      apt:
        update_cache: yes

    - name: Install build-essential package
      apt:
        name: build-essential
        state: present
    - name: Upgrade packages
      apt:
        upgrade: yes

    - name: Add lines to /etc/hosts
      ansible.builtin.lineinfile:
        path: /etc/hosts
        line: "{{ item }}"
      loop:
        - "$SALT_MASTER_PRIVATE_IP mrudloff-salt-master mrudloff-salt-master.us-east-2.compute.internal"
        - "$SALT_MINION_PRIVATE_IP mrudloff-salt-minion mrudloff-salt-minion.us-east-2.compute.internal"

    - name: Ensure required directories exist
      file:
        path: /etc/apt/keyrings
        state: directory
        mode: '0755'

    - name: Download Salt repository key
      ansible.builtin.get_url:
        url: https://repo.saltproject.io/salt/py3/ubuntu/24.04/amd64/SALT-PROJECT-GPG-PUBKEY-2023.gpg
        dest: /etc/apt/keyrings/salt-archive-keyring-2023.gpg
        mode: '0644'

    - name: Add Salt repository
      ansible.builtin.apt_repository:
        repo: deb [signed-by=/etc/apt/keyrings/salt-archive-keyring-2023.gpg arch=amd64] https://repo.saltproject.io/salt/py3/ubuntu/24.04/amd64/latest noble main
        state: present

    - name: Update apt 
      ansible.builtin.apt:
        update_cache: yes

- hosts: saltmaster
  become: yes
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: /Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem
    apache_server_name: $apache_domain_name
    apache_document_root: /var/www/html  
  tasks:
    - name: Set hostname using hostnamectl
      ansible.builtin.command:
        cmd: hostnamectl set-hostname mrudloff-salt-master.us-east-2.compute.internal
      become: yes

    - name: Backup SSH Configuration
      command: cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

    - name: Edit SSH Configuration - PermitRootLogin
      lineinfile:
        path: /etc/ssh/sshd_config
        regexp: '^#?PermitRootLogin'
        line: 'PermitRootLogin yes'

    - name: Edit SSH Configuration - PubkeyAuthentication
      lineinfile:
        path: /etc/ssh/sshd_config
        regexp: '^#?PubkeyAuthentication'
        line: 'PubkeyAuthentication yes'

    - name: Restart SSH
      systemd:
        name: ssh
        state: restarted

    - name: Generate new SSH key pair
      ansible.builtin.openssh_keypair:
        path: /root/.ssh/id_rsa
        type: rsa
        size: 4096
        comment: "root@mrudloff-salt-master"
        force: true        
        
    - name: Copy public key to /home/ubuntu
      copy:
        src: /root/.ssh/id_rsa.pub
        dest: /home/ubuntu/id_rsa.pub
        owner: ubuntu
        group: ubuntu
        mode: '0644'
        remote_src: yes                

- hosts: saltminion
  become: yes
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: /Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem
    apache_server_name: $apache_domain_name
    apache_document_root: /var/www/html  
  tasks:
    - name: Set hostname using hostnamectl
      ansible.builtin.command:
        cmd: hostnamectl set-hostname mrudloff-salt-minion.us-east-2.compute.internal
      become: yes


    - name: Backup SSH Configuration
      command: cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

    - name: Edit SSH Configuration - PermitRootLogin
      lineinfile:
        path: /etc/ssh/sshd_config
        regexp: '^#?PermitRootLogin'
        line: 'PermitRootLogin yes'

    - name: Edit SSH Configuration - PubkeyAuthentication
      lineinfile:
        path: /etc/ssh/sshd_config
        regexp: '^#?PubkeyAuthentication'
        line: 'PubkeyAuthentication yes'

    - name: Restart SSH
      systemd:
        name: ssh
        state: restarted

    - name: Generate new SSH key pair
      ansible.builtin.openssh_keypair:
        path: /root/.ssh/id_rsa
        type: rsa
        size: 4096
        comment: "root@mrudloff-salt-minion"
        force: true        
        
    - name: Copy public key to /home/ubuntu
      copy:
        src: /root/.ssh/id_rsa.pub
        dest: /home/ubuntu/id_rsa.pub
        owner: ubuntu
        group: ubuntu
        mode: '0644'
        remote_src: yes

    - name: Install Apache
      apt:
        name: apache2
        state: latest
    - name: Create /etc/ssl/private/ directory
      file:
        path: /etc/ssl/private/
        state: directory
        owner: root
        group: root
        mode: '0700'

    - name: Create /etc/ssl/certs/ directory
      file:
        path: /etc/ssl/certs/
        state: directory
        owner: root
        group: root
        mode: '0755'

    - name: Copy files to remote server
      copy:
        src: "$salt_certs_path/{{ item }}"
        dest: "/etc/ssl/private/{{ item }}"
      with_items:
        - ansible-apache-selfsigned.key

    - name: Copy files to remote server
      copy:
        src: "$salt_certs_path/{{ item }}"
        dest: "/etc/ssl/certs/{{ item }}"
      with_items:
        - ansible-apache-selfsigned.crt

    - name: Enable Apache2 modules
      apache2_module:
        name: "{{ item }}"
        state: present
      loop:
        - ssl
        - rewrite
   
    - name: Configure Apache2 for HTTPS
      template:
        src: $salt_templates_path/ansible-apache-ssl.conf.j2
        dest: /etc/apache2/sites-available/default-ssl.conf
      notify: Restart Apache2

    - name: Enable Apache2 default SSL virtual host
      command: a2ensite default-ssl

    - name: Configure Apache2 to redirect HTTP to HTTPS
      template:
        src: $salt_templates_path/ansible-apache-redirect.conf.j2
        dest: /etc/apache2/sites-available/000-default.conf
      notify: Restart Apache2

  handlers:
    - name: Restart Apache2
      service:
        name: apache2
        state: restarted

- hosts: localhost
  become: no
  vars:
    remote_user: ubuntu
    remote_host: $SALT_MASTER_PUBLIC_DNS
    remote_file: /home/ubuntu/id_rsa.pub
    local_dest: /Users/michaelrudloff/Dropbox/vscode/SSH_Keys_For_Deployed_Servers/salt_master.pub
    ssh_key: /Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem
  tasks:
    - name: Copy public key from remote server using scp
      shell: |
        scp -i {{ ssh_key }} {{ remote_user }}@{{ remote_host }}:{{ remote_file }} {{ local_dest }}
      delegate_to: localhost
      ignore_errors: no
      register: scp_copy

    - name: Debug SCP output
      debug:
        var: scp_copy.stdout_lines

    - name: Debug SCP error
      debug:
        var: scp_copy.stderr_lines

- hosts: localhost
  become: no
  vars:
    remote_user: ubuntu
    remote_host: $SALT_MINION_PUBLIC_DNS
    remote_file: /home/ubuntu/id_rsa.pub
    local_dest: /Users/michaelrudloff/Dropbox/vscode/SSH_Keys_For_Deployed_Servers/salt_minion.pub
    ssh_key: /Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem
  tasks:
    - name: Copy public key from remote server using scp
      shell: |
        scp -i {{ ssh_key }} {{ remote_user }}@{{ remote_host }}:{{ remote_file }} {{ local_dest }}
      delegate_to: localhost
      ignore_errors: no
      register: scp_copy

    - name: Debug SCP output
      debug:
        var: scp_copy.stdout_lines

    - name: Debug SCP error
      debug:
        var: scp_copy.stderr_lines        

    - name: Upload DigiCertTLMAgentGPOInstaller to master
      shell: |
        scp -i /Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem /Users/michaelrudloff/Dropbox/vscode/salt_automation/tlmfiles/DigiCertTLMAgentGPOInstaller.tar.gz ubuntu@$SALT_MASTER_PUBLIC_DNS:/home/ubuntu/

- hosts: saltmaster
  become: yes
  vars:
    local_files:      
      - "/Users/michaelrudloff/Dropbox/vscode/SSH_Keys_For_Deployed_Servers/salt_minion.pub"      
    remote_temp_dir: "/tmp/ssh_keys"
    remote_final_path: "/root/.ssh/authorized_keys"
    remote_hosts:
      - mrudloff-salt-minion            
  tasks:
    - name: Create required directories for states
      ansible.builtin.file:
        path: "{{ item }}"
        state: directory
        mode: '0755'
      loop:
        - /srv/salt
        - /srv/salt/files
        - /srv/pillar  
    - name: Move TLM Agent installer to cookbook directory
      command: mv /home/ubuntu/DigiCertTLMAgentGPOInstaller.tar.gz /srv/salt/files/    
    - name: Create temporary directory on the remote server
      ansible.builtin.file:
        path: "{{ remote_temp_dir }}"
        state: directory

    - name: Copy local files to remote server's temporary directory
      ansible.builtin.copy:
        src: "{{ item }}"
        dest: "{{ remote_temp_dir }}/{{ item | basename }}"
      loop: "{{ local_files }}"
      loop_control:
        label: "{{ item }}"

    - name: Append content of the temporary files to the remote authorized_keys file
      ansible.builtin.shell: |
        cat {{ remote_temp_dir }}/*.pub >> "{{ remote_final_path }}"

    - name: Remove specific line from /root/.ssh/authorized_keys
      ansible.builtin.lineinfile:
        path: /root/.ssh/authorized_keys
        line: >-
          no-port-forwarding,no-agent-forwarding,no-X11-forwarding,
          command="echo 'Please login as the user \"ubuntu\" rather than the user \"root\".'; echo; sleep 10; exit 142"
        state: absent       

    - name: Ensure known_hosts contains the remote hosts
      ansible.builtin.shell: ssh-keyscan {{ item }} >> /root/.ssh/known_hosts
      with_items: "{{ remote_hosts }}"
      ignore_errors: yes         

- hosts: localhost
  become: no
  vars:
    remote_user: ubuntu
    remote_host: $SALT_MINION_PUBLIC_DNS
    remote_file: /home/ubuntu/id_rsa.pub
    local_dest: /Users/michaelrudloff/Dropbox/vscode/SSH_Keys_For_Deployed_Servers/salt_minion.pub
    ssh_key: /Users/michaelrudloff/Dropbox/vscode/key/aws_keypair.pem
  tasks:
    - name: Copy public key from remote server using scp
      shell: |
        scp -i {{ ssh_key }} {{ remote_user }}@{{ remote_host }}:{{ remote_file }} {{ local_dest }}
      delegate_to: localhost
      ignore_errors: no
      register: scp_copy

    - name: Debug SCP output
      debug:
        var: scp_copy.stdout_lines

    - name: Debug SCP error
      debug:
        var: scp_copy.stderr_lines        

- hosts: saltminion
  become: yes
  vars:
    local_files:      
      - "/Users/michaelrudloff/Dropbox/vscode/SSH_Keys_For_Deployed_Servers/salt_master.pub"      
    remote_temp_dir: "/tmp/ssh_keys"
    remote_final_path: "/root/.ssh/authorized_keys"
    remote_hosts:
      - mrudloff-salt-master            
  tasks:
    - name: Create temporary directory on the remote server
      ansible.builtin.file:
        path: "{{ remote_temp_dir }}"
        state: directory

    - name: Copy local files to remote server's temporary directory
      ansible.builtin.copy:
        src: "{{ item }}"
        dest: "{{ remote_temp_dir }}/{{ item | basename }}"
      loop: "{{ local_files }}"
      loop_control:
        label: "{{ item }}"

    - name: Append content of the temporary files to the remote authorized_keys file
      ansible.builtin.shell: |
        cat {{ remote_temp_dir }}/*.pub >> "{{ remote_final_path }}"

    - name: Remove specific line from /root/.ssh/authorized_keys
      ansible.builtin.lineinfile:
        path: /root/.ssh/authorized_keys
        line: >-
          no-port-forwarding,no-agent-forwarding,no-X11-forwarding,
          command="echo 'Please login as the user \"ubuntu\" rather than the user \"root\".'; echo; sleep 10; exit 142"
        state: absent       

    - name: Ensure known_hosts contains the remote hosts
      ansible.builtin.shell: ssh-keyscan {{ item }} >> /root/.ssh/known_hosts
      with_items: "{{ remote_hosts }}"
      ignore_errors: yes 

- name: Install and configure Salt Master
  hosts: saltmaster
  become: yes
  tasks:
    - name: Install Salt Master
      ansible.builtin.apt:
        name: salt-master
        state: present

    - name: Enable and start Salt Master service
      ansible.builtin.systemd:
        name: salt-master
        enabled: yes
        state: started



    - name: Create /srv/pillar/vars.sls
      ansible.builtin.copy:
        content: |
          # /srv/pillar/vars.sls
          options:
            bundle_name: tlm_agent_3.0.11_linux64.tar.gz
            alias_name: mrudloff_salt_minion
            businessUnit: 542bce5b-9a54-41df-a054-fe977133ee09
            proxy: ''
        dest: /srv/pillar/vars.sls
        mode: '0644'

    - name: Create /srv/pillar/top.sls
      ansible.builtin.copy:
        content: |
          # /srv/pillar/top.sls
          base:
            '*':
              - vars
        dest: /srv/pillar/top.sls
        mode: '0644'

    - name: Create /srv/salt/tlmagent.sls
      ansible.builtin.copy:
        content: |
          {% raw %}
          {% set bundle_name = pillar['options']['bundle_name'] %}
          {% set business_unit = pillar['options']['businessUnit'] %}
          {% set alias_name = pillar['options']['alias_name'] %}
          {% set proxy = pillar['options']['proxy'] %}

          create_directory:
            file.directory:
              - name: /opt/digicert
              - mode: 0755
              - user: root
              - group: root

          copy_archive:
            file.managed:
              - name: /opt/digicert/DigiCertTLMAgentGPOInstaller.tar.gz
              - source: salt://files/DigiCertTLMAgentGPOInstaller.tar.gz
              - mode: 0644
              - user: root
              - group: root
              - require:
                - file: create_directory

          extract_bundle:
            archive.extracted:
              - name: /opt/digicert
              - source: /opt/digicert/DigiCertTLMAgentGPOInstaller.tar.gz
              - user: root
              - group: root
              - enforce_ownership: true
              - require:
                - file: copy_archive

          run_installer:
            cmd.run:
              - name: ./silentInstaller-by-companion-lnx.sh AGENT_BUNDLE_NAME={{ bundle_name }} BUSINESS_UNIT_ID={{ business_unit }} ALIASNAME={{ alias_name }} PROXY={{ proxy }}
              - shell: /bin/bash
              - cwd: /opt/digicert/DigiCertTLMAgentGPOInstaller
              - user: root
              - group: root
              - require:
                - archive: extract_bundle
          {% endraw %}
        dest: /srv/salt/tlmagent.sls
        mode: '0644'

    - name: Create /srv/salt/top.sls
      ansible.builtin.copy:
        content: |
          # /srv/salt/top.sls
          base:
            '*':
              - tlmagent
        dest: /srv/salt/top.sls
        mode: '0644'

- name: Install and configure Salt Minion
  hosts: saltminion
  become: yes
  tasks:
    - name: Install Salt Minion
      ansible.builtin.apt:
        name: salt-minion
        state: present

    - name: Configure Salt Minion
      ansible.builtin.lineinfile:
        path: /etc/salt/minion
        regexp: '^master:.*'
        line: 'master: mrudloff-salt-master.us-east-2.compute.internal'

    - name: Enable and start Salt Minion service
      ansible.builtin.systemd:
        name: salt-minion
        enabled: yes
        state: restarted

    - name: Give the Minion 15 seconds to start
      ansible.builtin.pause:
        seconds: 15        

- name: Accept all minion keys on Salt Master
  hosts: saltmaster
  become: yes
  tasks:
    - name: Accept all Salt Minion keys
      command: salt-key -A -y

    - name: Refresh pillar data
      command: salt '*' saltutil.refresh_pillar

    - name: Apply tlmagent state
      command: salt '*' state.apply tlmagent

EOF
}

# Call the functions
configure_ansible_hosts
configure_ansible_playbook
create_selfsigned_certificates
configure_ansible_apache_templates

# Running Playbook
export ANSIBLE_HOST_KEY_CHECKING=False
ansible-playbook -i $salt_hosts_local_path/salthosts $salt_hosts_local_path/salt.yml

  exit
}


press_enter() {
  echo ""
  echo -n "	Press Enter to continue "
  read
  clear
}
incorrect_selection() {
  echo "Incorrect selection! Try again."
}
## Start Menu ##
until [ "$selection" = "0" ]; do
clear
echo "██╗      █████╗ ██████╗ "                                  
echo "██║     ██╔══██╗██╔══██╗"                                  
echo "██║     ███████║██████╔╝"                                  
echo "██║     ██╔══██║██╔══██╗"                                 
echo "███████╗██║  ██║██████╔╝"                                  
echo "╚══════╝╚═╝  ╚═╝╚═════╝"                                   
echo ""                                                          
echo " ██████╗██████╗ ███████╗ █████╗ ████████╗ ██████╗ ██████╗ "
echo "██╔════╝██╔══██╗██╔════╝██╔══██╗╚══██╔══╝██╔═══██╗██╔══██╗"
echo "██║     ██████╔╝█████╗  ███████║   ██║   ██║   ██║██████╔╝"
echo "██║     ██╔══██╗██╔══╝  ██╔══██║   ██║   ██║   ██║██╔══██╗"
echo "╚██████╗██║  ██║███████╗██║  ██║   ██║   ╚██████╔╝██║  ██║"
echo " ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝"
echo ""
  echo "Select Lab to deploy"
  echo ""
  echo "1  -  Ansible Server | Node + Apache + SelfSigned TLS + TLM Agent"
  echo "2  -  Puppet Server | Node + Apache + SelfSigned TLS + TLM Agent"
  echo "3  -  Chef Server | Workstation + TLM Agent Cookbook | Node + Apache + SelfSigned TLS"
  echo "4  -  HAProxy (OSS) + ACME Client + SelfSigned TLS | Loadbalanced Apache Servers"
  echo "5  -  AWS EKS Cluster + Istio + CertManager "
  echo "6  -  Ubuntu | Apache | No SSL | No TLM Agent"
  echo "7  -  Ubuntu | Apache | No SSL | TLM Agent"
  echo "8  -  Ubuntu | Apache | SelfSigned TLS | TLM Agent"
  echo "9  -  Salt Master | Minion + Apache + SelfSigned TLS + TLM Agent"
  echo "0  -  Exit"
  echo ""
  echo "Enter selection: "
  read selection
  echo ""
  case $selection in
    1 ) clear ; menu_option_one ; press_enter ;;
    2 ) clear ; menu_option_two ; press_enter ;;
    3 ) clear ; menu_option_three ; press_enter ;;
    4 ) clear ; menu_option_four ; press_enter ;;
    5 ) clear ; menu_option_five ; press_enter ;;
    6 ) clear ; menu_option_six ; press_enter ;;
    7 ) clear ; menu_option_seven ; press_enter ;;
    8 ) clear ; menu_option_eight ; press_enter ;;
    9 ) clear ; menu_option_nine ; press_enter ;;
    0 ) clear ; exit ;;
    * ) clear ; incorrect_selection ; press_enter ;;
  esac
done