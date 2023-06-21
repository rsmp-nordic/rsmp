require 'async'

# A helper for running RSpec test code inside an Async reactor.
# You can optially pass a lambda, which will be run in a separate Async,
# for example, if you need server task running to perform the test.
#
# Exceptions are re-raise outside the async block so that RSpec can catch and display them.
# It also avoid Async printing errors, which interferes with RSpec output.

module AsyncRSpec
  def self.async context:nil, &block
    error = nil
    Async do |task|
      if context     # run context as a separate task
        Async do
          context.call       
        rescue StandardError => e
          error = e                 # store error
          task.stop                  # stop parent task and all child task, including context task
        end 
      end
      yield task                    # call main block
    rescue StandardError => e
      error = e                     # store error, but no not re-raise
    ensure
      task.stop                     # stop parent task and all child task, including context task
    end.wait                        # wait for main block to complete (needed if we're already inside a task)
    raise error if error             # re-raise outside async block, so rspec will catch it
  rescue IOError => e               # work-around for async still being work-in-progress on Windows
    puts e
    puts e.backtrace
  end
end
