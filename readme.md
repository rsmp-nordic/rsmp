
# Ruby RSMP
This is a Ruby implementation of the RSMP protocol.

The "rsmp" script can by used to start an RSMP supervisor server, which equipment can connect to:

$ ruby ./rsmp

The script reads settigns from the file ./rsmp.yml, including the port to listen to and the rsmp version that's supported.









# 
If you're running the RSMP simulator in Virtualbox, you need to use NAT to connect them.
The simulator should connect to 10.202.182.252:12111