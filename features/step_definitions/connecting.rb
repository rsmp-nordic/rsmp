Given("the settings file {string}") do |filename|
  dir = File.dirname(__FILE__)
  path = File.expand_path File.join(dir,'../scenarios',filename)
  @settings = YAML.load_file(path)
end

Given("the setting {string} is set to {string}") do |key, value|
  @settings[key] = JSON.parse(value)
end

When("we start the server") do
  $server = RSMP::Server.new(@settings)
  $server.start
end

Then("the site {string} should connect within {int} seconds") do |site_id, timeout|
	@client = $server.wait_for_site site_id, timeout
	expect(@client).not_to be_nil
	expect(@client.site_ids.include? site_id).to eq(true)
end

Then(/the connection sequence should be complete within (\d+) second(?:s)?/) do |timeout|
  ready = @client.wait_for_state :ready, timeout
  expect(ready).to be(true)
end

When("we start collecting message") do
  @log_start = Time.now
end

Then(/we should exchange these messages within (\d+) second(?:s)?/) do |timeout, expected_table|
  expected_num = expected_table.rows.size
  @messages, num = $server.logger.wait_for_messages num: expected_num, timeout: timeout, earliest: @log_start
  actual_table = @messages.map { |message| [message.direction.to_s, message.type] }
  actual_table = actual_table.slice(0,expected_table.rows.size)
  actual_table.unshift expected_table.headers
  expected_table.diff!(actual_table)
end
