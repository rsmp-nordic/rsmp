require 'time'

module RSMP
  # Get the current time in UTC, with optional adjustment.
  # Conversion to string uses the RSMP format 2015-06-08T12:01:39.654Z
  # Use `Clock.to_s` to format times in RSMP format.
  class Clock
    attr_reader :adjustment

    def initialize
      @adjustment = 0
    end

    def set(target)
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

    def self.to_s(time = nil)
      (time || now).strftime('%FT%T.%3NZ')
    end

    def self.parse(str)
      Time.parse(str)
    end
  end
end
