# Base class for conenction to a single site or supervisor

require_relative 'message'
require_relative 'error'
require 'timeout'

module RSMP  
  class Remote
    attr_reader :site_ids, :server

    def initialize options
      @logger = options[:logger]
      @info = options[:info]
      @socket = options[:socket]
      @site_ids = []
      @state = :starting
    end

    def close
      @socket.close
    end

    def terminate
      @state = :stopping
      info "Closing connection"
      @reader.kill
    end

    def kill_threads
      reaper = Thread.new(@threads) do |threads|
        threads.each do |thread|
          info "Stopping #{thread[:name]}"
          thread.kill
        end
      end
      reaper.join
      @threads.clear
    end

    def prefix
      site_id = @site_ids.first
      "#{Server.log_prefix(@info[:ip])} #{site_id.to_s.ljust(12)}"
    end

    def error str, message=nil
      log_at_level str, :error, message
    end

    def warning str, message=nil
      log_at_level str, :warning, message
    end

    def log str, message=nil
      log_at_level str, :log, message
    end

    def info str, message=nil
      log_at_level str, :info, message
    end

    def log_at_level str, level, message=nil
      @logger.log({
        level: level,
        ip: @info[:ip],
        site_id: @site_ids.first,
        str: str,
        message: message
      })
    end

    def send message, reason=nil
      message.generate_json
      message.direction = :out
      log_send message, reason
      @socket.print message.out
      expect_acknowledgement message
      message.m_id
    end

    def log_send message, reason=nil
      if reason
        log "Sent #{message.type} #{reason}", message
      else
        log "Sent #{message.type}", message
      end
    end

  end
end