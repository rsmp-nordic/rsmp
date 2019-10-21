# rsmp-ruby
This is a Ruby implementation of the RSMP protocol, including:
 - RSMP classes (engine) that can be used to build RSMP tools
 - Ruby command-line tools for starting RSMP supervisors or sites

The code has so far only been tested on Mac.

## Installation
You need a recent version of Ruby intalled. 2.6.3 or later is recommended.

Install required gems:

```
$ gem intall bundler
$ bundle
```

Install git submodules:
The JSON Schema is is included as a git submodule. To install it run:

```
$ git submodule init     # initialize local submodule config
$ git submodule update   # fetch submodules
```

Alternatively, you can pass --recurse-submodules to the git clone command, and it will automatically initialize and update each submodule in the repository.

## Ruby classes 
A set of classes that represents RSMP messages, supervisors and sites and handles connecting, exchanging version information, acknowledging messages and other RSMP protocol specifics.

## Command-line tool
Tools for easily running RSMP supervisors and sites. The command is called rsmp.

### Running a supervisor
The 'supervisor' command will start an RSMP supervisor (server), which equipment can connect to:

```
$ rsmp supervisor
2019-08-26 11:48:58 UTC                           Starting supervisor RN+SU0001 on port 12111
2019-08-26 11:49:49 UTC                           Site connected from 127.0.0.1:57138
2019-08-26 11:49:49 UTC  RN+SI0001     -->  2b20  Received Version message for sites [RN+SI0001] using RSMP 3.1.4
2019-08-26 11:49:49 UTC  RN+SI0001     <--  1168  Sent Version
2019-08-26 11:49:49 UTC  RN+SI0001                Connection to site RN+SI0001 established
2019-08-26 11:49:49 UTC  RN+SI0001     -->  f912  Received AggregatedStatus status []
```

### Site
The "site" tool will start an RSMP site. Here's an example of the site connecting to a Ruby supervisor:

```
$ ./site
                         Starting site RN+RC4443 on port 12111
              <--  49c5  Sent Version
              -->  3356  Received MessageAck for Version 49c5
RN+RS0001     -->  c517  Received Version message for sites [RN+RS0001] using RSMP 3.1.4
RN+RS0001                Starting timeout checker with interval 1 seconds
RN+RS0001     <--  1c30  Sent MessageAck for Version c517
RN+RS0001                Connection to supervisor established
RN+RS0001                Starting watchdog with interval 1 seconds
```

Settings will be read from the file config/supervisor.yaml, including what supervisor to connect to, reconnect interval, etc. 

## Cucumber tests
A suite of cucumber tests can be used to test RSMP communication.

It currently focuses on testing sites. It will therefore run an internal supervisor, and tests the communication with the an external) site.

However, cucumber can optionally also run an internal site. In this case all tests can be run quickly, since reconnect delays are eliminated.

### Installing cucumber
Since cucumber is installed via bundler, it's recommended to run via bundle exec: 
$ bundle exec cucumber

### Cucumber tests
The tests are located in features/scenarios/.
Run all tests by simply using the cucumber command:

```
$ cucumber
```

Different sets of tests can be run using the --tag selector, eg:

```
$ cucumber -t @command
```

A small set of tests needs check what messages are send within a certain time. This will cause longer running time when testing. These tests are marked with @delay and can be excluded when running tests:

```
$ cucumber --t 'not @delay'
```

### Cucumber settings
Connection settings used in cucumber tests are stored in:
features/support/supervisor.yaml
features/support/sites.yaml

To run an internal site, ensure this is in features/support/supervisor.yaml:

```yaml
cucumber:
  run_site: false
```

You can override the settings file by using the SITE environment variable:

```
$ cucumber SITE=internal   # run an internal site
$ cucumber SITE=external   # don't run an internal site
```
