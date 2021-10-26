class A
	def go &block
		@block = block			# block will be converted automatically to a Proc
		indirect
	end

	def call
		@block.call
	end

	def indirect
		call
	end

end

a = A.new

a.go do
	break		# this is ok. break causes the block to exit, and the encasing method to return - go() will exit
end

# this raises an error. the block we passed to go() will be called again, and it tries to break
# but we're not inside a method we can exit from


a.indirect
