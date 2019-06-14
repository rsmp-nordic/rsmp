
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

