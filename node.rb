#
# RSMP site
#
# Handles a single connection to a supervisor.
# We connect to the supervisor.
#

require 'rubygems'
require 'yaml'
require 'socket'
require 'time'
require_relative 'rsmp'
require_relative 'archive'
require_relative 'logger'

module RSMP
  class Node
    attr_reader :archive, :logger

    def initialize options
      @archive = options[:archive] || RSMP::Archive.new
      @logger = options[:logger] || RSMP::Logger.new(options[:log_settings]) 
      @connection_threads = []
    end

    def run
      start
      wait_for_threads
    rescue SystemExit, SignalException, Interrupt
      exiting
      exit      #will cause all open sockets to be closed
    end

    def start
      starting
    end

    def stop
      kill_threads @connection_threads
    end

    def restart
      stop
      start
    end

    def wait_for_threads
      @connection_threads.each { |thread| thread.join }
    end

    def kill_threads threads
      threads.each { |thread| thread.kill }
      threads.clear
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