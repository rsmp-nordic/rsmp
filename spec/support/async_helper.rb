require 'async'

# Run block inside an Async reactor.
# Catch errors and return them, then use result() to re-raise them outside the reactor.
# to avoid Async printing errors, which interferes with rspec output.
# We use a transient task, to ensure that any subtask are terminated as soon as the main task completes.
def async_context transient:nil, &block
	Async do |task|
		if transient
			Async transient: true do |child|
				transient.call
			end.result
		end
		yield task
	end.result
end
