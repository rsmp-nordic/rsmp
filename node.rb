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
require_relative 'probe'
require_relative 'probe_collection'
require_relative 'logger'
require 'async/io'

module RSMP
  class Node
    attr_reader :archive, :logger

    def initialize options
      @archive = options[:archive] || RSMP::Archive.new
      @logger = options[:logger] || RSMP::Logger.new(options[:log_settings]) 
    end

    def start
      starting
      Async do |task|
        @task = task
        start_action
      end
    rescue Errno::EADDRINUSE => e
      log str: "Cannot start supervisor: #{e.to_s}", level: :error
    rescue SystemExit, SignalException, Interrupt
      exiting
    end

    def start_action
    end

    def starting
    end

    def stop
      @task.stop
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
        raise ArgumentError.new "Missing setting: #{setting}" unless settings.include? setting.to_s
      end 
    end

  end
end