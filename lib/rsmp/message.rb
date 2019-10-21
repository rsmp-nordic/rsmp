# rsmp messages

require 'json'
require'securerandom'
require 'json_schemer'
require_relative 'error'
require_relative 'rsmp'

module RSMP
  class Message

    attr_reader :now, :attributes, :out, :timestamp
    attr_accessor :json, :direction

    def self.load_schemas
      @@schemas = {}
      @@schemas[:traffic_light_controller] = JSONSchemer.schema( Pathname.new('../rsmp_schema/schema/core/rsmp.json') )
      @@schemas
    end

    def self.get_schema sxl = :traffic_light_controller
      schema = @@schemas[sxl]
      raise SchemaError.new("Unknown schema #{sxl}") unless schema
      schema
    end

    @@schemas = load_schemas


    def self.parse_attributes packet
      raise ArgumentError unless packet
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
      when "CommandRequest"
        message = CommandRequest.new attributes
      when "CommandResponse"
        message = CommandResponse.new attributes
      when "StatusRequest"
        message = StatusRequest.new attributes
      when "StatusResponse"
        message = StatusResponse.new attributes
      when "StatusSubscribe"
        message = StatusSubscribe.new attributes
      when "StatusUnsubscribe"
        message = StatusUnsubscribe.new attributes
      when "StatusUpdate"
        message = StatusUpdate.new attributes
      else
        message = Unknown.new attributes
      end
      message.json = packet
      message.direction = :in
      message
    end

    def type
      @attributes["type"]
    end

    def m_id
      @attributes["mId"]
    end

    def attribute key
      unless @attributes.key? key # note that this is not the same as @attributes[key] when
        maybe = @attributes.find { |k,v| k.downcase == key.downcase }
        if maybe
          raise MissingAttribute.new "attribute '#{maybe.first}' should be named '#{key}'"
        else
          raise MissingAttribute.new "missing attribute '#{key}'"
        end
      end
      @attributes[key]
    end

    def self.bin_to_chars(s)
      out = s.gsub(/[^[:print:]]/i, '.')
      max = 120
      if out.size <= max
        out
      else
        mid = " ... "
        length = (max-mid.size)/2 - 1
        "#{out[0..length]} ... #{out[-length-1..-1]}"
      end
    end

    def self.validate_message_type attributes
      raise MalformedMessage.new("JSON must be a Hash, got #{attributes.class} ") unless attributes.is_a?(Hash)
      raise MalformedMessage.new("'mType' is missing") unless attributes["mType"]
      raise MalformedMessage.new("'mType' must be a String, got #{attributes["mType"].class}") unless attributes["mType"].is_a? String
      raise MalformedMessage.new("'mType' must be 'rSMsg', got '#{attributes["mType"]}'") unless attributes["mType"] == "rSMsg"
      raise MalformedMessage.new("'type' is missing") unless attributes["type"]
      raise MalformedMessage.new("'type' must be a String, got #{attributes["type"].class}") unless attributes["type"].is_a? String
    end

    def initialize attributes = {}
      @timestamp = RSMP.now_object
      @attributes = { "mType"=> "rSMsg" }.merge attributes

      ensure_message_id
    end

    def ensure_message_id
      # if message id is empty, generate a new one
      @attributes["mId"] ||= SecureRandom.uuid()
    end

    def validate
      unless Message.get_schema.valid? attributes
        errors = Message.get_schema.validate attributes
        error_string = errors.map do |item|
          [item['data_pointer'],item['type'],item['details']].compact.join(' ')
        end.join(", ")
        raise SchemaError.new error_string
      end
    end

    def validate_type
      @attributes["mType"] == "rSMsg"
    end

    def validate_id
       (@attributes["mId"] =~ /[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}/i) != nil
    end

    def valid?
      true
    end

    def generate_json
      @json = JSON.generate @attributes

      # wrap json with a form feed to create an rsmp packet,
      #as required by the rsmp specification
      @out = "#{@json}"
    end

  end

  class Malformed < Message
    def initialize attributes = {}
      # don't call super, just copy (potentially invalid) attributes
      @attributes = {}
      @invalid_attributes = attributes
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

  class MessageAcking < Message
    attr_reader :original

    def self.build_from message
      return new({
        "oMId" => message.attributes["mId"]
      })
    end

    def original= message
      raise InvalidArgument unless message
      @original = message
    end

    def validate_id
      true
    end
  end

  class MessageAck < MessageAcking
    def initialize attributes = {}
      super({
        "type" => "MessageAck",
      }.merge attributes)
    end

    def ensure_message_id
      # Ack and NotAck does not have a mId
    end
  end

  class MessageNotAck < MessageAcking
    def initialize attributes = {}
      super({
        "type" => "MessageNotAck",
        "rea" => "Unknown reason"
      }.merge attributes)
      @attributes.delete "mId"
   end
  end

  class CommandRequest < Message
    def initialize attributes = {}
      super({
        "type" => "CommandRequest",
      }.merge attributes)
    end
  end

  class CommandResponse < Message
    def initialize attributes = {}
      super({
        "type" => "CommandResponse",
      }.merge attributes)
    end
  end

  class StatusRequest < Message
    def initialize attributes = {}
      super({
        "type" => "StatusRequest",
      }.merge attributes)
    end
  end

  class StatusResponse < Message
    def initialize attributes = {}
      super({
        "type" => "StatusResponse",
      }.merge attributes)
    end
  end

  class StatusSubscribe < Message
    def initialize attributes = {}
      super({
        "type" => "StatusSubscribe",
      }.merge attributes)
    end
  end

  class StatusUnsubscribe < Message
    def initialize attributes = {}
      super({
        "type" => "StatusUnsubscribe",
      }.merge attributes)
    end
  end

  class StatusUpdate < Message
    def initialize attributes = {}
      super({
        "type" => "StatusUpdate",
      }.merge attributes)
    end
  end

end