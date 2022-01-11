# Collection
You often need to collect messages or responses. The collector classes are used to collect message asyncronously. Other tasks continue until the collection completes, time outs or is cancelled.

A collector can collect ingoing and/or outgoing messages. 

An object that includes the Notifier module (or implements the same functionality) must be provided when you construct a Collected. The collector will attach itself to this notifier when it starts collecting, to receive messages. The SiteProxy and SupervisorProxy classes both include the Notifier module, and can therefore be used as message sources.

Messages that match the relevant criteria are stored by the collector.

When the collection is done, the collector detaches from the notifier, and returns the status.


## Collector
Class uses for collecting messages filtered by message type, direction and/or component id. A block can be used for custom filtering.

You can choose to collect a specific number of message and/or for a specific duration.

A collector has a status, which is `:ready` initialialy. When you start collecting, it changes to `:collecting`. It will be `:ok` once collection completes successfully, or `:cancel` if it was cancelled to to some error or by a filter block.

### Initialization
When you create a collector, you specify the messages types you want to collect.
You can also specify ingoing and/or outgoing direction and the RSMP component.

```ruby
collector = MessageCollector.new notifier, num: 10, ingoing: true, outgoing: true
```

num: The number of messages to collect. If not provided, a timeout must be set instead.
timeout: The number of seconds to collect
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
You can use a block to do extra filtering. The block will be callled for each messages that fulfils the  correct message type, direction and component id.

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
message = collector.collect # => collected message.
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

## Subscribing to status updates
The method `subscribe_to_status` can be used to subscribe to one of more status messages.

### Without collection
The simple form sends an RSMP status subscription message to the site and then returns immediatly. To collect incoming status messages, you need to manually use e.g. a Collector.

A hash is returned, with `:sent` containing the send subscription messages.

```ruby
options = {
	list: [{'sCI'=>'S0001','n'=>'signalgroupstatus'}],
}
result = subscribe_to_status(options)
result.keys => # [:sent]
```

Note: If you want to use this simple form and manually collect responses, it's best to start collection in an asyncronous task _before_ you subscribe, to make sure you don't miss early responses:

```ruby
task = async do
	MessageCollector.new(options).collect(num: 5, timeout:10)  # start listening for status messages
end
result = subscribe_to_status(options) # subscribe
task.wait  # wait for collection task to complete (or time out)
```

### With collection
If you provide `:collect` options, it will be used to construct a StatusCollector for collecting the relevant status messages. When collection completes the collector is returned in the `:collector` key:

```ruby
options = {
	list: [{'sCI'=>'S0001','n'=>'signalgroupstatus'}],
	collect: {timeout: 5}
}
result = subscribe_to_status(options)
result.keys => # [:sent, :collector]
result[:collector].messages # => list of collected messages
```

You can pass you own collector which will give you more control of how to collect the incoming status messages:

```ruby
collector = Collector.new(options)
options = {collect: collector}
result = subscribe_to_status(options)
result.keys => # [:sent, :collector]
result[:collector].messages # => list of collected messages
```

### Processing responses
If you pass a block, the block will be used to construct a collector. The block will be called for each matching  status item received.
Collection will continue until the block returns :cancel, or it times.

```ruby
options = {
	list: [{'sCI'=>'S0001','n'=>'signalgroupstatus'}]
}
result = subscribe_to_status(options) do |message|
	# do something with message
	:keep # or not
end
result.keys => # [:sent, :collector]
```

