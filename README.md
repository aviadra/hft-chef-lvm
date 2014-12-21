hft-chef-lvm Cookbook
=====================
This cookbook is used to create LVMs. If it is running on AWS/EC2, it can also request disks automatically.
If you're on AWS, and you need the array to be backed up, you will also need the "hft-chef-ebs-backup" cookbook.

The cookbook can:
* Create "simple disks" - If no striping is requested, then a none-striping array will be created. This array can have just one disk.
* Create "striped array" - In order to boost performance (like RAID 0), it is possible to set how many strips one wants data to be distributed to. (Keep in mind that there is a 20 disks limit)
* Increase the size of the arrays - At any given moment, the disk assignment by attributes can be changed. increasing the amount of disks will increase the available capacity all the way up to the FileSystem on top of the array. Note: As long as there are enough disks to satisfy the striping demand among other caveats (see below for details).

Background
---------
This cookbook was created to address the need to be able to create arrays of disks that would not be space limited. That is, one would create the array with the current demand, and when the need to expand arose, one could simply upgrade seamlessly, and with no down time (aka the power of LVM).
This is in contrast to the traditional Linux RAID (MDadm) striped arrays (i.e. RAID level 0 or 1), where the array is set in stone, and in order to expand, one would have to create a new array.
Of course, there is another option, which is to create an LVM on top of MD devices. That is, create an MD device and on it create an LVM, and when we need to expand, create another MD device and expand the LVM to it. However, we quickly came to the conclusion, that this would add a lot of complexity to the system and we thought that there must be another way. 

And then we found it... We found that LVM supports both striping (a.k.a RAID 0) and mirroring (a.k.a RAID 1). This made the decision a no brainier... Why mess with MD devices at all if they are so constrained, as apposed to simply crating a striping/mirroring LVM array from the get go?
The answer we chose, was to go full hug with LVM only arrays.

How it works
-------------
This Cookbook when added to a node's runlist, aggregates all the arrays attributed to the node from every level (node, role, environment, Etc') and creates them in one go. So for example, if you have a "role" that needs an LVM for logs, and the same node holds another role of having a DB which needs a striping array, both will be created.
It is actually a wrapper around the "aws" and "lvm" cookbooks, in order to be able to provide the LVM functionality, and the ability to pull disks from AWS dynamically.

This Cookbook depends on "lvm" and "aws". The "aws" version in question is v1.0.1 by Opscode. The "lvm" is hulu1522's fork at https://github.com/hulu1522/lvm/, Which fixed the resize issue but wasn't merged into opscode yet (at the time of this writting). Commit "1964ea28064ee705d3a85e387a649dc8a270a9e8".
For simplicity, they are forked into my account, and you may simply clone them from it.

Usage
-----
When using the cookbook, you need to include it in the runlist (we the "cutting" way of adding it to a role).
We've designed it so that when a VG is created, the LV on top of it will take 100% of its space. 
Currently, only 1 LV creation on a VG is supported.


Requirements
------------
If the node is of type "operational", there are some attributes which are required to be set. They are:

physical_volumes - If you're not using the aws ability, this must be an array of physical disks to use for the LVM. 

volume_group - The name you wish to give the LVM's volume group (pool).

logical_volume - The name of the logical volume to create on top of the VG.

mount_point[location] - The mount_point attribute is a hash object, that must include at least the "location" to mount to.

aws_ebs_volume_name - If you are using the AWS feature, then  you need to declare a name prefix the disks will use.

Optional
------------
"snapshot_backup": true - tells the LVM to subscribe to the snapshot backups (provided by "hft-chef-ebs-backup").

snapshot_pre_backup_cmd/snapshot_post_backup_cmd - You may declare per and post scripts you wish the machine will run before and after the backup. Note: multiple entries are conglomerated and run in no particular order for all snapshot directives regardless to if they belong to other disks on the machine. Also, if the exact same cmd is declared, only one occurrence will be considered. Options can be: Simple command, for example: "ls -lash". An array of commands, for example: ["ls -lash", "ps-ef"]. The "commands" maybe other scripts to be invoked. For every command/script invoked, the exit status is checked and if the returened exit status is not successful ("0"), the entire run will be aborted.

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
