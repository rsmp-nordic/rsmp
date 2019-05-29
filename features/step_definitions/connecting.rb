Given("the settings file {string}") do |filename|
  dir = File.dirname(__FILE__)
  path = File.expand_path File.join(dir,'../scenarios',filename)
  @settings = YAML.load_file(path)
end

When("we start the server") do
  @server = RSMP::Server.new(@settings)
  Thread.new do
  	@server.run
  end
end

Then("the site {string} should connect within {int} seconds") do |site_id, timeout|
	@client = @server.wait_for_site site_id, timeout
	expect(@client).not_to be_nil
	expect(@client.site_ids.include? site_id).to eq(true)
end

Then("we should exchange these messages within {int} seconds") do |timeout, expected_table|
  archive = @server.wait_for_messages expected_table.rows.size, timeout
  messages = archive.map { |item| message = item[:message] }.compact
  actual_table = messages.map { |message| [message.direction.to_s, message.type] }
  actual_table = actual_table.slice(0,expected_table.rows.size+1)
  expected_table.diff!(actual_table)
end
