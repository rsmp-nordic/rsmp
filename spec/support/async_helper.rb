require 'async'

def async_context &block
	Async transient: true do |task|
		yield task
	rescue StandardError => e
		e
	ensure
		task.stop later: true
	end.result
end
