require 'async'

# Run block inside an Async reactor.
# Catch errors and just return then, and use result() reo re-raise then outside the reactor,
# to avoid Async printing errors, which interferes with rspec output.
# Use a transient task, to ensure that any subtask are terminated as soon as the main task completes
def async_context &block
	Async transient: true do |task|
		yield task
	rescue StandardError => e
		e
	end.result
end
