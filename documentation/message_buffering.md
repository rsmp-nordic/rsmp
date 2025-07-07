# Message Buffering

RSMP sites implement message buffering to handle temporary disconnections from supervisors. When a site loses connection to a supervisor, certain messages are buffered and sent when the connection is reestablished.

## How it works

1. **During disconnection**: When a site tries to send a message but the connection is closed, the message is evaluated for buffering:
   - **Buffered messages**: StatusUpdate, AlarmIssue, AggregatedStatus, and other data messages
   - **Discarded messages**: CommandRequest, CommandResponse, Version, Watchdog, MessageAck, MessageNotAck

2. **Quality modification**: Status messages (StatusUpdate) have their quality field modified from the original value to `"old"` when buffered, indicating the data is no longer current.

3. **After reconnection**: Once the handshake is complete and the connection is reestablished, all buffered messages are sent in order, then the buffer is cleared.

## RSMP Specification Compliance

This implementation follows the RSMP specification requirements for message buffering:

- Status subscriptions remain active during disconnection and generate buffered messages
- Buffered status messages have quality set to "old" 
- Control messages (commands, versions, watchdogs, acknowledgements) are not buffered
- Buffered messages are sent after connection reestablishment

## Implementation Details

### Buffer Storage
- Messages are stored in a `@message_buffer` array in the `Proxy` class
- Buffer is initialized when proxy is created and cleared after each reconnection

### Message Filtering
```ruby
unbuffered_types = %w[CommandRequest CommandResponse Version Watchdog MessageAck MessageNotAck]
```

### Quality Modification
For StatusUpdate messages, the quality field is changed:
```ruby
if message.type == 'StatusUpdate' && cloned_attributes['sS']
  cloned_attributes['sS'] = cloned_attributes['sS'].map do |status|
    status.merge('q' => 'old')
  end
end
```

### Sending Buffered Messages
Buffered messages are sent after the handshake is complete in `SupervisorProxy#handshake_complete`:
```ruby
send_buffered_messages
```

## Testing

The buffer functionality is tested with unit tests that verify:
- Correct message type filtering
- Quality modification for status messages
- Buffer clearing after sending
- Proper handling of different message types

Run the buffer tests:
```bash
bundle exec rspec spec/buffer_spec.rb
```

## Limitations

- **No persistence**: Messages are stored in memory only. A power outage will cause buffered messages to be lost.
- **No size limit**: There is currently no limit on buffer size, though this could be added if needed.
- **No prioritization**: Messages are sent in the order they were buffered (FIFO).

## Future Enhancements

Potential improvements as mentioned in the RSMP specification:
- Disk persistence to survive power outages
- Buffer size limits with overflow handling
- Message prioritization for critical alarms