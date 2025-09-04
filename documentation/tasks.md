# Tasks

## Concurrency
When you use a site or a supervisor, it runs asyncronously so you can run several concurrently, or do other things concurrently, like sending messages and waiting for reponses.

Concurrency is provided by Ruby Fiber Scheduler and the Async gem. and used to:

- Runn multiple sites or supervisors
- Run multiple connections from each site or supervisor
- Wait for messages, connections or states

Classes don't inherit from Async::Task. Instead they include task as instance variables. This means that the hierachy of objects and tasks can be different.

## Task module
The `Task` module is used by the `Node` and `Proxy` classes and defines a life cycle for handling async tasks.

A single main tasks is kept in `@task`. If subclasses need subtask, they can start them as needed, inside the main task.

You first call `start`. If `@task` already exists, it will return immedatiately.
Otherwise an async task is created and stored in `@task`, and `run` is called inside this task, to handle any long-running jobs, like listening for incoming messages. By default `run` calls `start_subtasks`, but should be overriden to do actual work as well.
The call to `start` returns immediately, with the async task running concurently.

If you want to stop the task, call `stop`. It will fist call `stop_subtasks` and then `stop_task` which calls Async#stop on `@task` and sets `@task` to `nil`.

## Stopping tasks
If a task stops itself, code after the call to `stop` will not be run, unless you use an ensure block:

```ruby
require 'async'

Async do |task|
	task.stop
	puts "I just stopped"   # this will not be reaced, because the task was stopped
end

Async do |task|
	task.stop
ensure
	puts "I just stopped"   # this will be reached
end
```
This can happen if either the task stops itself directly, or if it stops task higher up in the task hierarchy.

For example, when a timer task finds that an acknowledgement was not received in time, and then closes the connection by calling stop() on the Proxy, the proxy which will then in turn stop the timer task. So any code that should be run after that must be inside an ensure block.

## Proxies
A site connects to one of more supervisors. A proxy is created and run to handle each connection.

A site can connect to one or more supervisor. It creates a proxy for each and runs them.

When the proxy is run, it creates an async task to read incoming messages. This reader task is stored in `@reader`and will be a sub task of the site/supervisor main task.

A proxy also creates a timer task, stored in `@timer`. This task is used to check watchdog and acknowledgement timeouts.

Proxies build on the Task module functionality by handling RSMP communication via a TCP socket.

The TCP socket can be open or closed. The RSMP communication first goes through a handshake sequence before being ready. The `status` attribute keeps track of this, and can be either `:disconnected`, `:connected` or `:ready`

Proxies provide `connect` and `close` for starting and stopping commununication.

A supervisor proxies connects actively to a site proxy, whereas a site proxy waits for the supervisor proxy to connect.

A supervisor proxy is created at startup, and is responsible for creating the TCP socket and connecting to the supervisor.

A site proxy is also created at startup, but the socket is created in the supervisor by `Aync::Endpoint#accept`when a site connects.

## Object Hierarchy
A Site has one or more SupervisorProxies, which represent connections to the remote supervisor. 

A Supervisor has one or more SiteProxies, which represent connections to the remote site.

SiteProxy and SupervisorProxy both inherit from Proxy and have a reader task and a timer task. These are just Async tasks, not separate classes.

## Task Hierachy
When you start an Async task, the parent will be the currently running task, unless you specify a different parent task.

The Async task hierarchy is similar to the object hierachy, with the difference that proxies have reader and timer tasks. And IO::Endpoint which is used to handle TCP connections concurently, will create some intermediate tasks:

```
Supervisor @task
	accepting connections      # this task is created by IO::Endpoint
		incoming connection 1    # this task is created by IO::Endpoint
			SiteProxy @task
				SiteProxy @reader
				SiteProxy @timer
		incoming connection 2    # this task is created by IO::Endpoint
			SiteProxy @task
				SiteProxy @reader
				SiteProxy @timer

```


A Site run from the CLI, before it connects to a supervisor:

```
#<Async::Reactor:0xb90 1 children (running)>
	#<Async::Task:0xba4 cli (running)>
		#<Async::Task:0xbcc RSMP::TLC::TrafficControllerSite main task (running)>
			#<Async::Task:0xbe0 RSMP::SupervisorProxy main task (running)>
			#<Async::Task:0xbf4 tlc timer (running)>
```

After the site connects to a supervisor:

```
#<Async::Reactor:0xadc 1 children (running)>
	#<Async::Task:0xaf0 cli (running)>
		#<Async::Task:0xb18 RSMP::TLC::TrafficControllerSite main task (running)>
			#<Async::Task:0xb2c RSMP::SupervisorProxy main task (running)>
				#<Async::Task:0xb40 reader (running)>
				#<Async::Task:0xb54 timer (running)>
			#<Async::Task:0xb68 tlc timer (running)>
```



A supervisor run from the CLI, before any sites have connected:

```
#<Async::Reactor:0x94c 1 children (running)>
	#<Async::Task:0x960 cli (running)>
		#<Async::Task:0x988 RSMP::Supervisor main task (running)>
			#<Async::Task:0x99c accepting connections #<Addrinfo: 0.0.0.0:14111 TCP> [fd=12] (running)>
```

The supervisor after a site has connected

```
#<Async::Reactor:0x94c 1 children (running)>
	#<Async::Task:0x960 cli (running)>
		#<Async::Task:0x988 RSMP::Supervisor main task (running)>
			#<Async::Task:0x99c accepting connections #<Addrinfo: 0.0.0.0:13111 TCP> [fd=12] (running)>
				#<Async::Task:0xac8 incoming connection #<Addrinfo: 127.0.0.1:51778 TCP> [fd=13] (running)>
					#<Async::Task:0xadc RSMP::SiteProxy main task (running)>
						#<Async::Task:0xaf0 reader (running)>
						#<Async::Task:0xb04 timer (running)>
```

The task hierachy matters when you stop a task or iterate on subtasks. Note that calling `Task#wait`
 does not wait for subtasks, whereas Task#stop stops all subtasks.

## Transient tasks
If you mark an Async task with `transient: true` when you created it, that task will be stopped aas soon as all normal task are completed. They will also be moved up the hierarchy if the parent is complete, but not the grandparent.

Transient tasks can be used to cleanup, but using an `ensure` block in the transient task. When you call `stop` on a task, an Async::Stop exception is raised, which will run the code in the `ensure` block.

Some of the RSpec tests runs tests in in transient task. As soon as the main test code is complete, any subtasks like Sites or Supervisors that might otherwise prevent the test from completing, will be stopped automatically.

