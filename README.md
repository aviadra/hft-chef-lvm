hft-chef-lvm Cookbook
=====================
This cookbook is used to create LVMs. If it is running on AWS/EC2, it can also request disks automatically.
If you're on AWS, and you need the array to be backed up, you will also need the "hft-chef-ebs-backup" cookbook.

Usage
-----
When using the cookbook, you need to include it in the runlist (we "cuttingly" do it by adding it to the role).
We've designed it so that when a VG is created, the LV on top of it will take 100% of its space. 
Currently, only 1 LV creation on a VG is supported.

The Cookbook depends on "lvm" and "aws". The "aws" version in question is v1.0.1 by Opscode. The "lvm" is hulu1522's fork at https://github.com/hulu1522/lvm/, Which fixed the resize issue but wasn't merged into opscode yet. Commit "1964ea28064ee705d3a85e387a649dc8a270a9e8".

Requirements
------------
If the node is of type "operational", there are some attributes which are required to be set. They are:

physical_volumes - if you not using the aws ability, this must be a ruby array of physical disks to use for the LVM. 

volume_group - The name you wish to give the LVM's volume group (pool).

logical_volume - The name of the logical volume to create on top of the VG.

mount_point[location] - The mount_point attribute is a hash object, that must include at least the "location" to mount to.

aws_ebs_volume_name - If you are using the AWS feature, then  you need to declare a name prefix the disks will use.

Optional
------------
"snapshot_backup": true - tells the LVM to subscribe to the snapshot backup

snapshot_pre_backup_cmd/snapshot_post_backup_cmd - You may declare per and post scripts you wish the machine will run before and after the backup. Note: multiple entries are conglomerated and run in no particular order for all snapshot directives regardless to if they belong to other disks on the machine. Also, if the exact same cmd is declared, only one occurrence will be considered. Options can be: Simple command, for example: "ls -lash". An array of commands, for example: ["ls -lash", "ps-ef"]. Note: you may declare other scripts to be invoked, but there is no protection if they cause the script to error out, or if they even exist on the system.

Attributes
----------
in a role or envirment Json, this would look like:
"hft-chef-lvm": {
    "using_aws" : true,
    "arrays" : {
      "mongodb" : {
        "aws_attributes" : {
          "aws_ebs_volume_name" : "EBS_for_mongo_LVM_in_RS",
          "volsize" : 50,
          "vols" : 4,
          "voltype": "io1",
          "use_piops": true,
          "piops": 150
        },
        "lvm_attributes" : {
          "lvm_lv_stripes" : 2,
          "volume_group" : "mongo-pool00",
          "logical_volume" : "mongodb",
          "snapshot_backup": true,
          "snapshot_pre_backup_cmd": "ls -lash",
          "snapshot_post_backup_cmd": ["whoami", "ps -ef"]
          "mount_point" : {
            "location": "/var/lib/mongodb",
            "user": "mongodb",
            "group": "mongodb"
          }
         }
        },



Contributing
------------
TODO: (optional) If this is a public cookbook, detail the process for contributing. If this is a private cookbook, remove this section.

e.g.
1. Fork the repository on Github
2. Create a named feature branch (like `add_component_x`)
3. Write you change
4. Write tests for your change (if applicable)
5. Run the tests, ensuring they all pass
6. Submit a Pull Request using Github

License and Authors
-------------------
Authors: Aviad
