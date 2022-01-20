# Tasks

## Concurrency
The Async gem (which uses Rubys concurrent Fibers are the new Rubhy Fiber scheduler) is used to handle concurrency.

When you use a site or a supervisor, it runs asyncronously so you can run several concurrently, or do other things concurrently, like sending messages and waiting for reponses.

```
Site - SupervisorProxy - Reader  < < <  Writer - SiteProxy - Supervisor
                       \ Writer  > > >  Reader /
```

Running asyncronously means that the site/supervisor network handling is run in an async task.

Classes don't inherit for Async::Task. Instead they include task as instance variables. This means that the hierachy of objects and tasks can be different.

Async task are use for handle the the following concurrently:

- Running multiple sites or supervisors concurrently
- Running multiple connections concurrently
- Waiting for messages
- Waiting for connections or states

## Proxies
A supervisor waits for sites to connect. Each time a site connects, a proxy is created and run to handle the connection.

A site connects to one of more supervisors. A proxy is created and run to handle each connection.

A site can connect to one or more supervisor. It creates proxy for each and runs them.

When the proxy is run, it creates an async task to handle the communication. The proxy task will be a sub task of the site/supervisor task.

A proxy can use sub tasks to handle watchdog timers, etc.

## The run() cycle
The Task modules defines a life cycle for handling async tasks.

You first call `start`. If `@atask` already exists, it will return immedatiately.
Otherwise an async task is created and stored in `@task`, and `run` is called inside this task, to handle any long-running processes. The call to `start` returns immediately.

If you want to stop the task, call `stop`. If `@task`doesn't exist, it will return. Otherwise it wil call `shutdown`which will terminate the task stored in `@task` as well as any subtasks.

## Proxies and run()
Proxies build on the Task functionality by handling RSMP communication via a TCP socket. The TCP socket can be open or closed. The RSMP communication first goes through a handshake sequence before being ready. This is encapsulated in the `status` attribute, which can be one of `:disconnected`, `:connected` or `:ready`

Proxies implement `connect` and `close` for starting and stopping commununication, but supervisor and site proxies are a bit different. A supervisor proxies connects actively to a site proxy, whereas a site proxy waits for the supervisor proxy to connect. This means they are constructed a bit differently.

A supervisor proxy is created at startup, and is responsible for creating the tcp socket and connecting to the supervisor.

A site proxy is also created at startup, but the socket is created in the supervisor by `Aync::Endpoint#accept`when a site connects.


## Stopping tasks
Be aware that if a task stops itself, code after the call to stop() will not be run - unless you use an ensure block:

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

This is important to keep in mind, e.g. when a timer task finds an acknowledgement was not received in time, and then closes the connection by calling stop() in the Proxy, which will thne in turn stop the timer task.


Object hierarchy:

```
Supervisor 1
	site proxy 1
	site proxy 2
Supervisor 2
	site proxy 1
	site proxy 2

Site 1
	supervisor proxy 1
	supervisor proxy 2
```

Task hierachy:

```
supervisor parent
	accepting connections
		incoming connection 1
		incoming connection 2
	reader
	timer
	
site parent
	tlc site
		connected
		tlc timer

```

The task hierachy matters when you stop a task or iterate on subtasks. Note that calling `Task#wait`
 does not wait for subtasks, whereas Task#stop stops all subtasks.





Async block usage

```ruby
# new design:

# running a site or supervisor
# returns immedately. code will run inside an async task
site.run
supervisor.run

# when a site connects to supervisors,
# async task are implicitely created
@socket = @endpoint.connect

# when a supervisor accepts incoming connections from sites,
# async task are implicitely created
@endpoint.accept

# when you wait for messages
...



# current design:
Async do |task|					  									# Node#start

@endpoint.accept do |socket|  							# Supervisor#start_action,implicit task creation
@socket = @endpoint.connect  								# SupervisorProxy#connect, implicit task creation

@task.async do |task|												# Site#start_action

@reader = @task.async do |task|							# Proxy#start_reader
@timer = @task.async do |task|							# Proxy#start_reader

task = @task.async { |task| yield task }		# Proxy#send_and_optionally_collect
@timer = @task.async do |task|							# TrafficControllerSite#start_timer
```


Task assignment

```ruby
@task = options[:task] 											# Node#initialize
@task = task 																# Node#do_start

@task = options[:task] 											# Collector#initialize
@task = task 																# Collector#use_task

```



