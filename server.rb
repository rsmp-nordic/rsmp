# rsmp supervisor server
# handles mulitple connection to clients (equipment)
# the clients connect to the server

require 'rubygems'
require 'yaml'
require 'socket'
require 'monitor.rb'
require_relative 'logger'
require_relative 'remote_client'

# Handle connections to multiple clients.
# Uses bidirectional pure TCP sockets

module RSMP
  class Server
    WRAPPING_DELIMITER = "\f"

    attr_reader :rsmp_versions, :site_id, :settings, :remote_clients
    
    def initialize settings
      raise "Settings is empty" unless settings
      @settings = settings

      raise "Settings: port is missing" unless @settings["port"]
      @port = settings["port"]
      
      raise "Settings: rsmp_version is missing" unless @settings["rsmp_versions"]
      @rsmp_versions = settings["rsmp_versions"]

      raise "Settings: siteId is missing" unless @settings["siteId"]
      @site_id = settings["siteId"]

      raise "Settings: watchdog_interval is missing" if @settings["watchdog_interval"] == nil
      raise "Settings: watchdog_timeout is missing" if @settings["watchdog_timeout"] == nil
      raise "Settings: acknowledgement_timeout is missing" if @settings["acknowledgement_timeout"] == nil
      raise "Settings: store_messages is missing" if @settings["store_messages"] == nil

      @remote_clients = []
      @client_counter = 0

      @remote_clients.extend(MonitorMixin)
      @new_clients_connected
      @empty_cond = @remote_clients.new_cond
    end

    def run
      starting
      socket = TCPServer.new @port  # server on specific port
      loop do
        Thread.start(socket.accept) do |client|    # wait for a client to connect
          handle_connection(client)
        end
      end
    ensure
      exiting
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
      log "#{Server.now_string} Starting site id #{@site_id} on port #{@port}"
    end

    def accept? client, info
      true
    end

    def log str
       Logger.log str if @settings["logging"]
    end

    def connect client, info
      log "#{Server.log_prefix(info[:ip])} Connected"
      remote_client = RemoteClient.new self, client, info

      @remote_clients.synchronize do
        @remote_clients.push remote_client
        @empty_cond.broadcast
      end
      remote_client.run
    end

    def reject client, info
      log "#{Server.log_prefix(info[:ip])} Rejected"
    end

    def close client, info
      log "#{Server.log_prefix(info[:ip])} Closed "
      client.close
    end

    def exiting
      log "#{Server.now_string} Exiting"
    end

    def self.now_object
      # date using UTC time zone
      Time.now.utc
    end

    def self.now_string
      # date in the format required by rsmp, using UTC time zone
      # example: 2015-06-08T12:01:39.654Z
      Time.now.utc.strftime("%FT%T.%3NZ")
    end

    def self.log_prefix ip
      "#{now_string} #{ip.ljust(20)}"
    end

    def site_connected? site_id
       @remote_clients.each do |client|
        return true if client.site_ids.include? site_id
      end
      false
    end

    def wait_for_site site_id, timeout
      @remote_clients.synchronize do
        @empty_cond.wait_while { !site_connected?(site_id) }
      end
      client = @remote_clients.first
      p client.site_ids
      client
    end

  end
end