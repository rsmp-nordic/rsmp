#
# RSMP site
#
# Handles a single connection to supervisor.
# We connect to the supervisor.
#

require 'rubygems'
require 'yaml'
require 'socket'
require 'time'
require_relative 'rsmp'
require_relative 'remote_supervisor'

module RSMP
  class Site
    attr_reader :rsmp_versions, :site_id, :site_settings, :logger

    def initialize options
      handle_site_settings options
      @logger = Logger.new self, @site_settings["log"]
      @remote_supervisors = []
      @socket_threads = []
      @run = false
    end

    def handle_site_settings options
      if options[:site_settings]
        @site_settings = options[:site_settings]
      else
        # load settings
        dir = File.dirname(__FILE__)
        if options[:site_settings_path]
          @site_settings = YAML.load_file(options[:site_settings_path])
        else
          raise "site_settings or site_settings_path must be present"
        end
      end
      raise "Site settings is empty" unless @site_settings
      raise "Site settings:supervisor_ip is missing" unless @site_settings["supervisor_ip"]
      @supervisor_ip = @site_settings["supervisor_ip"]
      raise "Site settings:port is missing" unless @site_settings["port"]
      @port = @site_settings["port"]
      raise "Site settings:rsmp_version is missing" unless @site_settings["rsmp_versions"]
      @rsmp_versions = @site_settings["rsmp_versions"]
      raise "Site settings:siteId is missing" unless @site_settings["site_id"]
      @site_id = @site_settings["site_id"]
      raise "Site settings:watchdog_interval is missing" if @site_settings["watchdog_interval"] == nil
      raise "Site settings:watchdog_timeout is missing" if @site_settings["watchdog_timeout"] == nil
      raise "Site settings:acknowledgement_timeout is missing" if @site_settings["acknowledgement_timeout"] == nil
      raise "Site settings:command_response_timeout is missing" if @site_settings["command_response_timeout"] == nil
      raise "Site settings:log is missing" if @site_settings["log"] == nil
    end

    def start
      @run = true
      starting
      
      # TODO for each supervisor we want to connect to
      socket = TCPSocket.open @supervisor_ip, @port  # connect to supervisor
      info = {ip:@supervisor_ip, port:@port, now:RSMP.now_string()}
      log ip: info[:ip], str: "Connected to supervisor", level: :log
      remote_supervisor = RemoteSupervisor.new site: self, socket: socket, info: info, logger: @logger
      @remote_supervisors.push remote_supervisor
      remote_supervisor.run
    end

    def join
      @socket_thread.join if @socket_thread
    end

    def stop
      log str: "Stopping site id #{@site_id}", level: :info
      @run = false
      @remote_supervisors.each { |site| site.terminate }
      @remote_supervisors.clear

      @socket.close if @socket
      @socket = nil

      @socket_thread.join if @socket_thread
      @socket_thread = nil
    ensure
      exiting
    end

    def restart
      stop
      start
    end

    def close site, info
      log ip: info[:ip], str: "Site disconnected", level: :log
      site.close
    end

    def starting
      log str: "Starting site id #{@site_id} on port #{@port}", level: :info
    end

    def exiting
      log str: "Exiting", level: :info
    end

    def log item
      raise ArgumentError unless item.is_a? Hash
      now_obj = RSMP.now_object
      now_str = RSMP.now_string(now_obj)

      cleaned = item.select { |k,v| [:level,:ip,:site_id,:str,:message].include? k }
      cleaned[:timestamp] = now_obj
      cleaned[:direction] = item[:message].direction if item[:message]

      @logger.log cleaned
    end

  end
end