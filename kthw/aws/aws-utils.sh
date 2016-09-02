#!/bin/bash -

valid_region() {
  aws ec2 describe-regions --region-names "$@" > /dev/null 2>&1
}

valid_zone() {
  aws ec2 describe-availability-zones --zone-names "$@" > /dev/null 2>&1
}

cluster_exists() {
  kops get cluster "--state=$1" | grep "$2" > /dev/null 2>&1
}

s3_bucket_exists() {
  aws s3 ls | grep "$@" > /dev/null 2>&1
}
