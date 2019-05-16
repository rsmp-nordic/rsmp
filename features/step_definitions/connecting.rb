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

Then("the site should connect within {int} seconds") do |int|
	sleep 1	#TODO should use call back to continue as soon as connection is established

	@client = @server.remote_clients.first
	expect(@client).not_to be_nil

	expect(@client.site_ids).not_to be_empty
	expect(@client.site_ids.first).to eq(@site_id)
end

Then("the connection sequence should complete within {int} seconds") do |int|
  @messages = @client.stored_messages.clone
end

Then("we should have the following sequence of messages:") do |expected_table|
  actual_table = @messages.reject { |message| message.type == "MessageAck"}.map { |message| [message.type] }
  expected_table.diff!(actual_table)
end
