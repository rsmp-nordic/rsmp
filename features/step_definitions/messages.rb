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
  @acknowledged = @remote_site.wait_for_acknowledgement @sent_message, @supervisor_settings["acknowledgement_timeout"]
  expect(@acknowledged).to be_a(RSMP::MessageAck)
end

Then("we should receive a not acknowledged message") do
  @not_acknowledged = @remote_site.wait_for_not_acknowledged @sent_message, @supervisor_settings["acknowledgement_timeout"]
end

When("we start collecting messages") do
	@probe_start_time = Time.now
	@probe.reset
end

Then(/we should exchange these messages within (\d+) second(?:s)?/) do |timeout, expected_table|
  expected_num = expected_table.rows.size
  @items, num = @archive.capture with_message: true, num: expected_num, timeout: timeout, earliest: @probe_start_time
  actual_table = @items.map { |item| item[:message] }.map { |message| [message.direction.to_s, message.type] }
  actual_table = actual_table.slice(0,expected_table.rows.size)
  actual_table.unshift expected_table.headers
  expected_table.diff!(actual_table)
end

Then("we should receive {int} {string} messages within {int} seconds") do |expected_num, type, timeout|
  @items, num = @archive.capture with_message: true, type: type, num: expected_num, timeout: timeout, earliest: @probe_start_time
  expect(num).to eq(expected_num)
end

