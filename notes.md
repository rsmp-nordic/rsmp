
# RSMP simulator issues
The simulator ignores if we send a no_ack response to the initital version message

When invalid messages are send during connection sequence, the simulator stalls and does not send anything more, nor does it disconnect.

Notes in .INI settings file is in swedish

System log should not auto-scroll to bottom when new message are received, unless it's already at the bottom

When sending invalid commands to the simulator, it response with NotAcknowledged with empty "rea".

When requesting status, the sCIO and n fields seem to be ignored, we always get a StatusRespons back, even it we send invalid values.
When requesting data, the "s" field contains null. Is null allowed?


# RSMP specification issues
## Clarify
The version message should contain an identifier of the SXL to use, e.g. "traffic_lights" or "variable_message_sign".

It's not specified whether the first watchdog message is send immediately by both sides, or first by the connecting device, and then the supervisor system.

Should we reply to a version message with an ack + version messages, or only with a version message?

No timeout for receiving Version after connecting? There's no watchdog yet.

aggregated status: "alarm" or "fault"? simulatar and documentation does not agree
aggregated status: "rest" or "idle"? simulatar and documentation does not agree

"Description of the alarm. Defined in SXL but is never actually sent." Why not?

## Fix
Remove references to SUL (signautbytningsliste), use SXL instead
Remove references to NTS (national trafik system)

## Ideas
RSMP message for reading/writing reconnect interval?
RSMP message for reading/writing which status messages that will be buffered during communication outage?

