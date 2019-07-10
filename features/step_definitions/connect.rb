
def connect
  @probe_start_index = 0
  $launcher.restart supervisor_settings: @supervisor_settings
  @supervisor = $launcher.supervisor
  @archive = $launcher.archive
end


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
  connect
end

When("we start the supervisor and the site has connected") do
  connect
  @remote_site = @supervisor.wait_for_site :any, @supervisor_settings["site_connect_timeout"]
  expect(@remote_site).not_to be_nil
end

Then("the site should connect within {float} seconds") do |timeout|
	@remote_site = @supervisor.wait_for_site :any, timeout
	expect(@remote_site).not_to be_nil
	#expect(@remote_site.site_ids.include? site_id).to eq(true)
end

Then("the site should disconnect within {float} seconds") do |timeout|
  ready = @remote_site.wait_for_state :stopping, timeout
  expect(ready).to be(true)
end


Given("we focus on component {string}") do |component|
  @component = component
end
