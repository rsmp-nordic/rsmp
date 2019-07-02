When("we send the following command request") do |table|
  @send_values = table.hashes
  timeout = @supervisor_settings["command_response_timeout"]
  @sent_message = @remote_site.send_command @component, table.hashes
  expect(@sent_message).to_not be_nil
end

Then(/we should receive a command response within (\d+) second(?:s)?/) do |timeout|
  @response_message = @remote_site.wait_for_command_response @component, timeout
  expect(@response_message).to_not be_nil
end

Then("we should received the following return values") do |expected_table|
	# build table of received responses
	rvs = @response_message.attributes["rvs"]
	actual_table = [expected_table.headers]
	rvs.each_with_index do |rv|
		actual_row = expected_table.headers.map { |key| rv[key] }
		actual_table << actual_row
	end

	# and compare with expected table
	expected_table.diff!(actual_table)
end

Then("same values should be returned in the command response") do
	expected = []
	@send_values.each do |sent|
		expected << { "cCI" => sent["cCI"], "n" => sent["n"], "v" => sent["v"], "age" => "recent"}
	end

	rvs = @response_message.attributes["rvs"]
	expect(rvs).to eq(expected)
end

Then("we should receive empty command return values") do
	expected = []
	@send_values.each do |sent|
		expected << { "cCI" => nil, "n" => sent["n"], "v" => nil, "age" => "undefined"}
	end

	rvs = @response_message.attributes["rvs"]
	expect(rvs).to eq(expected)
end
