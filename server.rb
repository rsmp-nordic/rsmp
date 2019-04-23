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

    include Logger
    
    def initialize settings
      raise "Settings is empty" unless settings
      @settings = settings

      raise "Port settings is missing" unless @settings["port"]
      @port = settings["port"]
      
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
      info = {ip:remote_ip, port:remote_port, hostname:remote_hostname, now:Time.now, id:get_new_client_id}

      if accept? client, info
        connect client, info
      else
        reject client, info
      end
    ensure
      close client, info
    end

    def starting
      log "#{Server.now_utc} Starting on port #{@port}"
    end

    def accept? client, info
      true
    end

    def connect client, info
      log "#{Server.now_utc} #{info[:id].to_s.rjust(3)} Connected #{info[:hostname]}"
      remote_client = RemoteClient.new client, info
      @remote_clients << remote_client
      remote_client.run
    end

    def reject client, info
      log "#{Server.now_utc} #{info[:id].to_s.rjust(3)} Rejected #{info[:hostname]}"
    end

    def close client, info
      log "#{Server.now_utc} #{info[:id].to_s.rjust(3)} Closed #{info[:hostname]}"
      client.close
    end

    def exiting
      log "#{Server.now_utc} Exiting"
    end

    def self.now_utc
      # date in the format required by rsmp, using UTC time zone
      # example: 2015-06-08T12:01:39.654Z
      DateTime.now.new_offset(0).strftime("%FT%T.%3NZ")
    end
  end
end