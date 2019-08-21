# creates

require 'singleton'
require_relative '../../supervisor'
require_relative '../../site'
require 'colorize'

class SupervisorRunner
  include Singleton

  def up
    return if @reactor
    @reactor = Async::Reactor.new

    @reactor.async do |task|
      @supervisor = RSMP::Supervisor.new supervisor_settings: { 'log' => { 'active' => false }}
      @supervisor.start
    end

     @connector = @reactor.run do |task|
      puts "Waiting for site...".colorize(:light_blue)
      @remote_site = @supervisor.wait_for_site(:any,10)
      if @remote_site
        @remote_site.wait_for_state :ready, 3
        from = "#{@remote_site.connection_info[:ip]}:#{@remote_site.connection_info[:port]}"
        puts "Site #{@remote_site.site_id} connected from #{from}".colorize(:light_blue)
      else
        raise "Site connection timeout".colorize(:red)
      end
      @reactor.stop
    end
  end

  def down
    @reactor.stop
  end

  def connected &block
    up
    @reactor.run do |task|
      yield task, @remote_site
      @reactor.stop
    end
  end
end
