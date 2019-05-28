def parse_settings_table table
  table.rows_hash.map do |key,value|
    if value == "true"
      [key,true]
    elsif value == "false"
      [key,false]
    elsif value.match /^\d+$/
      [key,value.to_i]
    elsif value.include? ','
      [key,value.split(',').map {|s| s.strip }.flatten]
    else
      [key,value]
    end
  end.to_h
end

Given("the supervisor settings") do |table|
  @settings = parse_settings_table table
end

When("we start the server") do
  @server = RSMP::Server.new(@settings)
  Thread.new do
  	@server.run
  end
end

Then("the site {string} should connect within {int} seconds") do |site_id, timeout|
	@server.wait_for_site site_id, timeout

	@client = @server.remote_clients.first
	expect(@client).not_to be_nil

	expect(@client.site_ids).not_to be_empty
	expect(@client.site_ids.include? site_id).to eq(true)

  @messages = @client.stored_messages.clone
end

Then("we should see the message sequence") do |expected_table|
  actual_table = @messages.map { |message| [message.direction.to_s, message.type] }
  actual_table = actual_table.slice(0,expected_table.rows.size+1)
  expected_table.diff!(actual_table)
end
