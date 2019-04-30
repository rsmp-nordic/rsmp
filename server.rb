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

    attr_reader :rsmp_versions, :site_id, :settings
    include Logger
    
    def initialize settings
      raise "Settings is empty" unless settings
      @settings = settings

      raise "Settings file: port is missing" unless @settings["port"]
      @port = settings["port"]
      
      raise "Settings file: rsmp_version is missing" unless @settings["rsmp_versions"]
      @rsmp_versions = settings["rsmp_versions"]

      raise "Settings file: siteId is missing" unless @settings["siteId"]
      @site_id = settings["siteId"]

      raise "Settings file: watchdog_interval is missing" unless @settings["watchdog_interval"]
      raise "Settings file: watchdog_timeout is missing" unless @settings["watchdog_timeout"]
      raise "Settings file: acknowledgement_timeout is missing" unless @settings["acknowledgement_timeout"]

      @remote_clients = []
      @client_counter = 0
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

    def connect client, info
      log "#{Server.log_prefix(info[:ip])} Connected"
      remote_client = RemoteClient.new self, client, info
      @remote_clients << remote_client
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
  end
end