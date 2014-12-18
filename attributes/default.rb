# #LVM attributes
# default['hft-chef-lvm']['lvm_attributes']['physical_volumes'] = []
# default['hft-chef-lvm']['lvm_attributes']['volume_group'] = "mongo-pool00"
# default['hft-chef-lvm']['lvm_attributes']['logical_volume'] = "mongodb"
# default['hft-chef-lvm']['lvm_attributes']['lvm_lv_stripes'] = 1
# default['hft-chef-lvm']['lvm_attributes']['filesystem'] = "ext4"
# default['hft-chef-lvm']['lvm_attributes']['mount_options'] = "rw,noatime,nodiratime"

# #AWS attributes
# default['hft-chef-lvm']['aws_attributes']['using_aws'] = false
# default['hft-chef-lvm']['aws_attributes']['aws_ebs_volume_name'] = "mongo_ebs_for_LVM"
# default['hft-chef-lvm']['aws_attributes']['volsize'] = 1
# default['hft-chef-lvm']['aws_attributes']['voltype'] = "standard"
# default['hft-chef-lvm']['aws_attributes']['use_piops'] = false
# default['hft-chef-lvm']['aws_attributes']['piops'] = 1000
# default['hft-chef-lvm']['aws_attributes']['vols'] = 1
# default['hft-chef-lvm']['aws_attributes']['device'] = "/dev/sd"
# default['hft-chef-lvm']['aws_attributes']['start_device'] = "f"
# default['hft-chef-lvm']['aws_attributes']['lvm_subscribers'] = []
