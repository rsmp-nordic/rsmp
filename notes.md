
# RSMP simulator issues
The simulator ignores if we send a no_ack response to the initital version message

# RSMP specification issues
The version message should contain an identifier of the SXL to use, e.g. "traffic_lights" or "variable_message_sign".
It's not specified whether the first watchdog message is send immediately by both sides, or first by the connecting device, and then the supervisor system.

Should we reply to a version message with an ack + version messages, or only with a version message?
