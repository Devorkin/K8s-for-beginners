# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|

  # Variables
  NUM_OF_MACHINES = 4
  
  # Plugins check
  unless Vagrant.has_plugin?("vagrant-hosts")
    raise 'vagrant-hosts is not installed! "vagrant plugin install vagrant-hosts" is needed to be ran first!'
  end
  unless Vagrant.has_plugin?("vagrant-vbguest")
    raise 'vagrant-vbguest is not installed! "vagrant plugin install vagrant-vbguest" is needed to be ran first!'
  end

  if Vagrant::Util::Platform.windows? then
    unless Vagrant.has_plugin?("virtualbox_WSL2")
      raise 'virtualbox_WSL2 is not installed! "vagrant plugin install virtualbox_WSL2" is needed to be ran first!'
    end
  end

  # Default VM configuration
  config.vm.box = "ubuntu/jammy64"

  # Default Virtualbox provider configuration
  config.vm.provider "virtualbox" do |vb|
    # UI
    vb.gui = false

    # VM virtual-hardware spec
    vb.customize ["modifyvm", :id, "--cpus", "4"]
    vb.customize ["modifyvm", :id, "--memory", 4096]
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

  config.vm.define 'master' do |node|
    node.vm.hostname = 'master.tests.net'
    node.vm.network "private_network", ip: "192.168.57.110"
    node.vm.network "forwarded_port", guest: 6443, host: 6443, protocol: "tcp"
    node.vm.provision :shell, path: './provision_scripts/master.sh'
  end
  
  (1..NUM_OF_MACHINES).each do |i|
    config.vm.define "node#{i}" do |node|
      node.vm.hostname = "node#{i}.tests.net"
      node.vm.network "private_network", ip: "192.168.57.1#{i}"
      for port in 30200..30219 do
        host_port = "#{port - 20000 + i * 1000}"
        node.vm.network "forwarded_port", guest: "#{port}", host: "#{host_port}", protocol: "tcp"
      end
      node.vm.provision :shell, path: './provision_scripts/worker_node.sh'
    end
  end
end
