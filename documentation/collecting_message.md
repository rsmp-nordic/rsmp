# Collection
You often need to collect messages or responses. The collector classes are used to collect message asyncronously. Other tasks continue until the collection completes, time outs or is cancelled.

A collector can collect ingoing and/or outgoing messages.

An object that includes the Distributor module (or implements the same functionality) must be provided when you construct a Collected. The collector will attach itself to this distributor when it starts collecting, to receive messages. The SiteProxy and SupervisorProxy classes both include the Distributor module, and can therefore be used as message sources.

Messages that match the relevant criteria are stored by the collector.

When the collection is done, the collector detaches from the distributor, and returns the status.


## Collector
Class used for collecting messages filtered by message type, direction and/or component id. A block can be used for custom filtering.

You can choose to collect a specific number of message and/or for a specific duration.

A collector has a status, which is `:ready` initialialy. When you start collecting, it changes to `:collecting`. It will be `:ok` once collection completes successfully, or `:cancel` if it was cancelled to to some error or by a filter block.

### Initialization
When you create a collector, you provide a Filter to specify the messages types you want to collect. You can also specify ingoing and/or outgoing direction and the RSMP component.

```ruby
collector = MessageCollector.new(distributor,
	num: 10,
	filter: Filter.new(ingoing: true, outgoing: true)
```

num: The number of messages to collect. If not provided, a timeout must be set instead.
filter: filter to identify the types of messages to look for.

### Filter
The Filter class is used to filter messages according to message type, direction and component.

```ruby
filter = Filter.new(
	type: 'Alarm',
	ingoing: true,
	outgoing: false,
	component: 'DL1'
	)
```

type: a string, or an array of string, specifiying one or more RSMP message types.
ingoing: Whether to collect ingoing messages. Defaults to true
outgoing: Whether to collect outgoing messages. Defaults to true
component: An RSMP component id.

### Collecting
Use collect() to start collecting and wait for completion or timeout. The status will be returned.

```ruby
result = collector.collect # => :ok, :timeout or :cancelled
collector.messages # => collected messages
```

If you want start collection, but not wait for the result, use `start()`. You can then later use `wait()` if you want:

```ruby
result = collector.start # => nil
# do other stuff
result = collector.wait
```

### Custom filtering
You can use a block to do extra filtering. The block will be callled for each messages that passes the Filter provided when initializing the collector.

The block must return nil or a list of symbols to indicate whether the message should be kept, and whether collection should be cancelled.

```ruby
result = collector.collect do |message|
	:keep, :cancel 		# example of how to keep the message and cancel collection
end
```

`:keep` keeps (collect) this message
`:cancel` cancel collection

Note that you cannot use `return` in a block. You can either simply provide the values as the last expresssion in the block, or use next().

Exceptions in the block will cause the collector to abort. If the collect! or wait! variants are used, the exception is propagated to the caller.

### Bang version
The method collect!() will raise exceptions in case of errors, and will return the collect message directly.

```ruby
message = collector.collect! # => collected message.
```

Similar, `wait!()` will raise an exception in case of timeouts or errors:

```ruby
message = collector.wait! # => collected message.
```


### Schema Errors and Disconnects
The collector can optionally cancel collection in special cases, controlled by the `:cancel` option provided when contructing the collector.

```ruby
options = {
	cancel: {
		disconnect: true,
		schema_error: true
	}
}
result = collector.collect options
```

disconnect: If the proxy which provides messages experience a disconnect, the collector will cancel collection.

schema_error: If the proxy receives a message with a schema error, the collector will cancel collection, if the the invalid message has the correct message type.

### NotAck
A typical scenaria is that you send a command or status request, and want to collect the response. But if the original message is rejected by the site, you will received a NotAck instead of a reply. The collector classes can handle this, as long as you provide the message id of the original request in the `m_id` key of teh options when you construct the collector.

If a NotAck is received with a matching `oMId` (original message id), the collection is cancelled.

## StatusCollector
Waits for a set of status criteria to be met.

Note that a single RSMP status message can contain multiple status items. Unlike MessageCollector, a StatusCollector therefore operates on items, rather than messages, and you can't specify a number of messages to collect.


### Criteria
You construct a StatusCollector with set of criteria, specifying the status codes, names, and optionally values that must be met.

### Collecting
When you start collection, it will complete once all criteria are all fulfilled, the timeout is reached or a custom filtering block aborts the collection.

```ruby
collector = StatusCollector.new(options)
result = matcher.collect(timeout: 5)
```

### Custom filtering
You can use a block to do extra filtering. The block will be called for each individual status item that fulfils all criteria, like status code and name, component, etc.

Like with MessageCollector, the block must return a hash specifing whether to keep the message and whether to continue collection.

```ruby
matcher = StatusCollector.new(options)
result = matcher.collect(options) do |message,item|
	next(:keep) if good_item?(item) 		# keep item
end
```

## Sending commands
The method `send_command` sends a CommandRequest to the site and returns the sent message. `component:` defaults to `main.c_id`.

```ruby
message = send_command(
  [{'cCI' => 'M0001', 'n' => 'status', 'v' => 'NormalControl'}],
  component: 'AA+BBCCC=DDDEE001'
)
```

To send and wait for the CommandResponse, use `send_command_and_collect`. It returns a collector; call `.ok!` to raise on NotAck or timeout.

```ruby
collector = send_command_and_collect(
  [{'cCI' => 'M0001', 'n' => 'status', 'v' => 'NormalControl'}],
  within: 5,
  component: 'AA+BBCCC=DDDEE001'
)
collector.ok!
```

## Requesting status
The method `request_status` sends a StatusRequest to the site and returns `{ sent: message }`. `component:` defaults to `main.c_id`.

```ruby
result = request_status(
  [{'sCI' => 'S0001', 'n' => 'signalgroupstatus'}],
  component: 'AA+BBCCC=DDDEE001'
)
result[:sent]  # => the StatusRequest message
```

To send and wait for the StatusResponse, use `request_status_and_collect`. It returns a collector; call `.ok!` to raise on NotAck or timeout.

```ruby
collector = request_status_and_collect(
  [{'sCI' => 'S0001', 'n' => 'signalgroupstatus'}],
  within: 5,
  component: 'AA+BBCCC=DDDEE001'
)
collector.ok!
```

## Subscribing to status updates
The method `subscribe_to_status` sends a StatusSubscribe message to the site and returns `{ sent: message }`. `component:` defaults to `main.c_id`.

### Without collection

```ruby
result = subscribe_to_status(
  [{'sCI' => 'S0001', 'n' => 'signalgroupstatus', 'uRt' => '1'}],
  component: 'AA+BBCCC=DDDEE001'
)
result[:sent]  # => the StatusSubscribe message
```

If you want to manually collect incoming status updates after subscribing, start a collector before subscribing so you don't miss early responses:

```ruby
task = async do
  MessageCollector.new(options).collect(num: 5, timeout: 10)
end
subscribe_to_status(status_list)
task.wait
```

### With collection

Use `subscribe_to_status_and_collect` to subscribe and collect status updates matching the criteria. It returns a collector; call `.ok!` to raise on NotAck or timeout.

```ruby
collector = subscribe_to_status_and_collect(
  [{'sCI' => 'S0001', 'n' => 'signalgroupstatus', 'uRt' => '1'}],
  within: 5,
  component: 'AA+BBCCC=DDDEE001'
)
collector.ok!
```

