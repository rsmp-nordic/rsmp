# rsmp
This is a Ruby implementation of the RSMP protocol, including:
 - RSMP classes that can be used to build tests or other RSMP tools
 - Command-line tools for quickly running RSMP supervisors or sites and view messages exchanged

## Installation
You need a recent version of Ruby intalled. 2.6.3 or later is recommended.

Install required gems:

```console
$ gem install bundler
$ bundle
```

## Usage
### Site and Supervisor
The RSMP::Site and RSMP::Supervisor classes can be used to run a RSMP site.

```ruby
require 'rsmp'
RSMP::Site.new.start 		# run site until Ctlr-C is pressed
```

```ruby
require 'rsmp'
RSMP::Supervisor.new.start  		# run supervisor until Ctlr-C is pressed
```

Be default, a site will try to connect to a single supervisor on localhost 127.0.0.1, port 12111. By default, a supervisor will listen for sites on port 12111 and accept any site.

You can pass options to control ip adresseses, ports, logging and other behaviour:

Configuration files can be loaded from YAML using the CLI or the options classes. These are validated
against JSON schemas and will raise errors with details on what is wrong.

```ruby
require 'rsmp'
settings = {
  'site_id' => 'RN+SI0001',			# site id
  'supervisors' => [						# list of supervisor to connect to
    { 'ip' => '127.0.0.1', 'port' => 12111 }		# ip and port
  ],
  'log' => {
    'json' => true,		# show raw json messages in log
  }
}
RSMP::Site.new(site_settings:settings)
```

### Concurrency
The [async](https://github.com/socketry/async) and [async-io](https://github.com/socketry/async-io) gems are used to handle concurrency. Everything happens in a single thread, but fibers are used to switch between tasks whenever an IO operation blocks.

If you start a site or a supervisor inside an Async block, it will run concurrently:

```ruby
require 'rsmp'
settings = {
  'log' => { 'active' => false }    # disable log output
}
Async do |task|
  site = RSMP::Site.new(site_settings:settings)
  site.start 					# run concurrently since we're inside an Async block
  loop do
    task.sleep 1			# use task.sleep() instead of sleep() to avoid blocking
    puts "Latest archive item: #{site.archive.items.last}"
  end
end
```

Use task.show_hierarchy to see what task are created, task.stop() to stop all sites and supervisors running inside it:

```ruby
require 'rsmp'
Async do |task|
  RSMP::Site.new.start
  task.sleep 1
  task.print_hierarchy
  task.stop     # stop everything inside this Async block
end
puts "Bye!"
```

RSMP::Site and RSMP::Supervisor is not Async task themselves, but each contain a ```task``` attribute containing an async task used to run network and timers. A supervisor contains a single task listening for connections from sites. A site contain a task for each supervisor that it connects to.

See the async documentation for more information about working with task and concurrency.

### Archive and Logging
Sites and supervisor can log message and events, and will store them in an archive.

RSMP::Archive stores messages. RSMP::Logger filters and formats messages according to log settings.

By default, sites and supervisor will create a new archive when initialized, but you can pass in an exsiting archive, which is useful in case you want several sites/supervisors to use the same archive:

```ruby
require 'rsmp'

# create common archive and logger
logger = RSMP::Logger.new('timestamp'=>false,'author'=>true)
archive = RSMP::Archive.new

# run supervisor and site for 0.1 second, then stop them
Async do |task|
  RSMP::Supervisor.new(archive:archive,logger:logger).start
  RSMP::Site.new(archive:archive,logger:logger).start
  task.sleep 0.1
  task.stop
end

# show archiuve content
logger.dump archive, force:true
```

This will output messages form both the site and the supervisor, ordered chronologically:

```console
RN+SU0001                              Starting supervisor RN+SU0001 on port 12111
RN+SI0001                              Starting site RN+SI0001
RN+SI0001                              Connecting to supervisor at 127.0.0.1:12111
RN+SI0001                   <--  f8c7  Sent Version
RN+SU0001                              Site connected from 127.0.0.1:53500
RN+SU0001     RN+SI0001     -->  f8c7  Received Version message for sites [RN+SI0001] using RSMP 3.1.4
...
```

### JSON Schema validation
All messages sent and received will be validated against the core [RSMP JSON Schema](https://github.com/rsmp-nordic/rsmp_schema).

## Command-line tool
Tools for easily running RSMP supervisors and sites. The binary is called ```rsmp```.

The ```supervisor``` command will start an RSMP supervisor, which sites can connect to:

```console
% rsmp supervisor
2019-11-11 12:21:55 UTC                            Starting supervisor RN+SU0001 on port 12111
2019-11-11 12:22:00 UTC                            Site connected from 127.0.0.1:50098
2019-11-11 12:22:00 UTC  RN+SI0001      -->  792f  Received Version message for sites [RN+SI0001] using RSMP 3.1.4
2019-11-11 12:22:00 UTC  RN+SI0001      <--  e70e  Sent Version
2019-11-11 12:22:00 UTC  RN+SI0001                 Connection to site RN+SI0001 established
2019-11-11 12:22:00 UTC  RN+SI0001                 Adding component C1 to site RN+SI0001
2019-11-11 12:22:00 UTC  RN+SI0001  C1  -->  8280  Received AggregatedStatus status for component C1 []
```

The ```site``` command will start an RSMP site, which will try to connect to one or more supervisor. Here's an example of the site connecting to a Ruby supervisor:

```console
% rsmp site
2019-11-11 12:22:00 UTC                            Starting site RN+SI0001
2019-11-11 12:22:00 UTC                            Connecting to supervisor at 127.0.0.1:12111
2019-11-11 12:22:00 UTC                 <--  792f  Sent Version
2019-11-11 12:22:00 UTC  RN+SU0001      -->  e70e  Received Version message, using RSMP 3.1.4
2019-11-11 12:22:00 UTC  RN+SU0001                 Connection to supervisor established
2019-11-11 12:22:00 UTC  RN+SU0001  C1  <--  8280  Sent AggregatedStatus
```


Use the the --type switch to select a specific type of site. Messages will be validated against the corresponding SXL JSON schema. Without any type specified, messages will be validated against the core RSMP schema only.

Use the ```tlc``` site type to run an emulation of a traffic light controller. This type of site implements enough of functionality to pass all the rsmp_validator tests. You can setup signal group components, in the config file.


### CLI help and options.
Use ```--help <command>``` to get a list of available options.

Use ```--config <path>``` or ```--options <path>``` to point to a .yaml config file, controlling things like IP adresses, ports, and log output. Examples of config files can be found the folder ```config/```.

## Tests
### RSpec
RSpec tests are located in spec/. The tests will start supervisor and sites to test communication, but will do so on port 13111, rather than the usual port 12111, to avoid inferference with other RMSP processes running locally.

Note that these tests are NOT intented for testing external equipment or systems. The tests are for validating the code in this repository. To test external equipment or systems use the rsmp_validator tool.

```console
$ rspec
.........................

Finished in 0.12746 seconds (files took 0.6571 seconds to load)
25 examples, 0 failures

```

# Cucumber
Cucumber is used to test the CLI binaries.

```console
$ cucumber
Feature: Help

  Scenario: Displaying help              # features/help.feature:3
    When I run `rsmp help`               # aruba-0.14.11/lib/aruba/cucumber/command.rb:6
    Then it should pass with "Commands:" # aruba-0.14.11/lib/aruba/cucumber/command.rb:271

Feature: Run site
...

7 scenarios (7 passed)
28 steps (28 passed)
0m7.036s
```

