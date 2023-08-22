# 

site A -- proxy to X - - - - proxy to A -- supervisor X
site B --	proxy to X - - - - proxy to B /


A site tries to stay connected to it's supervisors. If disconnected, it waits a bit and tries to connect again.
A supervisor waits for sites to connect. If disconnected, it waits for the site to reconnect.


A site object is configured to connect to one or more supervisor. Each supervisor is handled by a proxy that runs continously, regardless of whether the connection to it's supervisor is up or down.

## Supervisor Proxy
### Timer
As soon as the proxy is created the timer start. It handles:
- status subscriptions
- aggregated status changes
- alarms

The timer runs regardless of whether the connection is up or down. If the connection is down and the timer causes a message to be send, the messages is buffered.

The timer also handles the following, but only when the proxy is connected to the supervisor:

- send watchdogs
- check that we receive message acknowledgements

### Connect loop
When the proxy starts, a loop is started in an async task, and will keep running until the proxy is stopped.

The loop:
- connect to the supervisor
- reader: read a line at a time and handle messages (async task)
- initiates handshake
- send alarms
- send buffered messages

If connecting fails, the proxy waits a while and tries again (restarting the loop)

When the connection is closed:
- the reader is stopped
- the list of messages that we expect to receive acknowledgements for is cleared (?)
- sending watchdog messages is paused

The loop then runs from the beginning, trying to connecting again.



## Supervisor
The supervisor opens a port for listening.

When a site connects, a site proxy is created (or reused if is has previously been connected), and the tcp connection is passed to the proxy.


## Site Proxy
### Connect loop
The proxy has a loop that:
- reader: read a line at a time and handle messages (async task)


# Proxy tasks
A proxy has several distinct tasks, like
- handling the initial handshake
- responding to messages read from the tcp socket
- checking that all send messages are acknowledged
- checking that we receive watchdog messages
- sending out status messages to subscribers

If the connection goes down, then what each of these task do might differ:
- timer that sends out status messages continues, buffering outgoing messages
- checking that messages are acknowledged is paused
- ongoing handshake is cancelled
- reading message to respond to is paused

If one of these tasks fails, e.g. has an uncaught exception, we can restart that task, instead of breaking everything. This is similar to the Elixir/Erlang principle of letting it fail, then restarting form a known good state. But we would need to ensure that we monitor and log such errors and restarts, so that bugs can be fixed.
