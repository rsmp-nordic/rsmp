require 'async'

# A helper for running RSpec test code inside an Async reactor.
# You can optially pass a lambda, which will be run in a separate Async,
# for example, if you need server task running to perform the test.
#
# Exceptions are re-raise outside the async block so that RSpec can catch and display them.
# It also avoid Async printing errors, which interferes with RSpec output.

module AsyncRSpec
  def self.async context:nil
    error = nil
    Async do |task|
      Async { context.call } if context
      yield task
    rescue StandardError => e
      error = e
    ensure
      task.stop                        # make sure child tasks are stopped
    end
    raise error if error               # re-raise outside async block
  rescue IOError, EOFError => e        # work-around for async still being work-in-progress on Windows
    puts e
    puts e.backtrace
  end
end
