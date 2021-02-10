# Message distribution

Proxy - - Notifier --> Listeners

A proxy distributes messages to listeners, when they are installed.

Collectors are special listenerws that waits for specific message, and are used to implement methods for waiting for RMSP responses, statuses, alarms, etc.

Note that Archive is not a listener, and does not receive messages via the Notifier. Instead the Archive gets and stores messages via the log() interface in the Logging module. The reason is that the items that the Archive and the Logger contain other data as well as the message, like error messages, warnings, text descriptions, colors codes, etc. The Distributor and Receiver handles only Message objects.

## Notifier
A module that handles distributing messages to receivers.

## Listener
Receives messages as long as it's installed into a distributor.

## Collector
A subclass of Receiver that wait for specific messages. Once received
the client receives the collection.

## Proxy
A proxy includes the Notifier module and distributes each message to listerens after processing it.

