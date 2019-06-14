#
# RSMP supervisor (server)
#
# Handles  connections to multiple sites (clients)
# The clients connect to us.
# Uses bidirectional pure TCP sockets
#

require 'rubygems'
require 'yaml'
require 'socket'
require 'time'
require_relative 'rsmp'
require_relative 'remote_client'

module RSMP
  class Server
    attr_reader :rsmp_versions, :site_id, :supervisor_settings, :sites_settings, :remote_clients, :logger
    attr_accessor :site_id_mutex, :site_id_condition_variable

    def initialize options
      handle_supervisor_settings options
      handle_sites_sittings options

      @port = @supervisor_settings["port"]
      
      @logger = Logger.new self, @supervisor_settings["log"]

      @remote_clients = []
      @client_counter = 0

      @site_id_mutex = Mutex.new
      @site_id_condition_variable = ConditionVariable.new

      @socket_threads = []
      @run = false
    end

    def handle_supervisor_settings options
      if options[:supervisor_settings]
        @supervisor_settings = options[:supervisor_settings]
      else
        # load settings
        dir = File.dirname(__FILE__)
        if options[:supervisor_settings_path]
          @supervisor_settings = YAML.load_file(options[:supervisor_settings_path])
        else
          raise "supervisor_settings or supervisor_settings_path must be present"
        end
      end
      raise "Supervisor settings is empty" unless @supervisor_settings
      raise "Supervisor settings:port is missing" unless @supervisor_settings["port"]
      @port = @supervisor_settings["port"]
      raise "Supervisor settings:rsmp_version is missing" unless @supervisor_settings["rsmp_versions"]
      @rsmp_versions = @supervisor_settings["rsmp_versions"]
      raise "Supervisor settings:siteId is missing" unless @supervisor_settings["site_id"]
      @site_id = @supervisor_settings["site_id"]
      raise "Supervisor settings:watchdog_interval is missing" if @supervisor_settings["watchdog_interval"] == nil
      raise "Supervisor settings:watchdog_timeout is missing" if @supervisor_settings["watchdog_timeout"] == nil
      raise "Supervisor settings:acknowledgement_timeout is missing" if @supervisor_settings["acknowledgement_timeout"] == nil
      raise "Supervisor settings:command_response_timeout is missing" if @supervisor_settings["command_response_timeout"] == nil
      raise "Supervisor settings:log is missing" if @supervisor_settings["log"] == nil
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
      @run = true
      starting
      @socket = TCPServer.new @port  # server on specific port
      @socket_thread = Thread.new do
        while @run
          begin
            @socket_threads << Thread.start(@socket.accept) do |client|    # wait for a client to connect
              handle_connection(client)
            end
          rescue Errno::EBADF => e
            break
          end
        end
      end
    end

    def join
      @socket_thread.join if @socket_thread
    end

    def stop
      log str: "Stopping supervisor id #{@site_id}", level: :info
      @run = false
      @remote_clients.each { |client| client.terminate }
      @remote_clients.clear

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

    def get_new_client_id
      @client_counter = @client_counter + 1
    end

    def handle_connection client
      sock_domain, remote_port, remote_hostname, remote_ip = client.peeraddr
      info = {ip:remote_ip, port:remote_port, hostname:remote_hostname, now:RSMP.now_string(), id:get_new_client_id}

      if accept? client, info
        connect client, info
      else
        reject client, info
      end
    ensure
      close client, info
    end

    def starting
      log str: "Starting supervisor id #{@site_id} on port #{@port}", level: :info
    end

    def accept? client, info
      true
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

    def connect client, info
      log ip: info[:ip], str: "Site connected", level: :log
      remote_client = RemoteClient.new self, client, info
      @remote_clients.push remote_client
      remote_client.run
    end

    def reject client, info
      log ip: info[:ip], str: "Site rejected", level: :log
    end

    def close client, info
      log ip: info[:ip], str: "Site disconnected", level: :log
      client.close
    end

    def exiting
      log str: "Exiting", level: :info
    end

    def site_connected? site_id
      return find_client(site_id) != nil
    end

    def find_client site_id
      @remote_clients.each do |client|
        return client if client.site_ids.include? site_id
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
        find_client site_id 
      end
    end

  end
end