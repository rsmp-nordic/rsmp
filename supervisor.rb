# RSMP supervisor (server)
#
# Handles connections to multiple sites (sites).
# The supervisor waits for sites to connect.

require_relative 'node'
require_relative 'remote_site'

module RSMP
  class Supervisor < Node
    attr_reader :rsmp_versions, :site_id, :supervisor_settings, :sites_settings, :remote_sites, :logger
    attr_accessor :site_id_mutex, :site_id_condition_variable

    def initialize options
      handle_supervisor_settings options
      handle_sites_sittings options

      @logger = options[:logger] || RSMP::Logger.new(self, @supervisor_settings["log"]) 
      @remote_sites = []
      @socket_threads = []
      
      @site_id_mutex = Mutex.new
      @site_id_condition_variable = ConditionVariable.new
    end

    def handle_supervisor_settings options
      if options[:supervisor_settings]
        @supervisor_settings = options[:supervisor_settings]
      else
        if options[:supervisor_settings_path]
          @supervisor_settings = YAML.load_file(options[:supervisor_settings_path])
        else
          raise "supervisor_settings or supervisor_settings_path must be present"
        end
      end
      
      required = ["port","rsmp_versions","site_id","watchdog_interval","watchdog_timeout",
                  "acknowledgement_timeout","command_response_timeout","log"]
      check_required_settings @supervisor_settings, required

      @port = @supervisor_settings["port"]
      @rsmp_versions = @supervisor_settings["rsmp_versions"]
      @site_id = @supervisor_settings["site_id"]
    end

    def handle_sites_sittings options
      if options[:sites_settings]
        @sites_settings = options[:sites_settings]
      else
        # load settings
        dir = File.dirname(__FILE__)
        if options[:sites_settings_path]
          @sites_settings = YAML.load_file(options[:sites_settings_path])
        else
          raise ":sites_settings or :sites_settings_path must be present"
        end
      end
      raise "Sites settings is empty" unless @supervisor_settings
      raise "Sites settings: port is missing" unless @supervisor_settings["port"]
    end

    def start
      @socket_thread = Thread.new do
        @tcp_server = TCPServer.new @port  # server on specific port
        loop do
          begin
            @socket_threads << Thread.start(@tcp_server.accept) do |socket|    # wait for a site to connect
              handle_connection(socket)
            end
          rescue SystemCallError => e # all ERRNO errors
            log str: "Exception: #{e.to_s}", level: :error
          rescue StandardError => e
            log str: ["Exception: #{e.inspect}",e.backtrace].flatten.join("\n"), level: :error
          end
        end
      end
    end

    def stop
      log str: "Stopping supervisor #{@site_id}", level: :info
      @remote_sites.each { |remote_site| remote_site.stop }
      @remote_sites.clear
      @tcp_server.close if @tcp_server
      @tcp_server = nil
      super
    end

    def handle_connection socket
      sock_domain, remote_port, remote_hostname, remote_ip = socket.peeraddr
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
      log str: "Starting supervisor #{@site_id} on port #{@port}", level: :info
    end

    def accept? socket, info
      true
    end

    def connect socket, info
      log ip: info[:ip], str: "Site connected from #{info[:ip]}:#{info[:port]}", level: :info
      remote_site = RemoteSite.new supervisor: self, settings: @sites_settings, socket: socket, info: info, logger: @logger
      @remote_sites.push remote_site
      remote_site.run # will run until the site disconnects

      @remote_sites.delete remote_site
    end

    def reject socket, info
      log ip: info[:ip], str: "Site rejected", level: :info
    end

    def close socket, info
      log ip: info[:ip], str: "Site #{info[:ip]}:#{info[:port]} gone", level: :info
      socket.close
    end

    def site_connected? site_id
      return find_site(site_id) != nil
    end

    def find_site site_id
      @remote_sites.each do |site|
        return site if site.site_ids.include? site_id
      end
      nil
    end

    def site_ids_changed
      @site_id_mutex.synchronize do
        @site_id_condition_variable.broadcast
      end
    end

    def wait_for_site site_id, timeout
      @site_id_mutex.synchronize do
        @site_id_condition_variable.wait(@site_id_mutex,timeout) unless site_connected? site_id
        find_site site_id 
      end
    end

    def check_site_id site_id
      @remote_sites.each do |site|
        if site.site_ids.include? site_id
          raise FatalError.new "Site id #{site_id} already connected" 
        end
      end
    end

  end
end