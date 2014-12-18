# Creates LVMs and aws disks
#
# Cookbook Name:: hft-chef-lvm
#
#
def find_next_letter(start_letter,used_letters)
	Chef::Log.info("hft-chef-lvm - find_next_letter - start_letter: " + start_letter.to_s + " used_letters: " + used_letters.flatten.to_s)
	until !used_letters.flatten.include?(start_letter) and !::File.exist?("/dev/xvd" + start_letter)
		Chef::Log.info("hft-chef-lvm - find_next_letter - The 'letter': " + start_letter + ", was not free for use.")
		start_letter = start_letter.next
	end
	Chef::Log.info("hft-chef-lvm - find_next_letter - The 'is this a letter of the ABC' returns:" + ('a'..'z').to_a.include?(start_letter).to_s)
	if ('a'..'z').to_a.include?(start_letter)
		Chef::Log.info("hft-chef-lvm - find_next_letter - the \"next\" letter chosen is: " + start_letter.to_s)
		return start_letter
	else
		Chef::Application.fatal!("hft-chef-lvm - Error, could not find a device letter :(.", 42) 	
	end
end

Chef::Log.info('hft-chef-lvm - Starting recipe')
include_recipe "aws"

chef_gem "aws-sdk" do 
	version "1.3.5"
end

aws = data_bag_item("aws", node['aws'].fetch('databag_entry','main'))
using_aws = node['hft-chef-lvm'].fetch('using_aws',false)

if !node.attribute?("hft-chef-lvm")
	Chef::Application.fatal!("hft-chef-lvm - Error, could not find hft-chef-lvm attributes??.", 42) 
end

#Total amount of disks sanity
total_allocated_vols = 0
total_linux_dev_letters = []
node['hft-chef-lvm']['arrays'].each do |(lvm_array_name,lvm_array_parms)|
	Chef::Log.info('hft-chef-lvm - Sanity working on: ' + lvm_array_name.to_s + ". with the params of: " + lvm_array_parms.to_s)
	aws_params = lvm_array_parms.fetch('aws_attributes', {})
	aws_attributes_vols = aws_params.fetch('vols',0)
	Chef::Log.info("hft-chef-lvm - for lvm_array_name: " + lvm_array_name.to_s + " aws_attributes_vols for sanity is: " + aws_attributes_vols.to_s)
	total_allocated_vols += aws_attributes_vols
	total_linux_dev_letters << aws_params.fetch('linux_dev_letters', [])
end
Chef::Log.info("hft-chef-lvm - total used by this node are: " + total_linux_dev_letters.flatten.to_s)

if total_allocated_vols > 20
	Chef::Application.fatal!("hft-chef-lvm - Error, this cookbook doesn't support more then 20 disks. You tried to allocate: " + total_allocated_vols.to_s, 42) 
else
	Chef::Log.info('hft-chef-lvm - total amount of requested disks is less then 20: ' + total_allocated_vols.to_s)
end

disk_counter = 0
node['hft-chef-lvm']['arrays'].each do |(lvm_array_name,lvm_array_parms)|
	Chef::Log.info('hft-chef-lvm - Working on: ' + lvm_array_name.to_s + ". with the params of: " + lvm_array_parms.to_s)

