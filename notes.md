
# RSMP simulator issues
The simulator ignores if we send a no_ack response to the initital version message

When invalid messages are send during connection sequence, the simulator stalls and does not send anything more, nor does it disconnect.


# RSMP specification issues
The version message should contain an identifier of the SXL to use, e.g. "traffic_lights" or "variable_message_sign".
It's not specified whether the first watchdog message is send immediately by both sides, or first by the connecting device, and then the supervisor system.

Should we reply to a version message with an ack + version messages, or only with a version message?

No timeout for receiving Version after connecting? There's no watchdog yet.

RSMP message for reading/writing reconnect interval?
RSMP message for reading/writing which status messages that will be buffered during communication outage?


aggregated status: "alarm" or "fault"? simulatar and documentation does not agree
aggregated status: "rest" or "idle"? simulatar and documentation does not agree

reemove references to NTS (national trafik system)

"Description of the alarm. Defined in SXL but is never actually sent." Why not?


Remove references to SUL (signautbytningsliste), use SXL instead

