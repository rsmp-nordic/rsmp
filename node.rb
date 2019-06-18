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
require_relative 'logger'

module RSMP
  class Node
    def initialize options
    end

    def run
      start
      @socket_thread.join
    rescue SystemExit, SignalException, Interrupt
      exiting
      exit      #will cause all open sockets to be closed
    end

    def start
      starting
    end

    def stop
      if @socket_thread
        @socket_thread.kill
        @socket_thread = nil
      end
    end

    def restart
      stop
      start
    end

    def log item
      @logger.log item
    end

    def exiting
      log str: "Exiting", level: :info
    end

    def check_required_settings settings, required
      raise ArgumentError.new "Settings is empty" unless settings
      required.each do |setting|
        raise ArgumentError.new "Missing setting: #{setting}" unless settings.include? setting
      end 
    end

  end
end