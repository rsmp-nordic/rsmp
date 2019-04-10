# rsmp messages

require 'json'

module RSMP  
  class Message

    attr_reader :now, :attributes, :out, :json, :id, :type

    def self.parse packet
      attributes = JSON.parse packet
      validate_message attributes
      return case attributes["type"]
      when "Version"
        Version.new attributes
      when "AggregatedStatus"
        AggregatedStatus.new attributes
      when "Watchdog"
        Watchdog.new attributes  
      else
        Unknown.new attributes                
      end
    rescue JSON::ParserError
      throw InvalidPacket
    end

    def self.validate_message attributes
      attributes["mType"] == "rSMsg" &&
      attributes["type"] &&
      attributes
    end

    def initialize attributes = {}
      @attributes = { "mType"=> "rSMsg" }.merge attributes
    end

    def valid?
      true
    end

    def generate_json
      @json = JSON.generate @attributes
      @out = "#{@json}\f"
    end

  end

  class Invalid < Message
    def valid?
      false
    end
  end

  class Unknown < Invalid
  end

  class Version < Message
  end

  class AggregatedStatus < Message
  end

  class Watchdog < Message
    def initialize attributes = {}
      super({
        "type" => "Watchdog",
      }.merge attributes)
    end
  end

  class Acknowledged < Message
    def initialize attributes = {}
      super({
        "type" => "MessageAck",
      }.merge attributes)
    end
  end

  class NotAcknowledged < Message
    def initialize attributes = {}
      super({
        "type" => "MessageNotAck",
        "rea" => "Unknown reason"
      }.merge attributes)
    end
  end

end