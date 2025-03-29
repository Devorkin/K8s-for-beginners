# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|

  # Variables
  allow_additional_disk = false
  vm_ram_capacity = 4096

  NUM_OF_MACHINES = 4

  PROVISION_CEPH = "false"
  if PROVISION_CEPH == "true"
    additional_disk_size = 30 * 1024          # 30GB by default

    unless allow_additional_disk == true
      raise 'Ceph setup requires additional disks to be Enabled.'
    end
    unless NUM_OF_MACHINES >= 3
      raise 'Ceph setup requires atleast 3 nodes!'
    end
    unless vm_ram_capacity >= 4096
      raise 'Ceph setup requires each Ceph node to have atleast 4GB of RAM!'
    end
  end
  PROVISION_CERT_MANAGER = "true"
  PROVISION_INGRESS_NGINX = "true"
  PROVISION_PROMETHEUS = "true"
  PROVISION_SELF_SIGNED_CA_CRT = "true"

  # VM OS-environments setup
  ARGS = [PROVISION_CEPH, PROVISION_SELF_SIGNED_CA_CRT, PROVISION_CERT_MANAGER, PROVISION_INGRESS_NGINX, PROVISION_PROMETHEUS]
  $set_environment_variables = <<SCRIPT
tee "/etc/profile.d/vagrant-setup.sh" > "/dev/null" <<EOF
export PROVISION_CEPH="$1"
export PROVISION_SELF_SIGNED_CA_CRT="$2"
export PROVISION_CERT_MANAGER="$3"
export PROVISION_INGRESS_NGINX="$4"
export PROVISION_PROMETHEUS="$5"
EOF
SCRIPT

  # Plugins check
  unless Vagrant.has_plugin?("vagrant-hosts")
    raise 'vagrant-hosts is not installed! "vagrant plugin install vagrant-hosts" is needed to be ran first!'
  end
  #unless Vagrant.has_plugin?("vagrant-vbguest")
  #  raise 'vagrant-vbguest is not installed! "vagrant plugin install vagrant-vbguest" is needed to be ran first!'
  #end

  # Default VM configuration
  config.vm.box = "ubuntu/jammy64"

  # Default Virtualbox provider configuration
  config.vm.provider "virtualbox" do |vb|
    # UI
    vb.gui = false

    # VM virtual-hardware spec
    vb.customize ["modifyvm", :id, "--cpus", "4"]
    vb.customize ["modifyvm", :id, "--memory", vm_ram_capacity]
    vb.customize ["modifyvm", :id, "--uartmode1", "disconnected" ]
    vb.customize ["guestproperty", "set", :id, "/VirtualBox/GuestAdd/VBoxService/--timesync-set-threshold", 10000]
  end

  # Hosts configuration
  config.vm.provision :hosts do |provisioner|
    provisioner.sync_hosts = true
    provisioner.autoconfigure = true
    provisioner.imports = ['global', 'virtualbox']
    provisioner.exports = {
      'virtualbox' => [
        ['@vagrant_private_networks', ['@vagrant_hostnames']],
      ],
    }
  end

  # VMs setups
  config.vm.define 'master' do |node|
    node.vm.provider "virtualbox" do |vb|
      vb.customize ["modifyvm", :id, "--memory", 3072]
    end
    node.vm.hostname = 'master.tests.net'
    node.vm.network "private_network", ip: "192.168.57.110"
    node.vm.network "forwarded_port", guest: "30208", host: "30208", protocol: "tcp"
    node.vm.network "forwarded_port", guest: "30209", host: "30209", protocol: "tcp"
    node.vm.provision :shell, inline: $set_environment_variables, run: "always", args: ARGS
    node.vm.provision :shell, path: './provision_scripts/master.sh'
  end

  (1..NUM_OF_MACHINES).each do |i|
    config.vm.define "node#{i}" do |node|
      # Network configuration
      node.vm.hostname = "node#{i}.tests.net"
      node.vm.network "private_network", ip: "192.168.57.1#{i}"
      for port in 30200..30219 do
        host_port = "#{port - 20000 + i * 1000}"
        node.vm.network "forwarded_port", guest: "#{port}", host: "#{host_port}", protocol: "tcp"
      end
      for port in 30900..30903 do
        host_port = "#{port - 20000 + i * 1000}"
        node.vm.network "forwarded_port", guest: "#{port}", host: "#{host_port}", protocol: "tcp"
      end

      # Attach additional disk device
      if allow_additional_disk == true
        node.vm.provider "virtualbox" do |vb|
          osd_disk = "./osd_disk_#{i}.vdi"
          unless File.exist?(osd_disk)
            vb.customize ['createhd', '--filename', osd_disk, '--size', additional_disk_size]
          end
          vb.customize ['storageattach', :id, '--storagectl', 'SCSI', '--port', 2, '--device', 0, '--type', 'hdd', '--medium', osd_disk]
        end
      end

      # Provisioner
      node.vm.provision :shell, path: './provision_scripts/worker_node.sh'
    end
  end
end
