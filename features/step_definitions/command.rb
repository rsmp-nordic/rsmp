When("we clear component data") do
	@client.clear_component_data
end

When("we send the command to component {string}") do |component, table|
  @client.send_command component, table.hashes
end

Then("the {string} message should contain the return values") do |message_type, expected_table|
	# find message to inspect
	candidates = @messages.select { |message| message.type == message_type }
	expect(candidates.size).to be(1)
	message = candidates.first

	# build table from received rvs values in message
	rvs = message.attributes["rvs"]
	actual_table = [expected_table.headers]
	rvs.each_with_index do |rv|
		actual_row = expected_table.headers.map { |key| rv[key] }
		actual_table << actual_row
	end

	# and compare with expected table
	expected_table.diff!(actual_table)
end

Then("the received return values for component {string} should be empty") do |component|
	rvs = @client.component(component)['rvs']
	expect(rvs).to be_nil
end

Then("the received return values for component {string} should be") do |component, expected_table|
	# build table from received rvs values
	rvs = @client.component(component)['rvs'] || {}
	actual_table = [expected_table.headers]
	rvs.each_with_index do |rv|
		actual_row = expected_table.headers.map { |key| rv[key] }
		actual_table << actual_row
	end

	# and compare with expected table
	expected_table.diff!(actual_table)
end
