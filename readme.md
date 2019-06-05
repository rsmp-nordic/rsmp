
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
