require 'rsmp_schema'

# rsmp messages
module RSMP
  class Message
    include Inspect

    attr_reader :now, :attributes, :out
    attr_reader :timestamp # this is an internal timestamp recording when we receive/send
    attr_accessor :json, :direction

    def self.make_m_id
      SecureRandom.uuid()
    end

    def self.parse_attributes json
      raise ArgumentError unless json
      JSON.parse json
    rescue JSON::ParserError
      raise InvalidPacket, bin_to_chars(json)
    end

    def self.build core_version, attributes, json
      validate_message_type attributes
      case attributes["type"]
      when "MessageAck"
        message = MessageAck.new core_version, attributes
      when "MessageNotAck"
        message = MessageNotAck.new core_version, attributes
      when "Version"
        message = Version.new core_version, attributes
      when "AggregatedStatus"
        message = AggregatedStatus.new core_version, attributes
      when "AggregatedStatusRequest"
        message = AggregatedStatusRequest.new core_version, attributes
      when "Watchdog"
        message = Watchdog.new core_version, attributes
      when "Alarm"
        message = self.build_alarm core_version, attributes
      when "CommandRequest"
        message = CommandRequest.new core_version, attributes
      when "CommandResponse"
        message = CommandResponse.new core_version, attributes
      when "StatusRequest"
        message = StatusRequest.new core_version, attributes
      when "StatusResponse"
        message = StatusResponse.new core_version, attributes
      when "StatusSubscribe"
        message = StatusSubscribe.new core_version, attributes
      when "StatusUnsubscribe"
        message = StatusUnsubscribe.new core_version, attributes
      when "StatusUpdate"
        message = StatusUpdate.new core_version, attributes
      else
        message = Unknown.new core_version, attributes
      end
      message.json = json
      message.direction = :in
      message
    end

    def self.build_alarm core_version, attributes
      case attributes["aSp"]
      when /^Issue$/i
        AlarmIssue.new core_version, attributes
      when /^Request$/i
        AlarmRequest.new core_version, attributes
      when /^Acknowledge$/i
        if attributes['ack'] =~ /^acknowledged$/i
        AlarmAcknowledged.new core_version, attributes
        else
          AlarmAcknowledge.new core_version, attributes
        end
      when /^Suspend$/i
        if attributes['sS'] =~ /^suspended$/i
          AlarmSuspended.new core_version, attributes
        elsif attributes['sS'] =~ /^notSuspended$/i
          AlarmResumed.new core_version, attributes
        else
          AlarmSuspend.new core_version, attributes
        end
      when /^Resume$/i
        AlarmResume.new core_version, attributes
      else
        Alarm.new core_version, attributes
      end
    end

    def type
      @attributes["type"]
    end

    def m_id
      @attributes["mId"]
    end

    def self.shorten_m_id m_id, length=4
      m_id[0..length-1]
    end

    def m_id_short
      Message.shorten_m_id @attributes["mId"]
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

    def initialize core_version, attributes = {}
      @timestamp = Time.now   # this timestamp is for internal use, and does not use the clock
                              # in the node, which can be set by an rsmp supervisor
      @attributes = attributes.merge( "mType"=> "rSMsg" )

      ensure_message_id
    end

    def ensure_message_id
      # if message id is empty, generate a new one
      @attributes["mId"] ||= Message.make_m_id
    end

    def validate schemas
      errors = RSMP::Schema.validate attributes, schemas
      if errors
        error_string = errors.map {|item| item.reject {|e| e=='' } }.compact.join(', ').strip
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
      # ensure compact format on all platforms
      options = {
        array_nl: nil,
        object_nl: nil,
        space_before: nil,
        space: nil
      }
      @json = JSON.generate @attributes, options
    end

  end

  class Malformed < Message
    def initialize core_version, attributes = {}
      # don't call super, just copy (potentially invalid) attributes
      @attributes = {}
      @invalid_attributes = attributes
    end
  end

  class Version < Message
    def initialize core_version, attributes = {}
      super(core_version, attributes.merge(
        "type" => "Version",
      ))
    end

    def versions
      attribute("RSMP").map{ |item| item["vers"] }
    end
  end

  class Unknown < Message
  end

  class AggregatedStatus < Message
    def initialize core_version, attributes = {}
      super(core_version, attributes.merge(
        "type" => "AggregatedStatus",
      ))
    end
  end

  class AggregatedStatusRequest < Message
    def initialize core_version, attributes = {}
      super(core_version, attributes.merge(
        "type" => "AggregatedStatusRequest",
      ))
    end
  end

  class Alarm < Message
    def initialize core_version, attributes = {}
      super(core_version, attributes.merge(
        "type" => "Alarm",
        "ntsOId" => '',
        "xNId" => '',
        "xACId" => '',
        "xNACId" => ''
      ))
    end

    def differ? from
      %w{aSp aCId ack aS sS aTs cat pri}.each do |key|
        return true if attribute(key).downcase != from.attribute(key).downcase
      end
      return true if attribute('rvs') != from.attribute('rvs')
      false
    end
  end

  class AlarmIssue < Alarm
    def initialize core_version, attributes = {}
      super(core_version, attributes.merge(
        "aSp" => "Issue"
      ))
    end
  end

  class AlarmRequest < Alarm
    def initialize core_version, attributes = {}
      super(core_version, attributes.merge(
        "aSp" => "Request",
      ))
    end
  end

  class AlarmAcknowledge < Alarm
    def initialize core_version, attributes = {}
      super(core_version, attributes.merge(
        "aSp" => "Acknowledge",
      ))
    end
  end

  class AlarmAcknowledged < Alarm
    def initialize core_version, attributes = {}
      super(core_version, attributes.merge(
        "aSp" => "Acknowledge",
        "ack" => "Acknowledged"
      ))
      p @attributes
    end
  end
  class AlarmSuspend < Alarm
    def initialize core_version, attributes = {}
      super(core_version, attributes.merge(
        "aSp" => "Suspend",
      ))
    end
  end

  class AlarmSuspended < Alarm
    def initialize core_version, attributes = {}
      super(core_version, attributes.merge(
        "aSp" => "Suspend",
        "sS" => "Suspended"
      ))
    end
  end

  class AlarmResume < Alarm
    def initialize core_version, attributes = {}
      super(core_version, attributes.merge(
        "aSp" => "Resume",
      ))
    end
  end

  class AlarmResumed < Alarm
    def initialize core_version, attributes = {}
      super(core_version, attributes.merge(
        "aSp" => "Suspend",
        "sS" => "notSuspended"
      ))
    end
  end

  class Watchdog < Message
    def initialize core_version, attributes = {}
      super(core_version, attributes.merge(
        "type" => "Watchdog",
      ))
    end
  end

  class MessageAcking < Message
    attr_reader :original

    def self.build_from message, core_version
      return new(core_version, {
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
 
     def ensure_message_id
      # Ack and NotAck does not have a mId
    end
  end

  class MessageAck < MessageAcking
    def initialize core_version, attributes = {}
      p attributes
      super(core_version, attributes.merge(
        "type" => "MessageAck",
      ))
    end
  end

  class MessageNotAck < MessageAcking
    def initialize core_version, attributes = {}
      super(core_version, attributes.merge(
        "type" => "MessageNotAck",
        "rea" => "Unknown reason"
      ))
      @attributes.delete "mId"
   end
  end

  class CommandRequest < Message
    def initialize core_version, attributes = {}
      super(core_version, attributes.merge(
        "type" => "CommandRequest",
      ))
    end
  end

  class CommandResponse < Message
    def initialize core_version, attributes = {}
      super(core_version, attributes.merge(
        "type" => "CommandResponse",
      ))
    end
  end

  class StatusRequest < Message
    def initialize core_version, attributes = {}
      super(core_version, attributes.merge(
        "type" => "StatusRequest",
      ))
    end
  end

  class StatusResponse < Message
    def initialize core_version, attributes = {}
      super(core_version, attributes.merge(
        "type" => "StatusResponse",
      ))
    end
  end

  class StatusSubscribe < Message
    def initialize core_version, attributes = {}
      super(core_version, attributes.merge(
        "type" => "StatusSubscribe",
      ))
    end
  end

  class StatusUnsubscribe < Message
    def initialize core_version, attributes = {}
      super(core_version, attributes.merge(
        "type" => "StatusUnsubscribe",
      ))
    end
  end

  class StatusUpdate < Message
    def initialize core_version, attributes = {}
      super(core_version, attributes.merge(
        "type" => "StatusUpdate",
      ))
    end
  end

end