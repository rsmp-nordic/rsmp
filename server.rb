# rsmp supervisor server
# handles mulitple connection to clients (equipment)
# the clients connect to the server

require 'rubygems'
require 'yaml'
require 'socket'
require_relative 'logger'
require_relative 'remote_client'

# Handle connections to multiple clients.
# Uses bidirectional pure TCP sockets


module RSMP
  class Server
    WRAPPING_DELIMITER = "\f"

    attr_reader :rsmp_versions, :site_id, :settings, :remote_clients, :logger
    attr_accessor :site_id_mutex, :site_id_condition_variable

    def initialize settings
      raise "Settings is empty" unless settings
      @settings = settings

      raise "Settings: port is missing" unless @settings["port"]
      @port = settings["port"]
      
      raise "Settings: rsmp_version is missing" unless @settings["rsmp_versions"]
      @rsmp_versions = settings["rsmp_versions"]

      raise "Settings: siteId is missing" unless @settings["site_id"]
      @site_id = settings["site_id"]

      raise "Settings: watchdog_interval is missing" if @settings["watchdog_interval"] == nil
      raise "Settings: watchdog_timeout is missing" if @settings["watchdog_timeout"] == nil
      raise "Settings: acknowledgement_timeout is missing" if @settings["acknowledgement_timeout"] == nil

      raise "Settings: log is missing" if @settings["log"] == nil
      @logger = Logger.new self, @settings["log"]

      @remote_clients = []
      @client_counter = 0

      @site_id_mutex = Mutex.new
      @site_id_condition_variable = ConditionVariable.new

      @socket_threads = []
      @run = false
    end

    def start
      #return if @socket_thread
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
      log str: "Stopping site id #{@site_id}", level: :info
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
      info = {ip:remote_ip, port:remote_port, hostname:remote_hostname, now:Server.now_string(), id:get_new_client_id}

      if accept? client, info
        connect client, info
      else
        reject client, info
      end
    ensure
      close client, info
    end

    def starting
      log str: "Starting site id #{@site_id} on port #{@port}", level: :info
    end

    def accept? client, info
      true
    end

    def log item
      raise ArgumentError unless item.is_a? Hash
      now_obj = Server.now_object
      now_str = Server.now_string(now_obj)

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

    def self.now_object
      # date using UTC time zone
      Time.now.utc
    end

    def self.now_string time=nil
      # date in the format required by rsmp, using UTC time zone
      # example: 2015-06-08T12:01:39.654Z
      time ||= Time.now.utc
      time.strftime("%FT%T.%3NZ")
    end

    def self.log_prefix ip
      "#{now_string} #{ip.ljust(20)}"
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