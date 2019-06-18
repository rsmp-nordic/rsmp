
When("we request the following statuses") do |table|
  @send_values = table.hashes
  timeout = @supervisor_settings["status_response_timeout"]
  @sent_message, @response_message = @remote_site.request_status @component, table.hashes, timeout
  expect(@sent_message).to_not be_nil
  expect(@response_message).to_not be_nil
end


Then("the status response should include the component id") do
	expect(@response_message.attributes["cId"]).to eq(@component)
end

Then("the status response should include the correct status code ids") do
	@send_values.each_with_index do |sent,index|
		expected = {
			"cCI" => sent["cCI"],
			"q" => "recent"
		}
		sS = @response_message.attributes["sS"][index]
		got = {
			"cCI" => sS["cCI"],
			"q" => sS["q"]
		}
		expect(got).to eq(expected)
	end
end

Then("the status response should include values") do
	@send_values.each_with_index do |sent,index|
		sS = @response_message.attributes["sS"][index]
		expect(sS["s"]).to_not be_nil
	end
end

Then("the status response should include a timestamp that is within {float} seconds of our time") do |seconds|
	timestamp = RSMP.parse_time(@response_message.attributes["sTs"])
	difference = (timestamp - @response_message.timestamp).abs
	expect(difference).to be <= seconds
end

Then("we should receive empty status return values") do
end

