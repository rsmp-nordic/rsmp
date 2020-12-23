
# Overview
```
	 Node - - - include Logging, Wait
	/   \
Super    Site


         Proxy - - - include Logging, Wait 
        /    \
SiteProxy     SupervisorProxy
```

# Modules
## Logging
Handle logging.

## Wait
Handles waiting for different types of messages and responses.

# Classes
## Node
A Node has an async task. A node can be started and stopped.

Node has two child classes: Site and Supervisor.

## Site
A Site represents an RSMP site, typically a traffic light, variable message sign, or other type of field equipment. An RSMP site can connect to one or more supervisors.

A Site has one or more SupervisorProxies (connections to supervisor).

A site has one of more components.

## Supervisor 
A Supervisor represents an RSMP supervisor, typically a central supervisor system. An RSMP supervisor can handle connections one or more sites.

A Supervisor has one or more SiteProxies (connections to sites).

## Proxy
A Proxy represents a connection to a remove Site or Supervisor and handles the RSMP interface.

A proxy has an async task listening for messages on an TCP/IP socket. Incoming RSMP messages are parsing and appropriate handles are called.

A proxy also has a repaating async timer task for handling watchdog and acknowledgement timeouts.

Proxy has to child classes: SiteProxy and SupervisorProxy.

## SiteProxy
A connection to a remote Site.

Handles RSMP messaging specific to a supervisor, including methods for requesting status, sending commands, etc.

A SiteProxy has one or more components, representing the components in the remote site.

## Supervisor Proxy
A connection to a remote Site. Handles RSMP messaging specific to a site, including sending aggregated status, handling status requests, status subscription and command requests.

Status and command requests are delegated to the appropriate components.

## Components
Things shared between Site and SiteProxy, mainly handling components.

