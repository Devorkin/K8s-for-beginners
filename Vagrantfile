Vagrant.configure("2") do |config|
    config.vbguest.auto_update = true
    config.vm.provider "virtualbox"

    # Vagrant minimum requierments:
    wantedversion = '2.0.0'
    if Gem::Version.new(Vagrant::VERSION) < Gem::Version.new(wantedversion)
        raise "Your Vagrant software is too old (#{Vagrant::VERSION}) - Please update it to at least #{wantedversion}!"
    end

    # Plugins confirmation
    unless Vagrant.has_plugin?("vagrant-hosts")
        puts "vagrant-hosts plugin is missing!\nWill install it now."
        system('vagrant plugin install vagrant-hosts')
    end

    unless Vagrant.has_plugin?("vagrant-vbguest")
        puts "vagrant-vbguest plugin is missing!\nWill install it now."
        system('vagrant plugin install vagrant-vbguest')
    end

    config.vm.provision :hosts do |provisioner|
        provisioner.add_host '192.168.70.8', [
            'node1.local'
        ]
        provisioner.add_host '192.168.70.9', [
            'node2.local'
        ]
    end

    config.vm.define "Node1" do |node1|
        node1.vbguest.auto_update = false
        node1.vm.box = "ubuntu/bionic64"
        node1.vm.hostname = "node1.local"
        node1.vm.network :public_network
        node1.vm.network :private_network, ip: "192.168.70.8", :adapter => 2
        # node1.vm.network :forwarded_port, guest: 4149, host: 4149, id: "Kubelet-Containers metrics", auto_correct: true
        # node1.vm.network :forwarded_port, guest: 6443, host: 6443, id: "Kube-API Server", auto_correct: true
        # node1.vm.network :forwarded_port, guest: 10250, host: 10250, id: "Kubelet - API", auto_correct: true
        # node1.vm.network :forwarded_port, guest: 10255, host: 10255, id: "Kubelet - Nodes state", auto_correct: true
        # node1.vm.network :forwarded_port, guest: 10256, host: 10256, id: "Kube-proxy", auto_correct: true
        # node1.vm.network :forwarded_port, guest: 9099, host: 9099, id: "Calico-Canal", auto_correct: true
        # for p in 30000..32767 do
        #     node1.vm.network :forwarded_port, guest: p, host: p, id: "#{p}_port", auto_correct: true
        # end
        node1.vm.provider "virtualbox" do |node1ADV|
            node1ADV.customize ["modifyvm", :id, "--cpus", "2"]
            node1ADV.customize ["modifyvm", :id, "--memory",5120]
            node1ADV.customize ["guestproperty", "set", :id, "/VirtualBox/GuestAdd/VBoxService/--timesync-set-threshold", 10000]
        end
        node1.vm.provision :shell, :inline => "sudo /vagrant/Scripts/K8s/node1.sh", run: "always"
    end

    config.vm.define "Node2" do |node2|
        node2.vbguest.auto_update = false
        node2.vm.box = "ubuntu/bionic64"
        node2.vm.hostname = "node2.local"
        node2.vm.network :public_network
        node2.vm.network :private_network, ip: "192.168.70.9", :adapter => 2
        # node2.vm.network :forwarded_port, guest: 4149, host: 44149, id: "Kubelet-Containers metrics", auto_correct: true
        # node2.vm.network :forwarded_port, guest: 6443, host: 46443, id: "Kube-API Server", auto_correct: true
        # node2.vm.network :forwarded_port, guest: 10250, host: 40250, id: "Kubelet - API", auto_correct: true
        # node2.vm.network :forwarded_port, guest: 10255, host: 40255, id: "Kubelet - Nodes state", auto_correct: true
        # node2.vm.network :forwarded_port, guest: 10256, host: 40256, id: "Kube-proxy", auto_correct: true
        # node2.vm.network :forwarded_port, guest: 9099, host: 49099, id: "Calico-Canal", auto_correct: true
        # for p in 0..2767 do
        #     guest_port=30000+p
        #     host_port=50000+p
        #     node2.vm.network :forwarded_port, guest: guest_port, host: host_port, id: "#{host_port}_port", auto_correct: true
        # end
        node2.vm.provider "virtualbox" do |node2ADV|
            node2ADV.customize ["modifyvm", :id, "--cpus", "2"]
            node2ADV.customize ["modifyvm", :id, "--memory", 5120]
            node2ADV.customize ["guestproperty", "set", :id, "/VirtualBox/GuestAdd/VBoxService/--timesync-set-threshold", 10000]
        end
        node2.vm.provision :shell, :inline => "sudo /vagrant/Scripts/K8s/node2.sh", run: "always"
    end
end
