# Finite operations and message collection

RSMP distinguishes expected operational failures from implementation defects.
Operations that can normally time out, be rejected, or lose their connection
return an `RSMP::Result`. They do not use exceptions for ordinary control flow.

```ruby
result = proxy.wait_for_state(:ready, timeout: 5)

if result.success?
  puts "Reached #{result.value}"
else
  warn "#{result.failure.code}: #{result.failure.message}"
end
```

`RSMP::Result::Success` contains `value`. `RSMP::Result::Failure` contains an
immutable `RSMP::Failure` with:

- `code`: a stable symbol such as `:timeout`, `:not_ready`,
  `:message_rejected`, or `:disconnected`.
- `message`: a human-readable explanation.
- `source`: where the failure originated, such as `:peer`, `:transport`,
  `:connection`, `:timeout`, or `:local`.
- `context`: structured details such as the message and connection session.
- `cause`: the underlying exception, when an expected low-level exception was
  translated at a boundary.

Use the corresponding bang method when exception-based handling is more
convenient. A failed result is then raised as `RSMP::OperationError`; its
`failure` attribute retains the structured failure.

```ruby
proxy.wait_for_state!(:ready, timeout: 5)
```

Unexpected exceptions are never converted into a `Result`. They propagate with
their original class and backtrace because they indicate a bug in the library or
calling application.

Message handlers can reject schema-valid but semantically invalid peer input by
raising `RSMP::PeerMessageError` or one of its domain subclasses, normally
`RSMP::MessageRejected`. The receive boundary converts only this explicit error
family to a peer failure. It does not rescue arbitrary `StandardError` values.

## Validation

Schema mismatches are expected when communicating with an external peer.
`RSMP::Schema.validate` and `message.validate` return an `RSMP::Validation`:

```ruby
validation = message.validate(core: '3.3.0', tlc: '1.3.0')

unless validation.valid?
  warn validation.message
  validation.violations.each { |violation| warn violation.inspect }
end
```

`message.validate!` is the explicit raising variant. Invalid API arguments,
missing schema configuration, and unknown schema versions still raise directly
because they are programming or configuration errors rather than invalid peer
messages.

## Collectors

A collector attaches to a message distributor, such as `SiteProxy` or
`SupervisorProxy`, and waits for matching messages. Give it a count, a timeout,
or a block that completes or cancels the collection.

```ruby
filter = RSMP::Filter.new(type: 'Alarm', ingoing: true, component: 'DL1')
collector = RSMP::Collector.new(proxy, filter: filter, num: 2, timeout: 5)
result = collector.collect
```

A successful collector returns `Result<RSMP::Collection>`. A collection is an
immutable snapshot containing `messages` and, for state collectors, `reached`
and `matcher_status`.

```ruby
if result.success?
  result.value.messages.each { |message| puts message }
end
```

`collect!` and `wait!` return the message array directly and raise
`RSMP::OperationError` for an expected failure.

To start without waiting:

```ruby
collector.start
# Perform another operation.
result = collector.wait
```

Collectors start in an inactive state, become active after `start`, and detach
from the distributor exactly once when they succeed or fail. A matching
`MessageNotAck`, timeout, invalid peer message, connection end, or explicit
`cancel` resolves the collector with a failure. An exception raised by a custom
collector callback rejects its completion and propagates unchanged.

Custom blocks return `:keep` to retain a matching message. They can also call
`collector.cancel(reason)` explicitly.

```ruby
result = collector.collect do |message|
  next :keep if useful?(message)

  collector.cancel('No longer needed') if finished?
end
```

### Message predicates

Use `predicate:` for conditions beyond the message type, direction, and component
handled by `RSMP::Filter`. The Proc receives a whole message after the filter
accepts it. Returning `false` or `nil` skips the message before collection
callbacks or state-item matching; earlier item matches remain intact.

```ruby
collector = RSMP::Collector.new(
  proxy,
  filter: RSMP::Filter.new(type: 'StatusUpdate', ingoing: true, outgoing: false),
  predicate: ->(message) { message.is_a?(RSMP::StatusUpdate) && message.attribute('sS').any? },
  num: 1,
  timeout: 5
)
```

