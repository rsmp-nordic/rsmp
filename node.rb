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
      super
      @socket_thread = nil
    end

    def run
      start
      join
    rescue SystemExit, SignalException, Interrupt
      exiting
      exit      #will cause all open sockets to be closed
    end
 
    def log item
      @logger.log item
    end

    def exiting
      log str: "Exiting", level: :info
    end

    def join
      @socket_thread.join if @socket_thread
      @socket_thread = nil
    end

    def restart
      stop
      start
    end

  end
end