#init AWS vars
	lvm_attributes_physical_volumes = [] # init as an array to be ready to collect dev_names from AWS

	aws_params = lvm_array_parms.fetch('aws_attributes', {})
	aws_attributes_ebs_volume_name = aws_params.fetch('aws_ebs_volume_name',nil)
	aws_attributes_volsize = aws_params.fetch('volsize',1)
	aws_attributes_voltype = aws_params.fetch('voltype',"standard")
	aws_attributes_use_piops = aws_params.fetch('use_piops',false)
	aws_attributes_piops = aws_params.fetch('piops',1000)
	aws_attributes_vols = aws_params.fetch('vols',1)
	aws_attributes_device_prefix = aws_params.fetch('device',"/dev/sd")
	aws_attributes_timeout = aws_params.fetch('timeout',nil)
	aws_attributes_snapshot_backup = aws_params.fetch('snapshot_backup',false)
	aws_attributes_snapshot_pre_backup_cmds = aws_params.fetch('snapshot_pre_backup_cmd',[])
	aws_attributes_snapshot_post_backup_cmds = aws_params.fetch('snapshot_post_backup_cmd',[])

	
	#what are the dev letters I should use?
	if aws_params.fetch('linux_dev_letters', []).empty?
		#There are no allocations
		Chef::Log.info("hft-chef-lvm - for lvm_array_name: " + lvm_array_name.to_s + " linux_dev_letters is empty: " + aws_params.fetch('linux_dev_letters', []).to_s)
		node.set['hft-chef-lvm']['arrays'][lvm_array_name]['aws_attributes']['linux_dev_letters'] = []
		aws_attributes_start_device = find_next_letter("f", total_linux_dev_letters)
		
		vergin = true
		for_me_linux_dev_letters = []
	else
		#there are some allocations already
		Chef::Log.info("hft-chef-lvm - for lvm_array_name: " + lvm_array_name.to_s + " linux_dev_letters is happy: " + aws_params.fetch('linux_dev_letters', []).to_s)
		vergin = false
		for_me_linux_dev_letters = aws_params.fetch('linux_dev_letters')
		#assemble the lvm_attributes_physical_volumes from the already existing letters
		for_me_linux_dev_letters.each do |letter|
			lvm_attributes_physical_volumes << aws_attributes_device_prefix.sub("sd", "xvd") + letter # Convert the disk name to xen notation, append the current letter and push into physical_volumes array, to be used by LVM.
		end

		#will we need more disks?
		Chef::Log.info("hft-chef-lvm - for lvm_array_name: " + lvm_array_name.to_s + " will we need more disks?: " + for_me_linux_dev_letters.length.to_s + " vs " + aws_attributes_vols.to_s)
		if for_me_linux_dev_letters.length > aws_attributes_vols
			Chef::Application.fatal!("hft-chef-lvm - Error, this cookbook doesn't support reducing the amount of disks.", 42) 
		end	

		if for_me_linux_dev_letters.length < aws_attributes_vols
			Chef::Log.info("hft-chef-lvm - for lvm_array_name: " + lvm_array_name.to_s + " found that we will need more disks because for_me_linux_dev_letters.length: " + for_me_linux_dev_letters.length.to_s + "is less then aws_attributes_vols: " + aws_attributes_vols.to_s)
			vergin = true
			aws_attributes_vols = aws_attributes_vols - for_me_linux_dev_letters.length
			aws_attributes_start_device = aws_params.fetch('start_device', "f")
			Chef::Log.info("hft-chef-lvm - for lvm_array_name: " + lvm_array_name.to_s + " new aws_attributes_vols is: " + aws_attributes_vols.to_s)
			aws_attributes_start_device = find_next_letter(aws_attributes_start_device,total_linux_dev_letters)
		end
	end

	Chef::Log.info("hft-chef-lvm - Eval for " + Chef::Config[:node_name].to_s + " AWS is:  node[hft-chef-lvm][using_aws] = " + using_aws.to_s + ", on_premise is: "+ node['adallom_base']['on_premise'].to_s + ", attribute is: " + node.attribute?("adallom_role").to_s + " and role is: "+ node["adallom_role"].to_s )
	if ((node['adallom_base']['on_premise'] == 0 and !node.attribute?("adallom_role") and node["adallom_role"] != "AllInOne") or using_aws == true) and !aws_attributes_ebs_volume_name.nil?
		Chef::Log.info("hft-chef-lvm - Found this machine " + Chef::Config[:node_name].to_s + " to be AWS eligible")
		Chef::Log.info("hft-chef-lvm - for lvm_array_name: " + lvm_array_name.to_s + " aws_attributes_ebs_volume_name: " + aws_attributes_ebs_volume_name.to_s)
		Chef::Log.info("hft-chef-lvm - for lvm_array_name: " + lvm_array_name.to_s + " aws_attributes_volsize: " + aws_attributes_volsize.to_s)
		Chef::Log.info("hft-chef-lvm - for lvm_array_name: " + lvm_array_name.to_s + " aws_attributes_use_piops: " + aws_attributes_use_piops.to_s)
		Chef::Log.info("hft-chef-lvm - for lvm_array_name: " + lvm_array_name.to_s + " aws_attributes_piops: " + aws_attributes_piops.to_s)
		Chef::Log.info("hft-chef-lvm - for lvm_array_name: " + lvm_array_name.to_s + " aws_attributes_vols: " + aws_attributes_vols.to_s)
		Chef::Log.info("hft-chef-lvm - for lvm_array_name: " + lvm_array_name.to_s + " aws_attributes_device_prefix: " + aws_attributes_device_prefix.to_s)
		Chef::Log.info("hft-chef-lvm - for lvm_array_name: " + lvm_array_name.to_s + " aws_attributes_start_device: " + aws_attributes_start_device.to_s)
		Chef::Log.info("hft-chef-lvm - for lvm_array_name: " + lvm_array_name.to_s + " aws_attributes_timeout: " + aws_attributes_timeout.to_s)

		0.upto(aws_attributes_vols - 1) do |disk_num|
			if vergin == true # assemble currently working on device name from prefix and disk letter			
				Chef::Log.info("hft-chef-lvm - for lvm_array_name: " + lvm_array_name.to_s + " working on disk number: " + disk_num.to_s + " with disk_counter of : " + disk_counter.to_s)
				disk_letter  = find_next_letter(aws_attributes_start_device,total_linux_dev_letters)
				total_linux_dev_letters << disk_letter
				Chef::Log.info("hft-chef-lvm - new total used by this node are: " + total_linux_dev_letters.flatten.to_s)
				Chef::Log.info("hft-chef-lvm - for lvm_array_name: " + lvm_array_name.to_s + " working on disk latter is: " + disk_letter.to_s)
				dev_name = aws_attributes_device_prefix + disk_letter 
				node.set['hft-chef-lvm']['arrays'][lvm_array_name]['aws_attributes']['linux_dev_letters'] << disk_letter
				ebs_vol = aws_attributes_ebs_volume_name + disk_letter.to_s
				Chef::Log.info("hft-chef-lvm - for lvm_array_name: " + lvm_array_name.to_s + " will now create ebs_vol: " + ebs_vol)
			else
				dev_name = aws_attributes_device_prefix + for_me_linux_dev_letters[disk_num] 
				ebs_vol = aws_attributes_ebs_volume_name + for_me_linux_dev_letters[disk_num].to_s
			end
			Chef::Log.info("hft-chef-lvm - for lvm_array_name: " + lvm_array_name.to_s + " dev_name is: " + dev_name.to_s)
			Chef::Log.info("hft-chef-lvm - for lvm_array_name: " + lvm_array_name.to_s + " ebs_vol is: " + ebs_vol.to_s)

			aws_ebs_volume ebs_vol do
			 	aws_access_key aws['aws_access_key_id']
			 	aws_secret_access_key aws['aws_secret_access_key']
			 	size aws_attributes_volsize
			 	device dev_name
			 	volume_type aws_attributes_voltype
			 	if aws_attributes_use_piops == true
			 		piops aws_attributes_piops
			 	end
			 	if !aws_attributes_timeout.nil?
			 		timeout 600
			 	end
			 	action [ :create, :attach ]
			end
		lvm_attributes_physical_volumes << dev_name.sub("sd", "xvd") unless vergin == false # Convert the disk name to xen notation and push into physical_volumes array, to be used by LVM.
 		end
 		disk_counter += aws_attributes_vols
		Chef::Log.info("hft-chef-lvm - for lvm_array_name: " + lvm_array_name.to_s + " AWS segment's output for lvm_attributes_physical_volumes is: " + lvm_attributes_physical_volumes.to_s)
 	else
		Chef::Log.info("hft-chef-lvm - Found this machine to be UNeligible for AWS, for: " + lvm_array_name.to_s + ", or to not have sufficient information to make the EBS requests")
 	end

	#Init LVM vars
	Chef::Log.info("hft-chef-lvm - lvm_array: " + lvm_array_name.to_s)
	Chef::Log.info("hft-chef-lvm - for lvm_array_name: " + lvm_array_name.to_s + " lvm_array_parms: " + lvm_array_parms.to_s)
	
	lvm_attributes_physical_volumes = lvm_array_parms.fetch('physical_volumes',[]) unless using_aws == true
	
	lvm_params = lvm_array_parms.fetch('lvm_attributes', {})
	Chef::Log.info("hft-chef-lvm - for lvm_array_name: " + lvm_array_name.to_s + " LVM attributes for this array are: " + lvm_attributes_physical_volumes.to_s + " as VG devices")
	lvm_attributes_volume_group = lvm_params.fetch('volume_group', nil)
	Chef::Log.info("hft-chef-lvm - for lvm_array_name: " + lvm_array_name.to_s + " lvm_attributes_volume_group: " + lvm_attributes_volume_group.to_s)
	lvm_attributes_logical_volume = lvm_params.fetch('logical_volume', nil)
	Chef::Log.info("hft-chef-lvm - for lvm_array_name: " + lvm_array_name.to_s + " lvm_attributes_logical_volume: " + lvm_attributes_logical_volume.to_s)
	lvm_attributes_lv_stripes = lvm_params.fetch('lvm_lv_stripes', 1)
	Chef::Log.info("hft-chef-lvm - for lvm_array_name: " + lvm_array_name.to_s + " lvm_attributes_lv_stripes: " + lvm_attributes_lv_stripes.to_s)
	lvm_attributes_filesystem = lvm_params.fetch('filesystem', "ext4")
	Chef::Log.info("hft-chef-lvm - for lvm_array_name: " + lvm_array_name.to_s + " lvm_attributes_filesystem: " + lvm_attributes_filesystem.to_s)
	lvm_attributes_mount_point = lvm_params.fetch('mount_point', {})
	Chef::Log.info("hft-chef-lvm - for lvm_array_name: " + lvm_array_name.to_s + " lvm_attributes_mount_point: " + lvm_attributes_mount_point.to_s)
	lvm_attributes_mount_options = lvm_params.fetch('mount_options', "rw,noatime,nodiratime")
	Chef::Log.info("hft-chef-lvm - for lvm_array_name: " + lvm_array_name.to_s + " lvm_attributes_mount_options: " + lvm_attributes_mount_options.to_s)
	lvm_attributes_stripe_size = lvm_params.fetch('stripe_size', 512)
	Chef::Log.info("hft-chef-lvm - for lvm_array_name: " + lvm_array_name.to_s + " lvm_attributes_stripe_size: " + lvm_attributes_stripe_size.to_s)


	Chef::Log.info('hft-chef-lvm - Starting to LVM')
	
	if !lvm_attributes_mount_point.kind_of?(Hash)
		Chef::Application.fatal!("hft-chef-lvm - for lvm_array_name: " + lvm_array_name.to_s + " The \"mount point\", must be a hash that contains the \"location\" key.", 42) 
	end

	if !lvm_attributes_physical_volumes.empty? and !lvm_attributes_volume_group.nil? and !lvm_attributes_logical_volume.empty? and !lvm_attributes_mount_point.fetch('location', nil).nil?
		Chef::Log.info('hft-chef-lvm - ' + lvm_array_name.to_s + ' has the following running mount point: ' + lvm_attributes_mount_point.fetch('running_mount', nil).to_s)
		if lvm_attributes_mount_point.fetch('running_mount', nil).nil?
			running_mount = lvm_attributes_mount_point["location"]
			node.set['hft-chef-lvm']['arrays'][lvm_array_name]['lvm_attributes']['mount_point']['running_mount'] = running_mount
		else
			running_mount = lvm_attributes_mount_point.fetch('running_mount')
		end

		if running_mount.nil? or (running_mount == lvm_attributes_mount_point["location"])
			directory lvm_attributes_mount_point["location"] do
				owner lvm_attributes_mount_point["user"] unless lvm_attributes_mount_point["user"].nil?
				group lvm_attributes_mount_point["group"] unless lvm_attributes_mount_point["group"].nil?
				mode lvm_attributes_mount_point["mode"] unless lvm_attributes_mount_point["mode"].nil?
				action :create
				recursive true
				#not_if { ::Dir.exist?(running_mount) and ( Pathname.new(running_mount).stat().uid == `stat #{running_mount} -c %u` ) } 
				not_if { ::Dir.exist?(running_mount) and ( !lvm_attributes_mount_point["user"].nil? and lvm_attributes_mount_point["user"] == `stat #{running_mount} -c %U` ) } 
			end
		else
			Chef::Application.fatal!("hft-chef-lvm - This cookbook, does NOT support changing the running mount point. manually unmount it ,delete the attribute of 'running_mount' on the node on the chef server and then run chef-client.", 42) 
		end

		Chef::Log.info("hft-chef-lvm - for lvm_array_name: " + lvm_array_name.to_s + " LVM disk allocations found, using " + lvm_attributes_physical_volumes.to_s + " as VG devices")
		#Do we have enough disks?
		if aws_attributes_vols <= 0 or aws_attributes_vols % lvm_attributes_lv_stripes != 0
			Chef::Application.fatal!("hft-chef-lvm - You must have enough disks to satisfy the striping demand.", 42) 
		else
			Chef::Log.info("hft-chef-lvm - for lvm_array_name: " + lvm_array_name.to_s + " Thinking there are enough disks to satisfy stripes")
		end

		lvm_volume_group lvm_attributes_volume_group do
		    physical_volumes lvm_attributes_physical_volumes
		    action [ :create, :extend ]
		    logical_volume lvm_attributes_logical_volume do
		        size '100%VG'
		        filesystem lvm_attributes_filesystem
		        mount_point  :location =>  lvm_attributes_mount_point["location"], options: lvm_attributes_mount_options, :dump => 0, :pass => 0
		        stripes lvm_attributes_lv_stripes
		        action [ :create, :resize ]
		        take_up_free_space true
		        stripe_size lvm_attributes_stripe_size
		    end
		end
		#Should this logical volume group be backed-up?
			if aws_attributes_snapshot_backup == true
				Chef::Log.info("hft-chef-lvm - Adallom_backups - for lvm_array_name: " + lvm_array_name.to_s + " invoking backup, because aws_attributes_snapshot_backup was: " + aws_attributes_snapshot_backup.to_s)
				node.set["adallom_backup"]["devices_to_backup"][lvm_attributes_volume_group]["location"] = lvm_attributes_volume_group
				node.set["adallom_backup"]["devices_to_backup"][lvm_attributes_volume_group]["type"] = "LVM"
				node.set["adallom_backup"]["devices_to_backup"][lvm_attributes_volume_group]["pre_backup_cmd"] = aws_attributes_snapshot_pre_backup_cmds
				node.set["adallom_backup"]["devices_to_backup"][lvm_attributes_volume_group]["post_backup_cmd"] = aws_attributes_snapshot_post_backup_cmds
				Chef::Log.info("hft-chef-lvm - Adallom_backups - Done a node set for adallom_backup.devices_to_backup." + lvm_attributes_volume_group.to_s + ". Location: " + lvm_attributes_volume_group.to_s + ", Type: r, aws_attributes_snapshot_pre_backup_cmds: " + aws_attributes_snapshot_pre_backup_cmds.to_s + " and aws_attributes_snapshot_pre_backup_cmds: " + aws_attributes_snapshot_post_backup_cmds.to_s)
				node.set["adallom_backup"]["devices_to_backup"][lvm_attributes_volume_group + "_physical"]["location"] = lvm_attributes_physical_volumes
				node.set["adallom_backup"]["devices_to_backup"][lvm_attributes_volume_group + "_physical"]["type"] = "r"
				node.set["adallom_backup"]["devices_to_backup"][lvm_attributes_volume_group + "_physical"]["pre_backup_cmd"] = aws_attributes_snapshot_pre_backup_cmds
				node.set["adallom_backup"]["devices_to_backup"][lvm_attributes_volume_group + "_physical"]["post_backup_cmd"] = aws_attributes_snapshot_post_backup_cmds
				Chef::Log.info("hft-chef-lvm - Adallom_backups - Done a node set for adallom_backup.devices_to_backup." + lvm_attributes_volume_group.to_s + "_physical. Location: " + lvm_attributes_physical_volumes.to_s + ", Type: r, aws_attributes_snapshot_pre_backup_cmds: " + aws_attributes_snapshot_pre_backup_cmds.to_s + " and aws_attributes_snapshot_pre_backup_cmds: " + aws_attributes_snapshot_post_backup_cmds.to_s)

				node.save
				include_recipe "adallom_backup"
				Chef::Log.info("hft-chef-lvm - Adallom_backups - invoked backup with lvm_attributes_volume_group of: " + lvm_attributes_volume_group.to_s + " and lvm_attributes_physical_volumes of: " + lvm_attributes_physical_volumes.to_s)
			end
	else
		Chef::Log.info("hft-chef-lvm - for lvm_array_name: " + lvm_array_name.to_s + " There are insufficient LVM attributes configured to create the array, so creating the LVM was skipped")
		if node["type"] == "operational"
	  		Chef::Application.fatal!("hft-chef-lvm - On an Operational env, you MUST have the LVM setup.", 42) 
		end
	end
 end
Chef::Log.info('hft-chef-lvm - End of LVM')

