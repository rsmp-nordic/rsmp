# Get the current time in UTC, with optional adjustment
# Convertion to string uses the RSMP format 2015-06-08T12:01:39.654Z
# Note that using to_s on a my_clock.to_s will not produce an RSMP formatted timestamp,
# you need to use Clock.to_s my_clock

require 'time'

module RSMP

  class Clock
    attr_reader :adjustment

    def initialize
      @adjustment = 0
    end

    def set target
      @adjustment = target - Time.now
    end

    def reset
      @adjustment = 0
    end

    def now
      Time.now.utc + @adjustment
    end

    def to_s
      Clock.to_s now
    end

    def self.now
      Time.now.utc
    end

    def self.to_s time=nil
      (time || now).strftime("%FT%T.%3NZ")
    end

  end
end