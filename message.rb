# rsmp messages

require 'json'
require 'securerandom'

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
      raise InvalidPacket, bin_to_chars(packet)
    end

    def self.bin_to_chars(s)
      if s.size == 0
        ""
      elsif s.size == 1
        "#{s.bytes.first}"
      elsif s.size == 2 
        "#{s.bytes.first},#{s.bytes.last}"
      elsif s.size >= 3
        "#{s.bytes.first},...,#{s.bytes.last}"
      end
    end

    def self.validate_message attributes
      raise InvalidJSON unless attributes.is_a?(Hash)
      raise InvalidMessage unless attributes["mType"] == "rSMsg" &&
                                  attributes["type"] &&
                                  attributes
    end

    def initialize attributes = {}
      @attributes = { "mType"=> "rSMsg" }.merge attributes

      # if message is empty, generate a new one
      @attributes["mId"] ||= SecureRandom.uuid()
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

    def self.build_from message
      return new({
        "oMId" => message.attributes["mId"]
      })
    end

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