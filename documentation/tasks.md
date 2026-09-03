# Async task ownership

RSMP uses Ruby's fiber scheduler and the Async gem for connections, readers,
timers, and waits. A site, supervisor, or proxy is not itself an Async task. It
owns a main task exposed through `task`.

## Starting and waiting

`start` must run below an active Async parent. It returns the created
`Async::Task`; it never creates a hidden root reactor.

```ruby
Async do |task|
  site = RSMP::Site.new(site_settings: settings)
  site.start(parent: task)

  # Other work can run here.
  site.stop
end
```

Inside an Async task, the current task is the default parent, so `site.start` is
equivalent. Calling `start` again while the task is running returns the existing
task.

`wait` uses `Async::Task#wait`. If the task ends because of an unexpected
exception, `wait` raises that same exception with its original backtrace.
Cancellation is handled by Async and is not translated into an operational
failure.

## Structured task trees

Every long-lived child has an explicit owner:

```text
Site or Supervisor main task
├── listener or connection proxy tasks
├── site status timer
└── explicit termination waiter

Proxy main task
├── connection reader
└── connection timer
```

Sibling tasks are registered in an `Async::Barrier`. Their owner observes task
completion in completion order. A reader's expected EOF or transport failure is
returned as an `RSMP::Result`, closes that connection session, and can lead to a
reconnect. An exception from message processing or a timer is not caught as a
connection error: it propagates through the barrier to the proxy and then the
node owner.

Session IDs prevent a late task from an old connection from closing or
publishing termination for a newer connection. Closing is idempotent and
cancels the remaining reader/timer sibling.

## Finite waits

Finite waits return `RSMP::Result`:

```ruby
result = supervisor.wait_for_site('RN+SI0001', timeout: 5)
result = proxy.wait_for_state(:ready, timeout: 5)
```

A normal timeout is `Result::Failure` with code `:timeout`. Use
`wait_for_site!`, `wait_for_state!`, or another bang variant to raise
`RSMP::OperationError` explicitly.

## Events from long-running services

Events report occurrences that are not the result of a single finite call, such
as a failed connection attempt, invalid peer message, missing acknowledgement,
missing watchdog, or connection end. Register an explicit subscriber on the
node:

```ruby
receiver = Object.new
receiver.define_singleton_method(:receive_event) do |event|
  warn "#{event.type}: #{event.failure}"
end

site.add_event_receiver(receiver)
```

Events are ordered and delivered in the reactor. There is no implicit global
error queue. Subscribers must have an owner that drains or handles them. A
subscriber callback defect propagates unless the subscriber implements `crash`,
in which case it receives that exception through its own completion mechanism.

## Restart and shutdown

`stop` cancels the owned main task and its descendants. A TLC restart request is
not an exception: it resolves an explicit `RSMP::Termination` with reason
`:restart`. The CLI observes this value, lets the old structured task tree clean
up, and then constructs a new site.
