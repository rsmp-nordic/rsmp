When("we turn off watchdog messages in the supervisor") do
  @remote_site.set_watchdog_interval(:never)
end
