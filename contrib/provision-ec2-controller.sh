#!/usr/bin/env bash

if [ -z $1 ]; then
  echo usage: $0 [region]
  exit 1
fi

# check for Deis' general dependencies
thisdir=`dirname $0`
if ! $thisdir/check-deis-deps.sh; then
  echo 'Deis is missing some dependencies.'
  exit 1
fi


# check for EC2 API tools in $PATH
if ! which ec2-describe-group > /dev/null; then
  echo 'Please install the EC2 API command-line tools and ensure they are in your $PATH.'
  exit 1
fi

# check for AWS environment variables
: ${AWS_ACCESS_KEY:?'Please set AWS_ACCESS_KEY in your environment for EC2 API access.'}
: ${AWS_SECRET_KEY:?'Please set AWS_SECRET_KEY in your environment for EC2 API access.'}

region=$1

# see contrib/prepare-ubuntu-ami.sh for instructions
# on creating your own deis-optmized AMIs
if [ "$region" == "ap-northeast-1" ]; then
  image=ami-6da8356c
elif [ "$region" == "ap-southeast-1" ]; then
  image=ami-a66f24f4
elif [ "$region" == "ap-southeast-2" ]; then
  image=ami-d5f66bef
elif [ "$region" == "eu-west-1" ]; then
  image=ami-acbf5adb
elif [ "$region" == "sa-east-1" ]; then
  image=ami-f9fd5ae4
elif [ "$region" == "us-east-1" ]; then
  image=ami-69f3bc00
elif [ "$region" == "us-west-1" ]; then
  image=ami-f0695cb5
elif [ "$region" == "us-west-2" ]; then
  image=ami-ea1e82da
else
  echo "Cannot find AMI for region: $region"
  exit 1
fi

# ec2 settings
flavor="m1.large"
ebs_size=100
sg_name=deis-controller
sg_src=0.0.0.0/0
key_name=deis-controller
export EC2_URL=https://ec2.$region.amazonaws.com/

# ssh settings
ssh_key_path=~/.ssh/$key_name
ssh_user="ubuntu"

# chef settings
node_name="deis-controller"
run_list="recipe[deis::controller]"
chef_version=11.4.4

function echo_color {
  echo -e "\033[1m$1\033[0m"
}

# create security group and authorize ingress
if ! ec2-describe-group | grep -q "$sg_name"; then
  echo_color "Creating security group: $sg_name"
  set -x
  ec2-create-group $sg_name -d "Created by Deis"
  set +x
  echo_color "Authorizing TCP ports 22,80,443,514 from $sg_src..."
  set -x
  ec2-authorize deis-controller -P tcp -p 22 -s $sg_src >/dev/null
  ec2-authorize deis-controller -P tcp -p 80 -s $sg_src >/dev/null
  ec2-authorize deis-controller -P tcp -p 443 -s $sg_src >/dev/null
  ec2-authorize deis-controller -P tcp -p 514 -s $sg_src >/dev/null
  set +x
else
  echo_color "Security group $sg_name exists"
fi

# create ssh keypair and store it
if ! test -e $ssh_key_path; then
  echo_color "Creating new SSH key: $key_name"
  set -x
  ec2-create-keypair $key_name > $ssh_key_path
  chmod 600 $ssh_key_path
  set +x
  echo "Saved to $ssh_key_path"
else
  echo_color "SSH key $ssh_key_path exists"
fi

# create data bags
knife data bag create deis-users 2>/dev/null
knife data bag create deis-formations 2>/dev/null
knife data bag create deis-apps 2>/dev/null

# trigger ec2 instance bootstrap
echo_color "Provisioning $node_name with knife ec2..."
set -x
knife ec2 server create \
 --bootstrap-version $chef_version \
 --region $region \
 --image $image \
 --flavor $flavor \
 --groups $sg_name \
 --tags Name=$node_name \
 --ssh-key $key_name \
 --ssh-user $ssh_user \
 --identity-file $ssh_key_path \
 --node-name $node_name \
 --ebs-size $ebs_size \
 --run-list $run_list
set +x
