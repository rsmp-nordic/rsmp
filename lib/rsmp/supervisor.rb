# RSMP supervisor (server)
#
# Handles connections to multiple sites (sites).
# The supervisor waits for sites to connect.

require_relative 'node'
require_relative 'supervisor_connector'
require 'async/queue'

module RSMP
  class Supervisor < Node
    attr_reader :rsmp_versions, :site_id, :supervisor_settings, :sites_settings, :remote_sites, :logger

    def initialize options={}
      handle_supervisor_settings options
      handle_sites_sittings options
      super options.merge log_settings: @supervisor_settings["log"]
      @remote_sites = []
      @site_id_condition = Async::Notification.new
    end

    def handle_supervisor_settings options
      @supervisor_settings = {
        'site_id' => 'RN+SU0001',
        'port' => 12111,
        'rsmp_versions' => ['3.1.1','3.1.2','3.1.3','3.1.4'],
        'timer_interval' => 0.1,
        'watchdog_interval' => 1,
        'watchdog_timeout' => 2,
        'acknowledgement_timeout' => 2,
        'command_response_timeout' => 1,
        'status_response_timeout' => 1,
        'status_update_timeout' => 1,
        'site_connect_timeout' => 2,
        'site_ready_timeout' => 1,
        'log' => {
          'active' => true,
          'color' => true,
          'ip' => false,
          'timestamp' => true,
          'site_id' => true,
          'level' => false,
          'acknowledgements' => false,
          'watchdogs' => false,
          'json' => false
        }
      }

      if options[:supervisor_settings_path]
        if File.exist? options[:supervisor_settings_path]
          @supervisor_settings.merge! YAML.load_file(options[:supervisor_settings_path])
        else
          puts "Error: Site settings #{options[:supervisor_settings_path]} not found"
          exit
        end

      end
      
      if options[:supervisor_settings]
        converted = options[:supervisor_settings].map { |k,v| [k.to_s,v] }.to_h   #convert symbol keys to string keys
        @supervisor_settings.merge! converted
      end

      required = [:port, :rsmp_versions, :site_id, :watchdog_interval, :watchdog_timeout,
                  :acknowledgement_timeout, :command_response_timeout, :log]
      check_required_settings @supervisor_settings, required

      @rsmp_versions = @supervisor_settings["rsmp_versions"]
      
      # randomize site id
      #@supervisor_settings["site_id"] = "RN+SU#{rand(9999).to_i}"

      # randomize port
      #@supervisor_settings["port"] = @supervisor_settings["port"] + rand(10).to_i
    end

    def handle_sites_sittings options
      @sites_settings = [
        {'site_id'=>:any}
      ]

      if options[:sites_settings_path]
        if File.exist? options[:sites_settings_path]
          @sites_settings = YAML.load_file(options[:sites_settings_path])
        else
          puts "Error: Site settings #{options[:sites_settings_path]} not found"
          exit
        end
      elsif options[:sites_settings]
        @sites_settings = options[:sites_settings]
      end
        
      raise "Sites settings is empty" unless @sites_settings
    end

    def start_action
      @endpoint = Async::IO::Endpoint.tcp('0.0.0.0', @supervisor_settings["port"])
      @endpoint.accept do |socket|
        handle_connection(socket)
      end
    rescue SystemCallError => e # all ERRNO errors
      log str: "Exception: #{e.to_s}", level: :error
    rescue StandardError => e
      log str: ["Exception: #{e.inspect}",e.backtrace].flatten.join("\n"), level: :error
    end

    def stop
      log str: "Stopping supervisor #{@supervisor_settings["site_id"]}", level: :info
      @remote_sites.each { |remote_site| remote_site.stop }
      @remote_sites.clear
      super
      @tcp_server.close if @tcp_server
      @tcp_server = nil
    end

    def handle_connection socket
      remote_port = socket.remote_address.ip_port
      remote_hostname = socket.remote_address.ip_address
      remote_ip = socket.remote_address.ip_address

      info = {ip:remote_ip, port:remote_port, hostname:remote_hostname, now:RSMP.now_string()}
      if accept? socket, info
        connect socket, info
      else
        reject socket, info
      end
    rescue SystemCallError => e # all ERRNO errors
      log str: "Exception: #{e.to_s}", level: :error
    rescue StandardError => e
      log str: "Exception: #{e}", exception: e, level: :error
    ensure
      close socket, info
    end

    def starting
      log str: "Starting supervisor #{@supervisor_settings["site_id"]} on port #{@supervisor_settings["port"]}", 
          level: :info,
          timestamp: RSMP.now_object
    end

    def accept? socket, info
      true
    end

    def connect socket, info
      log ip: info[:ip], str: "Site connected from #{info[:ip]}:#{info[:port]}", 
          level: :info,
          timestamp: RSMP.now_object

      remote_site = SupervisorConnector.new({
        supervisor: self,
        task: @task,
        settings: @sites_settings,
        socket: socket,
        info: info,
        logger: @logger,
        archive: @archive
      })
      @remote_sites.push remote_site
      
      remote_site.run # will run until the site disconnects
      @remote_sites.delete remote_site
      site_ids_changed
    end

    def site_ids_changed
      @site_id_condition.signal
    end

    def reject socket, info
      log ip: info[:ip], str: "Site rejected", level: :info
    end

    def close socket, info
      if info
        log ip: info[:ip], str: "Connection to #{info[:ip]}:#{info[:port]} closed", level: :info, timestamp: RSMP.now_object
      else
        log str: "Connection closed", level: :info, timestamp: RSMP.now_object
      end

      socket.close
    end

    def site_connected? site_id
      return find_site(site_id) != nil
    end

    def find_site site_id
      @remote_sites.each do |site|
        return site if site_id == :any || site.site_ids.include?(site_id)
      end
      nil
    end

    def wait_for_site site_id, timeout
      wait_for(@site_id_condition,timeout) { find_site site_id }
    rescue Async::TimeoutError
      nil
    end

    def wait_for_site_disconnect site_id, timeout
      value = wait_for(@site_id_condition,timeout) { return true unless find_site site_id }
    rescue Async::TimeoutError
      false
    end   

    def check_site_id site_id
      check_site_already_connected site_id
      return find_allowed_site_setting site_id
    end

    def check_site_already_connected site_id
      raise FatalError.new "Site id #{site_id} already connected" if find_site(site_id)
    end

    def find_allowed_site_setting site_id
      @sites_settings.each do |allowed_site|
        if allowed_site["site_id"] == :any || allowed_site["site_id"] == site_id
          return allowed_site
        end
      end
      raise FatalError.new "site id #{site_id} rejected"
    end

  end
end