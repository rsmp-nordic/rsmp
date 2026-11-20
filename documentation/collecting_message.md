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

### Filters and item matchers

`Filter` selects whole messages by `type:`, `ingoing:`, `outgoing:` and
`component:` (the message's `cId`). Specialized filters also select items within
a message:

| Filter | Default message types | Items | Matcher class |
| --- | --- | --- | --- |
| `StatusFilter` | StatusUpdate, StatusResponse | `sS` | `StatusMatcher` |
| `SubscriptionFilter` | StatusSubscribe, StatusUnsubscribe | `sS` | `SubscriptionMatcher` |
| `CommandFilter` | CommandRequest, CommandResponse | `arg` / `rvs` | `CommandMatcher` |
| `AlarmFilter` | Alarm | `rvs` | `AlarmMatcher` |

Use `type:` to narrow the family to one type or a list of types. Other message
types are rejected at construction. Direction defaults to both incoming and
outgoing. With no matcher constraints, only message-level criteria apply.

```ruby
filter = RSMP::CommandFilter.new(
  type: 'CommandRequest',
  component: 'TC',
  ingoing: true,
  outgoing: false,
  any: [RSMP::CommandMatcher.new('cCI' => 'M0002')]
)

filter = RSMP::StatusFilter.new(all: [
  RSMP::StatusMatcher.new('sCI' => 'S0014', 'n' => 'status', 's' => 2),
  RSMP::StatusMatcher.new('sCI' => 'S0007', 'n' => 'status', 's' => [true])
])
```

`all:` requires every matcher to find a matching item in **one message**. `any:`
requires at least one successful match. Extra items are allowed, and one item can
satisfy multiple matchers. Supply only one of these options, as a nonempty array
of the family's matcher instances; incompatible matchers raise `ArgumentError`.
Filtering does not record or clear matcher state.

To track expectations across several messages, use `StateCollector` through
`StatusCollector` or `CommandResponseCollector`. Those collectors use family
filters without item constraints, then manage their own matchers independently.
A relevant value mismatch clears that expectation until a matching value arrives.
The collectors and filters share item extraction through `items(message)`.

`AlarmFilter` also accepts `attributes:` for `cId`, `aCId`, `aSp`, `ack`, `aS`,
`sS`, `cat` and `pri`. It retains `AlarmCollector`'s comparisons: enum strings
ignore case, identifiers are case-sensitive, and regexes retain their own flags.
For compatibility, `attributes: { 'rvs' => [...] }` uses literal name/value
comparisons; use `all:` or `any:` with `AlarmMatcher` for item matcher semantics.
`AlarmCollector`'s existing `matcher:` hash is passed to the filter as `attributes:`.

All filters retain the `MessageNotAck` exception: rejection messages bypass type
and content criteria, but still respect direction and component filtering. This
lets consumers detect a rejection without waiting for a successful response.
A component filter admits messages without `cId`, including acknowledgements.

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

### Subscription item matching

`SubscriptionMatcher` matches individual `sS` items in `StatusSubscribe` and
`StatusUnsubscribe`. Specify `sCI` and optionally the field name `n`, update rate
`uRt`, and send-on-change setting `sOc`:

```ruby
matcher = RSMP::SubscriptionMatcher.new('sCI' => 'S0014')
matcher.match('sCI' => 'S0014', 'n' => 'status') # true
matcher.match('sCI' => 'S0001', 'n' => 'status') # nil

matcher = RSMP::SubscriptionMatcher.new('sCI' => 'S0014', 'n' => 'status', 'uRt' => '1', 'sOc' => false)
matcher.match('sCI' => 'S0014', 'n' => 'status', 'uRt' => '1', 'sOc' => false) # true
matcher.match('sCI' => 'S0014', 'n' => 'status', 'uRt' => '1', 'sOc' => true)  # false
```

Like `StatusMatcher`, it returns `nil` for a different code or field name, `false`
for matching identity but different requested settings, and `true` for a match.
Unspecified settings are ignored. An explicit `sOc: false` requires the field to
be present and false. Values are compared as supplied, without type conversion.
For unsubscribe items, normally specify only `sCI` and `n`.

The matcher does not wait or filter whole messages. Use `Filter` for message type,
direction and component, and `StatusMatcher` for status update values and quality.

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

The constructor's optional `filter:` decides which messages enter the queue.
A per-wait `filter:` searches the buffered messages in arrival order, discarding
non-matches and leaving messages after the match for later waits. The timeout
covers the entire search, including unrelated traffic. Use sequential waits when
checking a message sequence; concurrent filtered waits share and consume the same
inbox.

```ruby
queue.wait_for_message(
  filter: RSMP::Filter.new(type: 'StatusUpdate', ingoing: false, outgoing: true, component: 'TC'),
  timeout: 5
)
queue.wait_for_status_update('S0014', direction: :out, component: 'TC', timeout: 5)
queue.wait_for_subscribe('S0014', timeout: 5)
queue.wait_for_unsubscribe('S0014', component: 'TC', timeout: 5)
queue.wait_for_ack(update, timeout: 5)
queue.wait_for_command_request('M0002', timeout: 5)
queue.wait_for_command_response('M0002', direction: :out, timeout: 5)
```

These convenience methods default to incoming messages (`direction: :in`) and
return `Result<Message>`. Status waits select any item with the requested `sCI`;
command waits select any item with the requested `cCI`. For additional item
constraints, pass a specialized filter with `all:` or `any:` to `wait_for_message`.

`wait_for_ack` checks the original message ID and returns `:message_rejected` for
a matching `MessageNotAck`. The generic wait also accepts `original:` for
acknowledgement ID correlation. Unrelated rejections cannot satisfy a typed wait,
including a wait whose type restriction comes only from the constructor filter.
A completely untyped wait or a per-wait filter explicitly requesting
`MessageNotAck` can still return it as a message.

Both filters are optional and independent. A dedicated queue can filter on
arrival and use a plain wait:

```ruby
queue = RSMP::Queue.new(proxy, filter: RSMP::CommandFilter.new(
  type: 'CommandRequest', any: [RSMP::CommandMatcher.new('cCI' => 'M0002')]
))
queue.start
begin
  result = queue.wait_for_message(timeout: 5)
ensure
  queue.stop
end
```

For a sequence involving different message types, keep the constructor filter
broad enough to admit later messages, for example `Filter.new(component: 'TC')`,
and select the message type in each wait. A wait cannot recover messages excluded
on arrival. Selecting M0002 skips other commands; to assert that the *next* command
is M0002, wait for any `CommandRequest` and check its code explicitly.

Queues ignore failure events by default. Opt in when a wait should fail on invalid
messages, disconnection, or missing acknowledgements:

```ruby
queue = RSMP::Queue.new(proxy, cancel: {
  invalid_message: true,
  disconnect: true,
  missing_acknowledgement: true
})
```

An enabled failure wakes waiting consumers and takes precedence over buffered
messages. Subsequent waits return the same failure until `clear` resets the queue,
discarding both the failure and any buffered messages. Call `stop` to unregister
the queue when finished.

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
