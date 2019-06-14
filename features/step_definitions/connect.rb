Given("the supervisor settings {string}") do |filename|
  dir = File.dirname(__FILE__)
  path = File.expand_path File.join(dir,'../scenarios',filename)
  @supervisor_settings = YAML.load_file(path)
end

Given("the site settings {string}") do |filename|
  dir = File.dirname(__FILE__)
  path = File.expand_path File.join(dir,'../scenarios',filename)
  @sites_settings = YAML.load_file(path)
end

Given("the supervisor setting {string} is set to {string}") do |key, value|
  @supervisor_settings[key] = JSON.parse(value)
end

Given("the site setting {string} is set to {string}") do |key, value|
  @sites_settings[key] = JSON.parse(value)
end

When("we start the server") do
  $env.restart supervisor_settings: @supervisor_settings
  @server = $env.server
end

Then("the site should connect within {int} seconds") do |timeout|
  site_id = @main_site_settings["site_id"]
	@client = @server.wait_for_site site_id, timeout
	expect(@client).not_to be_nil
	expect(@client.site_ids.include? site_id).to eq(true)
end

Then(/the connection sequence should be complete within (\d+) second(?:s)?/) do |timeout|
  ready = @client.wait_for_state :ready, timeout
  expect(ready).to be(true)
end

Given("we focus on component {string}") do |component|
  @component = component
end
