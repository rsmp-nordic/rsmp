# Helper for running test code with an optional background context task.
# The context lambda runs concurrently (e.g. a supervisor or site that
# listens/connects in the background while the test body runs).
#
# Usage:
#   with_async_context(context: -> { supervisor.start }) do |task|
#     # test body
#     task.stop  # optional explicit cleanup
#   end
module AsyncHelper
  def with_async_context(context: nil)
    task = Async::Task.current
    context_task = task.async { context.call } if context
    yield task
  ensure
    context_task&.stop
  end
end
