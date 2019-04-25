# rsmp messages

require 'json'
require 'securerandom'

module RSMP  
  class Message

    attr_reader :now, :attributes, :out, :json, :id, :type

    def self.parse packet
      begin
        attributes = JSON.parse packet
      rescue JSON::ParserError
        raise InvalidPacket, bin_to_chars(packet)
      end

      validate_message_type attributes
      message = nil

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
      message
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

  class Invalid < Message
    def valid?
      false
    end
  end

  class Unknown < Invalid
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
      @attributes["RSMP"].map{ |item| item["vers"] }
    end
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