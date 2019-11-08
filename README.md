# rsmp-ruby
This is a Ruby implementation of the RSMP protocol, including:
 - RSMP classes (engine) that can be used to build RSMP tools
 - Ruby command-line tools for starting RSMP supervisors or sites

The code has so far only been tested on Mac.

## Installation
You need a recent version of Ruby intalled. 2.6.3 or later is recommended.

Install required gems:

```console
$ gem intall bundler
$ bundle
```

Install git submodules:
The JSON Schema is is included as a git submodule. To install it run:

```console
$ git submodule init     # initialize local submodule config
$ git submodule update   # fetch submodules
```

Alternatively, you can pass --recurse-submodules to the git clone command, and it will automatically initialize and update each submodule in the repository.

## Ruby classes 
A set of classes that represents RSMP messages, supervisors and sites and handles connecting, exchanging version information, acknowledging messages and other RSMP protocol specifics.

### Async
The 'async' gem is used to handle concurrency. It's based on the reactor pattern. All communication runs in a single thread, but using fibers to switch between tasks whenever an IO operation is blocked.

If you want to do things concurrently that involves the RSMP classes, you should use the async mechanism.

### Site
The RSMP::Site class can be used to run a site. A site will try to connect to one or more supervisor.

```ruby
require 'rsmp'
site = RSMP::Site.new.start
```

This will use the default settings, which will try to connect to a supervisor on the localhost 127.0.0.1, port 12111, and will show log output. It will keep running until you stop it with cntr-c.

### Supervisor
The RSMP::Supervisor class can be used to run a supervisor. It will listen for sites to connect. It can either accept all sites, or validate them against a whitelist.

```ruby
require 'rsmp'
supervisor = RSMP::Supervisor.new.start
```

This will use the default settings, which will listen on port 12111, accept all connecting sites and will show log output. It will keep running until you stop it with cntr-c.

### Settings
You can pass settings to sites and supervisors to control ip adresseses, ports, login and other behaviour:

```ruby
require 'rsmp'
settings = {
  'site_id' => 'RN+SI0001',			# site id
  'supervisors' => [				# list of supervisor to connect to
    { 'ip' => '127.0.0.1', 'port' => 12111 }		# ip and port
  ],
  'log' => {
    'json' => true,			# show raw json messages in log
  }
}
site = RSMP::Site.new(site_settings:settings).start
```

See site.rb and supervisor.rb for a list of settings and their default values.

### Concurrency
The RSMP gem uses the "async" gem to handle concurrency. Here's how to run a site as an asynchronous task, so you can do other things while the site is running. Here we also disable the log output from the site:

```ruby
require 'rsmp'
settings = {
  'log' => { 'active' => false }
}
Async do |task|
  task.async do
    site = RSMP::Site.new(site_settings:settings).start
  end
  puts "RSMP site is now running"
end
```

## Command-line tool
Tools for easily running RSMP supervisors and sites. The command is called rsmp.

### Running a supervisor
The 'supervisor' command will start an RSMP supervisor (server), which equipment can connect to:

```console
$ rsmp supervisor
2019-08-26 11:48:58 UTC                           Starting supervisor RN+SU0001 on port 12111
2019-08-26 11:49:49 UTC                           Site connected from 127.0.0.1:57138
2019-08-26 11:49:49 UTC  RN+SI0001     -->  2b20  Received Version message for sites [RN+SI0001] using RSMP 3.1.4
2019-08-26 11:49:49 UTC  RN+SI0001     <--  1168  Sent Version
2019-08-26 11:49:49 UTC  RN+SI0001                Connection to site RN+SI0001 established
2019-08-26 11:49:49 UTC  RN+SI0001     -->  f912  Received AggregatedStatus status []
```

### Running a site
The 'site' command will start an RSMP site, which will try to connect to one or more supervisor. Here's an example of the site connecting to a Ruby supervisor:

```console
$ rsmp site
                         Starting site RN+RC4443 on port 12111
              <--  49c5  Sent Version
              -->  3356  Received MessageAck for Version 49c5
RN+RS0001     -->  c517  Received Version message for sites [RN+RS0001] using RSMP 3.1.4
RN+RS0001                Starting timeout checker with interval 1 seconds
RN+RS0001     <--  1c30  Sent MessageAck for Version c517
RN+RS0001                Connection to supervisor established
RN+RS0001                Starting watchdog with interval 1 seconds
```

### CLI help and options.
Use ```--help <command>``` to get a list of available options.

Use --config <path> to point to a .yaml config file, controlling things like IP adresses, ports, and log output. Examples of config files can be found the folder config/. 

## Cucumber tests
A suite of cucumber tests can be used to test RSMP communication.

It currently focuses on testing sites. It will therefore run an internal supervisor, and tests the communication with the an external) site.

However, cucumber can optionally also run an internal site. In this case all tests can be run quickly, since reconnect delays are eliminated.

### Installing cucumber
Since cucumber is installed via bundler, it's recommended to run via bundle exec: 
$ bundle exec cucumber

### Tests
RSpec tests are located in spec/. The tests will start supervisor and sites to test communication, but will do so on port 13111, rather than the usual port 12111, to avoid inferference with other RMSP processes running locally.

Note that these tests are NOT intented for testing external equipemnt or systems. The tests are for validating the code in this repository.

Run all tests by using:

```console
$ rspec
.........................

Finished in 0.12746 seconds (files took 0.6571 seconds to load)
25 examples, 0 failures

```

Check the RSpec documentation for how to run selected tests.

