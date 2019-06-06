When("we send the command to component {string}") do |component, table|
  @client.send_command component, table.hashes
end

Then("the {string} message should contain the return values") do |message_type, expected_table|
	candidates = @messages.select { |message| message.type == message_type }
	expect(candidates.size).to be(1)
	message = candidates.first
	rvs = message.attributes["rvs"]

	actual_table = [expected_table.headers]
	rvs.each_with_index do |rv|
		actual_row = expected_table.headers.map { |key| rv[key]}
		actual_table << actual_row
	end

	expected_table.diff!(actual_table)
end
