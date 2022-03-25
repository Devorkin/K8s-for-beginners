# -*- mode: ruby -*-
# vi: set ft=ruby :

# All Vagrant configuration is done below. The "2" in Vagrant.configure
# configures the configuration version (we support older styles for
# backwards compatibility). Please don't change it unless you know what
# you're doing.
Vagrant.configure("2") do |config|
  # The most common configuration options are documented and commented below.
  # For a complete reference, please see the online documentation at
  # https://docs.vagrantup.com.

  # Every Vagrant development environment requires a box. You can search for
  # boxes at https://vagrantcloud.com/search.
  # config.vm.box = "ubuntu/focal64"
  # config.vm.box = "Ubuntu-20.04.3"
  config.vm.box = "bento/ubuntu-20.04"

  if Vagrant::Util::Platform.windows? then
    # Plugins check
    unless Vagrant.has_plugin?("virtualbox_WSL2")
      raise 'virtualbox_WSL2 is not installed! "vagrant plugin install virtualbox_WSL2" is needed to be ran first!'
    end
    unless Vagrant.has_plugin?("vagrant-hosts")
      raise 'vagrant-hosts is not installed! "vagrant plugin install vagrant-hosts" is needed to be ran first!'
    end
    unless Vagrant.has_plugin?("vagrant-vbguest")
      raise 'vagrant-vbguest is not installed! "vagrant plugin install vagrant-vbguest" is needed to be ran first!'
    end
  end
  # Disable automatic box update checking. If you disable this, then
  # boxes will only be checked for updates when the user runs
  # `vagrant box outdated`. This is not recommended.
  # config.vm.box_check_update = false

  # Create a forwarded port mapping which allows access to a specific port
  # within the machine from a port on the host machine. In the example below,
  # accessing "localhost:8080" will access port 80 on the guest machine.
  # NOTE: This will enable public access to the opened port
  # config.vm.network "forwarded_port", guest: 80, host: 8080

  # Create a forwarded port mapping which allows access to a specific port
  # within the machine from a port on the host machine and only allow access
  # via 127.0.0.1 to disable public access
  # config.vm.network "forwarded_port", guest: 80, host: 8080, host_ip: "127.0.0.1"

  # Create a private network, which allows host-only access to the machine
  # using a specific IP.
  # config.vm.network "private_network", ip: "192.168.33.10"

  # Create a public network, which generally matched to bridged network.
  # Bridged networks make the machine appear as another physical device on
  # your network.
  # config.vm.network "public_network"

  # Share an additional folder to the guest VM. The first argument is
  # the path on the host to the actual folder. The second argument is
  # the path on the guest to mount the folder. And the optional third
  # argument is a set of non-required options.
  # config.vm.synced_folder "../data", "/vagrant_data"

  # Provider-specific configuration so you can fine-tune various
  # backing providers for Vagrant. These expose provider-specific options.
  # Example for VirtualBox:
  #
  config.vm.provider "virtualbox" do |vb|
    # UI
    vb.gui = false

    # VM virtual-hardware spec
    vb.customize [ "modifyvm", :id, "--uartmode1", "disconnected" ]
    vb.customize  ["guestproperty", "set", :id, "/VirtualBox/GuestAdd/VBoxService/--timesync-set-threshold", 10000]
  end

  config.vm.provision :hosts do |provisioner|
    provisioner.add_host '10.10.10.101', [
        'node1.tests.net'
    ]
    provisioner.add_host '10.10.10.102', [
        'node2.tests.net'
    ]
  end
  
  # Enable provisioning with a shell script. Additional provisioners such as
  # Ansible, Chef, Docker, Puppet and Salt are also available. Please see the
  # documentation for more information about their specific syntax and use.
  # config.vm.provision "shell", inline: <<-SHELL
  #   apt-get update
  #   apt-get install -y apache2
  # SHELL
  config.vm.define 'node1' do |node1|
    node1.vm.provider "virtualbox" do |node1ADV|
      node1ADV.customize ["modifyvm", :id, "--cpus", "4"]
      node1ADV.customize ["modifyvm", :id, "--memory", 4096]
    end
    node1.vm.network 'private_network', ip: '10.10.10.101'
    node1.vm.hostname = 'node1.tests.net'
    node1.vm.provision :shell, path: 'node1.sh'
  end
  
  config.vm.define 'node2' do |node2|
    node2.vm.provider "virtualbox" do |node2ADV|
      node2ADV.customize ["modifyvm", :id, "--cpus", "4"]
      node2ADV.customize ["modifyvm", :id, "--memory", 4096]
    end    
    node2.vm.network 'private_network', ip: '10.10.10.102'
    node2.vm.hostname = 'node2.tests.net'
    node2.vm.provision :shell, path: 'node2.sh'
  end

  # config.vm.define 'testbox' do |testbox|
  #   testbox.vm.box = "generic/alpine38"
  #   testbox.vm.provider "virtualbox" do |testbox2ADV|
  #     testbox2ADV.customize ["modifyvm", :id, "--cpus", "2"]
  #     testbox2ADV.customize ["modifyvm", :id, "--memory", 2048]
  #   end
  # end
end