Predicates also work with `StatusCollector`. They do not suppress failures such
as a rejection of the initiating request or an invalid peer message. `Filter`
admits `MessageNotAck` even when a different message type is requested, so a
predicate that accesses type-specific attributes should check the message type.

### Status collection

`StatusCollector` matches wanted status items within incoming messages. Both
`StatusUpdate` and `StatusResponse` are accepted by default. Set `responses: false`
to accept updates only, or `updates: false` to accept responses only.

```ruby
want = [{ 'sCI' => 'S0001', 'n' => 'signalgroupstatus' }]
collector = RSMP::StatusCollector.new(
  proxy, want, component: 'C1', responses: false, timeout: 5
)
```

`component:` filters the message's `cId`; the wanted items describe entries in
`sS`, which do not have their own component ID. Collection completes when all
wanted items match, rather than after a fixed number of messages.

### Collection during proxy setup

The proxy's `collect:` option accepts the existing collector options hash:

```ruby
proxy_options = {
  collect: {
    filter: RSMP::Filter.new(type: 'StatusUpdate', ingoing: true, outgoing: false),
    num: 1,
    timeout: 5
  }
}
```

It also accepts a Proc that receives the new proxy and returns a collector or
queue. The proxy calls `start` on the returned object and exposes it through
`proxy.collector`. This starts receiving before the handshake can deliver
messages. Return an unstarted object; the factory runs before version negotiation
and should not rely on the proxy being fully initialized or connected.

```ruby
proxy_options = {
  collect: proc do |proxy|
    RSMP::StatusCollector.new(
      proxy,
      [{ 'sCI' => 'S0001', 'n' => 'signalgroupstatus' }],
      component: 'C1', responses: false, timeout: 5
    )
  end
}
```

Pass these options when creating the proxy. Use `proxy.collector.wait` or
`wait!` for a collector, or `wait_for_message` or `wait_for_message!` for a queue.

## Queues

`RSMP::Queue` retains accepted messages until consumed, including messages that
arrive before the caller starts waiting. Each wait returns one message, rather
than a collection. `start` and `stop` are aliases for `start_receiving` and
`stop_receiving`, so a queue can also be returned by a proxy's `collect:` factory.

```ruby
queue = RSMP::Queue.new(proxy, filter: RSMP::Filter.new(type: 'StatusUpdate'))
queue.start
begin
  result = queue.wait_for_message(timeout: 5)
  puts result.value if result.success?
ensure
  queue.stop
end
```

A queue stays registered until stopped. Its `timeout:` applies to an individual
wait: expiry returns a failure with code `:timeout`, or raises
`RSMP::OperationError` through `wait_for_message!`.

An enclosing Async timeout raised while waiting in the queue is converted in
the same way, even when no queue timeout is supplied:

```ruby
begin
  message = Async::Task.current.with_timeout(5) { queue.wait_for_message! }
rescue RSMP::OperationError => error
  raise unless error.failure.code == :timeout

  warn 'The caller deadline expired'
end
```

This example assumes the queue is already started. Both timeout sources use the
same failure code; `failure.cause` retains the original Async exception.

## Sending and collecting atomically

High-level send methods follow the same non-bang/bang convention:

```ruby
result = proxy.send_command(command_list, component: 'C1')
message = proxy.send_command!(command_list, component: 'C1')
```

Methods ending in `_and_collect` start their collector before sending, so an
immediate peer response cannot be missed. They return `Result<RSMP::Exchange>`.
The exchange contains the request and the immutable completed collection.

```ruby
result = proxy.send_command_and_collect(command_list, component: 'C1', within: 5)

if result.success?
  exchange = result.value
  puts exchange.request
  puts exchange.collection.messages
end
```

Status requests and subscriptions use the same shape:

```ruby
result = proxy.request_status_and_collect(status_list, component: 'C1', within: 5)
result = proxy.subscribe_to_status_and_collect(subscription_list, component: 'C1', within: 5)
```

The raising variants are `send_command_and_collect!`,
`request_status_and_collect!`, and `subscribe_to_status_and_collect!`.
