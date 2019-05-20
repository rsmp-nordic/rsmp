Given("we're the supervisor accepting communication from {string}") do |string|
	@site_id = string
end

When("we start listening on port {int}") do |int|
	settings = {
  	"siteId"=>"RN+RS0001",
  	"port"=>int,
  	"rsmp_versions"=>["3.1.4"],
  	"watchdog_interval"=>1, "watchdog_timeout"=>2,
  	"acknowledgement_timeout"=>2,
  	"logging"=>false,
  	"log_acknowledgements"=>false,
  	"log_watchdogs"=>true,
  	"store_messages"=>true
	}
  
  @server = RSMP::Server.new(settings)
  Thread.new do
  	@server.run
  end
end

Then("the site {string} should connect within {int} seconds") do |site_id,timeout|
	@client = @server.wait_for_site @site_id, timeout
	#expect(@client).not_to be_nil
	#expect(@client.site_ids).not_to be_empty
	#expect(@client.site_ids.first).to eq(@site_id)
end

Then("the connection sequence should complete within {int} seconds") do |int|
	sleep 1
  @messages = @client.stored_messages.clone
end

Then("we should see the following sequence of messages:") do |expected_table|
  actual_table = @messages.reject { |message| message.type == "MessageAck"}.map { |message| [message.type] }
  actual_table = actual_table[0,expected_table.rows.size]
  actual_table.unshift ['message']		# prepend column headers
  expected_table.diff!(actual_table)
end
