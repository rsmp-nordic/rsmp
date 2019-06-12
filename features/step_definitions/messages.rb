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

Then("we should receive an acknowledgement") do
  @acknowledged = @client.wait_for_acknowledgement @sent_message, @supervisor_settings["acknowledgement_timeout"]
end


Then("we should receive a not acknowledged message") do
  @not_acknowledged = @client.wait_for_not_acknowledged @sent_message, @supervisor_settings["acknowledgement_timeout"]
end
