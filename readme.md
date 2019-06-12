 
# Ruby RSMP
This is a Ruby implementation of the RSMP protocol.

## Command-line tool
The "rsmp" tool can by used to start an RSMP supervisor server, which equipment can connect to:

$ ruby ./rsmp

The script reads settigns from the file ./rsmp.yml, including the port to listen to and the rsmp version that's supported.



## Cucumber tests
First install requiered gems

$ gem install bundler
$ bundle

Then run the tests:
$ bundle exec cucumber

Connection settings used in cucumber tests are stored in features/scenarios/connecting.yml


## RSMP Simulator / VirtualBox setup
You can use the RSMP simulator to interact with the rsmp script or the Cucumber tests.

The RSMP Simulator is a Windows application. If you run the RSMP simulator in Virtualbox, you need to use setup networking so the guest OS can communicate with the host OS.


Create a network in VirtualBox global preferences. Ignore this, since it seems there's a bug with the first network in the list.

Create another network in VirtualBox global preferences. Turn off DHCP and add a port forwarding rute with host ip: empty, host port: 12111, guest post: 12111. The guest ip must be set to ip of the host. To find the guest ip, start the VM and run the "cmd". Then type "ipconfig" and enter. The ip is shown in IPv4Address.

Open the VM network settings, and pick the newly created network.


In the VM, the RSMP simulator must be set to connect to the ip of the host. This is setup be editing the file:
Program Files (x86)/RSMPSG1/Settings/RSMPSG1.INI

Edit the line:
IPAddress=10.202.182.252:12111

Change the ip to the ip of the host. The host ip can be found (if you're on Mac) by opening System Preferences > Network in the host. The IP is in IP Address.






