# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2019-2025, by Samuel Williams.

require_relative "../format"
require "time"
require "fiber/annotation"

module Console
	module Output
		class Serialized
			def initialize(io, format: Format.default, **options)
				@io = io
				@format = format
			end
			
			# This a final output that then writes to an IO object.
			def last_output
				self
			end
			
			attr :io
			attr :format
			
			def dump(record)
				@format.dump(record)
			end
			
			def call(subject = nil, *arguments, severity: UNKNOWN, **options, &block)
				record = {
					time: Time.now.iso8601,
					severity: severity,
					oid: subject.object_id,
					pid: Process.pid,
				}
				
				# We want to log just a brief subject:
				if subject.is_a?(String)
					record[:subject] = subject
				elsif subject.is_a?(Module)
					record[:subject] = subject.name
				else
					record[:subject] = subject.class.name
				end
				
				if annotation = Fiber.current.annotation
					record[:annotation] = annotation
				end
				
				message = arguments
				
				if block_given?
					if block.arity.zero?
						message << yield
					else
						buffer = StringIO.new
						yield buffer
						message << buffer.string
					end
				end
				
				if message.size == 1
					record[:message] = message.first
				elsif message.any?
					record[:message] = message
				end
				
				record.update(options)
				
				@io.write(self.dump(record) << "\n")
			end
		end
		
		JSON = Serialized
	end
end
