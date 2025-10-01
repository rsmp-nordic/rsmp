require 'rsmp_schema'

# rsmp messages
module RSMP
  class Message
    include Inspect

    attr_reader :now, :attributes, :out, :timestamp # this is an internal timestamp recording when we receive/send
    attr_accessor :json, :direction

    MESSAGE_CLASS_MAP = {
      'MessageAck' => 'MessageAck',
      'MessageNotAck' => 'MessageNotAck',
      'Version' => 'Version',
      'AggregatedStatus' => 'AggregatedStatus',
      'AggregatedStatusRequest' => 'AggregatedStatusRequest',
      'Watchdog' => 'Watchdog',
      'CommandRequest' => 'CommandRequest',
      'CommandResponse' => 'CommandResponse',
      'StatusRequest' => 'StatusRequest',
      'StatusResponse' => 'StatusResponse',
      'StatusSubscribe' => 'StatusSubscribe',
      'StatusUnsubscribe' => 'StatusUnsubscribe',
      'StatusUpdate' => 'StatusUpdate'
    }.freeze

    def self.make_m_id
      SecureRandom.uuid
    end

    def self.parse_attributes(json)
      raise ArgumentError unless json

      JSON.parse json
    rescue JSON::ParserError
      raise InvalidPacket, bin_to_chars(json)
    end

    def self.build(attributes, json)
      validate_message_type attributes
      message = instantiate_message(attributes)
      message.json = json
      message.direction = :in
      message
    end

    def self.instantiate_message(attributes)
      type = attributes['type']
      return build_alarm(attributes) if type == 'Alarm'

      klass_name = MESSAGE_CLASS_MAP[type]
      klass = klass_name ? RSMP.const_get(klass_name) : Unknown
      klass.new attributes
    end

    def self.build_alarm(attributes)
      case attributes['aSp']
      when /^Issue$/i
        AlarmIssue.new attributes
      when /^Request$/i
        AlarmRequest.new attributes
      when /^Acknowledge$/i
        if attributes['ack'] =~ /^acknowledged$/i
          AlarmAcknowledged.new attributes
        else
          AlarmAcknowledge.new attributes
        end
      when /^Suspend$/i
        if attributes['sS'] =~ /^suspended$/i
          AlarmSuspended.new attributes
        elsif attributes['sS'] =~ /^notSuspended$/i
          AlarmResumed.new attributes
        else
          AlarmSuspend.new attributes
        end
      when /^Resume$/i
        AlarmResume.new attributes
      else
        Alarm.new attributes
      end
    end

    def type
      @attributes['type']
    end

    def m_id
      @attributes['mId']
    end

    def self.shorten_m_id(m_id, length = 4)
      m_id[0..(length - 1)]
    end

    def m_id_short
      Message.shorten_m_id @attributes['mId']
    end

    def attribute(key)
      unless @attributes.key? key # NOTE: that this is not the same as @attributes[key] when
        maybe = @attributes.find { |k, _v| k.downcase == key.downcase }
        raise MissingAttribute, "attribute '#{maybe.first}' should be named '#{key}'" if maybe

        raise MissingAttribute, "missing attribute '#{key}'"

      end
      @attributes[key]
    end

    def self.bin_to_chars(str)
      out = str.gsub(/[^[:print:]]/i, '.')
      max = 120
      if out.size <= max
        out
      else
        mid = ' ... '
        length = ((max - mid.size) / 2) - 1
        "#{out[0..length]} ... #{out[(-length - 1)..]}"
      end
    end

    def self.validate_message_type(attributes)
      ensure_hash!(attributes)
      ensure_message_type_present!(attributes)
      ensure_message_type_format!(attributes)
      ensure_type_present!(attributes)
      ensure_type_format!(attributes)
    end

    def self.ensure_hash!(attributes)
      return if attributes.is_a?(Hash)

      raise MalformedMessage, "JSON must be a Hash, got #{attributes.class} "
    end

    def self.ensure_message_type_present!(attributes)
      raise MalformedMessage, "'mType' is missing" unless attributes['mType']
    end

    def self.ensure_message_type_format!(attributes)
      unless attributes['mType'].is_a?(String)
        raise MalformedMessage,
              "'mType' must be a String, got #{attributes['mType'].class}"
      end
      return if attributes['mType'] == 'rSMsg'

      raise MalformedMessage,
            "'mType' must be 'rSMsg', got '#{attributes['mType']}'"
    end

    def self.ensure_type_present!(attributes)
      raise MalformedMessage, "'type' is missing" unless attributes['type']
    end

    def self.ensure_type_format!(attributes)
      return if attributes['type'].is_a?(String)

      raise MalformedMessage, "'type' must be a String, got #{attributes['type'].class}"
    end

    def initialize(attributes = {})
      super()
      @timestamp = Time.now # this timestamp is for internal use, and does not use the clock
      # in the node, which can be set by an rsmp supervisor

      @attributes = { 'mType' => 'rSMsg' }.merge attributes

      ensure_message_id
    end

    def ensure_message_id
      # if message id is empty, generate a new one
      @attributes['mId'] ||= Message.make_m_id
    end

    def validate(schemas)
      errors = RSMP::Schema.validate attributes, schemas
      return unless errors

      error_string = errors.map { |item| item.reject { |e| e == '' } }.compact.join(', ').strip
      err = SchemaError.new error_string.to_s
      err.schemas = schemas
      raise err
    end

    def validate_type?
      @attributes['mType'] == 'rSMsg'
    end

    def validate_id?
      !(@attributes['mId'] =~ /[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}/i).nil?
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
    # rubocop:disable Lint/MissingSuper
    def initialize(attributes = {})
      # don't call super, just copy (potentially invalid) attributes
      @attributes = {}
      @invalid_attributes = attributes
    end
    # rubocop:enable Lint/MissingSuper
  end

  class Version < Message
    def initialize(attributes = {})
      super({
        'type' => 'Version'
      }.merge attributes)
    end

    def versions
      attribute('RSMP').map { |item| item['vers'] }
    end
  end

  class Unknown < Message
  end

  class AggregatedStatus < Message
    def initialize(attributes = {})
      super({
        'type' => 'AggregatedStatus'
      }.merge attributes)
    end
  end

  class AggregatedStatusRequest < Message
    def initialize(attributes = {})
      super({
        'type' => 'AggregatedStatusRequest'
      }.merge attributes)
    end
  end

  class Alarm < Message
    def initialize(attributes = {})
      super({
        'type' => 'Alarm',
        'ntsOId' => '',
        'xNId' => '',
        'xACId' => '',
        'xNACId' => ''
      }.merge attributes)
    end

    def differ?(from)
      %w[aSp aCId ack aS sS aTs cat pri].each do |key|
        return true if attribute(key).downcase != from.attribute(key).downcase
      end
      return true if attribute('rvs') != from.attribute('rvs')

      false
    end
  end

  class AlarmIssue < Alarm
    def initialize(attributes = {})
      super({
        'aSp' => 'Issue'
      }.merge attributes)
    end
  end

  class AlarmRequest < Alarm
    def initialize(attributes = {})
      super({
        'aSp' => 'Request'
      }.merge attributes)
    end
  end

  class AlarmAcknowledge < Alarm
    def initialize(attributes = {})
      super({
        'aSp' => 'Acknowledge'
      }.merge attributes)
    end
  end

  class AlarmAcknowledged < Alarm
    def initialize(attributes = {})
      super({
        'aSp' => 'Acknowledge',
        'ack' => 'acknowledged'
      }.merge attributes)
    end
  end

  class AlarmSuspend < Alarm
    def initialize(attributes = {})
      super({
        'aSp' => 'Suspend'
      }.merge attributes)
    end
  end

  class AlarmSuspended < Alarm
    def initialize(attributes = {})
      super({
        'aSp' => 'Suspend',
        'sS' => 'Suspended'
      }.merge attributes)
    end
  end

  class AlarmResume < Alarm
    def initialize(attributes = {})
      super({
        'aSp' => 'Resume'
      }.merge attributes)
    end
  end

  class AlarmResumed < Alarm
    def initialize(attributes = {})
      super({
        'aSp' => 'Suspend',
        'sS' => 'notSuspended'
      }.merge attributes)
    end
  end

  class Watchdog < Message
    def initialize(attributes = {})
      super({
        'type' => 'Watchdog'
      }.merge attributes)
    end
  end

  class MessageAcking < Message
    attr_reader :original

    def self.build_from(message)
      new({
            'oMId' => message.attributes['mId']
          })
    end

    def original=(message)
      raise InvalidArgument unless message

      @original = message
    end

    def validate_id?
      true
    end
  end

  class MessageAck < MessageAcking
    def initialize(attributes = {})
      super({
        'type' => 'MessageAck'
      }.merge attributes)
    end

    def ensure_message_id
      # Ack and NotAck does not have a mId
    end
  end

  class MessageNotAck < MessageAcking
    def initialize(attributes = {})
      super({
        'type' => 'MessageNotAck',
        'rea' => 'Unknown reason'
      }.merge attributes)
      @attributes.delete 'mId'
    end
  end

  class CommandRequest < Message
    def initialize(attributes = {})
      super({
        'type' => 'CommandRequest'
      }.merge attributes)
    end
  end

  class CommandResponse < Message
    def initialize(attributes = {})
      super({
        'type' => 'CommandResponse'
      }.merge attributes)
    end
  end

  class StatusRequest < Message
    def initialize(attributes = {})
      super({
        'type' => 'StatusRequest'
      }.merge attributes)
    end
  end

  class StatusResponse < Message
    def initialize(attributes = {})
      super({
        'type' => 'StatusResponse'
      }.merge attributes)
    end
  end

  class StatusSubscribe < Message
    def initialize(attributes = {})
      super({
        'type' => 'StatusSubscribe'
      }.merge attributes)
    end
  end

  class StatusUnsubscribe < Message
    def initialize(attributes = {})
      super({
        'type' => 'StatusUnsubscribe'
      }.merge attributes)
    end
  end

  class StatusUpdate < Message
    def initialize(attributes = {})
      super({
        'type' => 'StatusUpdate'
      }.merge attributes)
    end
  end
end
