# Ruby RSMP
This is a Ruby implementation of the RSMP protocol, including:
 - RSMP classes (engine) that can be used to build RSMP tools
 - Ruby command-line tools for starting RSMP supervisors or sites
 - An initial set of Cucumber tests for testing RSMP implemenetations.

The code has so far only been tested on Mac.

## Installation
You need a recent version of Ruby intalled. Latest is recommended.

Install required gems:
$ gem intall bundler
$ bundle

## Ruby classes 
A set of classes that represents RSMP messages, supervisors and sites and handles connecting,
exchanging version information, acknowledging messages and other RSMP protocol specifics.

## Command-line tool
Tools for easily running RSMP supervisors and sites.

### supervisor
The "supervisor" command will start an RSMP supervisor (server), which equipment can connect to.
Here's a an example of how the RSMP simuator connects to our supervisor:

$ ./supervisor
                         Site connected from ::ffff:10.202.183.252:57454
AA+BBCCC=DDD  -->  4234  Received Version message for sites [AA+BBCCC=DDD] using RSMP 3.1.4
AA+BBCCC=DDD             Starting timeout checker with interval 1 seconds
AA+BBCCC=DDD  <--  564c  Sent Version
AA+BBCCC=DDD             Connection to site established
AA+BBCCC=DDD             Starting watchdog with interval 1 seconds
AA+BBCCC=DDD  -->  d032  Received AggregatedStatus status [local_control, normal]


When starting, the supervisor will read setting from the file comnfig/supervisor.yaml, including the port to listen to and the rsmp version that's supported. THe settings file can also be used to adjust what will be logged, and whether to colorize the output.


### site
The "site" tool will start an RSMP site. Settings will be read from the file comnfig/supervisor.yaml, including
what supervisor to connect to, reconnect interval, etc. Here's an example of the site site connecting to a Ruby supervisor:

$ ./site
                         Starting site RN+RC4443 on port 12111
              <--  49c5  Sent Version
              -->  3356  Received MessageAck for Version 49c5
RN+RS0001     -->  c517  Received Version message for sites [RN+RS0001] using RSMP 3.1.4
RN+RS0001                Starting timeout checker with interval 1 seconds
RN+RS0001     <--  1c30  Sent MessageAck for Version c517
RN+RS0001                Connection to supervisor established
RN+RS0001                Starting watchdog with interval 1 seconds

## Cucumber tests
Since cucumber is installed via bundler, it's recommended to run via bundle exec: 
$ bundle exec cucumber

Connection settings used in cucumber tests are stored in features/support/supervisor.yaml.


## RSMP Simulator / VirtualBox setup
You can use the RSMP simulator to interact with the command-line tools or the Cucumber tests.

The RSMP Simulator is a Windows application. If you run the RSMP simulator in Virtualbox, you need to use setup networking so the guest OS can communicate with the host OS.


Create a network in VirtualBox global preferences. Turn off DHCP and add a port forwarding rute with host ip: empty, host port: 12111, guest post: 12111. The guest ip must be set to ip of the host. To find the guest ip, start the VM and run the "cmd". Then type "ipconfig" and enter. The ip is shown in IPv4Address.

Open the VM network settings, and pick the newly created network.


In the VM, the RSMP simulator must be set to connect to the ip of the host. For the site simulator this is setup be editing the file:
Program Files (x86)/RSMPSG1/Settings/RSMPSG1.INI

Edit the line:
IPAddress=111.111.111.111:12111

Change the ip to the ip of the host. The host ip can be found (if you're on Mac) by opening System Preferences > Network in the host. The IP is in "IP Address".






