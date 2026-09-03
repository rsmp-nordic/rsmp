# Message distribution

```text
Proxy -- Distributor --> message receivers
  |
  +-- EventSource ----> explicit node event subscribers
```

A proxy distributes messages to receivers when they are installed. Distribution
uses a receiver snapshot, so a receiver may safely detach during delivery.

Collectors are special receivers that wait for specific messages, and are used to implement methods for waiting for RSMP responses, statuses, alarms, etc.

Archive is not a receiver. It stores messages and other log entries through the
logging interface.

## Distributor
A module that handles distributing messages to receivers.

## Receiver
Receives messages as long as it's installed into a distributor.

Collectors also receive relevant `RSMP::Event` values, such as
`:invalid_message` and `:connection_ended`. This lets expected peer and
transport failures resolve a pending collection without raising.

## Collector
Includes the Receiver module to wait for specific messages. Once received
the client receives the collection.

## Proxy
A proxy includes the Distributor module and distributes each message to receivers after processing it.

Long-running occurrences are additionally published to the owning node's
explicit event subscribers. Event delivery is synchronous and ordered; there is
no implicit global error queue.
