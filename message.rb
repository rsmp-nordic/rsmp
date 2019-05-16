# rsmp messages

require 'json'
require 'securerandom'

module RSMP  
  class Message

    attr_reader :now, :attributes, :out
    attr_accessor :json

    def self.parse_attributes packet
      JSON.parse packet
    rescue JSON::ParserError
      raise InvalidPacket, bin_to_chars(packet)
    end

    def self.build attributes, packet
      validate_message_type attributes
      case attributes["type"]
      when "MessageAck"
        message = MessageAck.new attributes
      when "MessageNotAck"
        message = MessageNotAck.new attributes
      when "Version"
        message = Version.new attributes
      when "AggregatedStatus"
        message = AggregatedStatus.new attributes
      when "Watchdog"
        message = Watchdog.new attributes
      when "Alarm"
        message = Alarm.new attributes
      else
        message = Unknown.new attributes
      end
      message.validate
      message.json = packet
      message
    end

    def validate
    end

    def type
      @attributes["type"]
    end

    def mId
      @attributes["mId"]
    end

    def attribute key
      raise MissingAttribute.new("missing attribute '#{key}'") unless @attributes[key]
      @attributes[key]
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

    def self.validate_message_type attributes
      raise MalformedMessage.new("JSON must be a Hash, got #{attributes.class} ") unless attributes.is_a?(Hash)
      raise MalformedMessage.new("mType is missing") unless attributes["mType"]
      raise MalformedMessage.new("mType must be 'rSMsg', got '#{attributes["mType"]}'") unless attributes["mType"] == "rSMsg"
      raise MalformedMessage.new("'type' is missing") unless attributes["type"]
      raise MalformedMessage.new("'type' must be a String, got #{attributes["type"].class}") unless attributes["type"].is_a? String
    end

    def initialize attributes = {}
      @attributes = { "mType"=> "rSMsg" }.merge attributes

      # if message is empty, generate a new one
      @attributes["mId"] ||= SecureRandom.uuid()
    end

    def validate
      validate_type &&
      validate_id
    end

    def validate_type
      @attributes["mType"] == "rSMsg"
    end

    def validate_id
       @attributes["mId"] =~ /[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}/i
    end

    def valid?
      true
    end

    def generate_json
      @json = JSON.generate @attributes

      # wrap json with a form feed to create an rsmp packet,
      #as required by the rsmp specification
      @out = "#{@json}\f"
    end

  end

  class Malformed < Message
    def initialize attributes = {}
      # don't call super, just copy (potentially invalid) attributes
      @attributes = attributes
    end
  end

  class Version < Message
    def initialize attributes = {}
      super({
        "type" => "Version",
      }.merge attributes)
    end

    def validate
      super &&
      @attributes["RSMP"].is_a?(Array) && @attributes["RSMP"].size >= 1
    end

    def versions
      attribute("RSMP").map{ |item| item["vers"] }
    end
  end

  class Unknown < Message
  end

  class AggregatedStatus < Message 
    def initialize attributes = {}
      super({
        "type" => "AggregatedStatus",
      }.merge attributes)
    end
  end

  class Alarm < Message
    def initialize attributes = {}
      super({
        "type" => "Alarm",
      }.merge attributes)
    end
  end

  class Watchdog < Message
    def initialize attributes = {}
      super({
        "type" => "Watchdog",
      }.merge attributes)
    end
  end

  class MessageAck < Message

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

  class MessageNotAck < Message
    def initialize attributes = {}
      super({
        "type" => "MessageNotAck",
        "rea" => "Unknown reason"
      }.merge attributes)
    end
  end

end