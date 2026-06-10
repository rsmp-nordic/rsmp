module RSMP
  # Resolves SXL schemas from message code ownership.
  module Schema
    MESSAGE_CODE_EXTRACTORS = {
      'StatusRequest' => ->(message) { status_codes(message) },
      'StatusSubscribe' => ->(message) { status_codes(message) },
      'StatusUnsubscribe' => ->(message) { status_codes(message) },
      'StatusResponse' => ->(message) { status_codes(message) },
      'StatusUpdate' => ->(message) { status_codes(message) },
      'CommandRequest' => ->(message) { request_command_codes(message) },
      'CommandResponse' => ->(message) { response_command_codes(message) },
      'Alarm' => ->(message) { alarm_codes(message) }
    }.freeze

    MESSAGE_CODE_KINDS = {
      'StatusRequest' => :statuses,
      'StatusSubscribe' => :statuses,
      'StatusUnsubscribe' => :statuses,
      'StatusResponse' => :statuses,
      'StatusUpdate' => :statuses,
      'CommandRequest' => :commands,
      'CommandResponse' => :commands,
      'Alarm' => :alarms
    }.freeze

    def self.message_codes(message)
      extractor = MESSAGE_CODE_EXTRACTORS[message['type']]
      extractor ? extractor.call(message).uniq : []
    end

    def self.status_codes(message)
      (message['sS'] || []).map { |item| item['sCI'] }.compact
    end

    def self.request_command_codes(message)
      (message['arg'] || []).map { |item| item['cCI'] }.compact
    end

    def self.response_command_codes(message)
      (message['rvs'] || []).map { |item| item['cCI'] }.compact
    end

    def self.alarm_codes(message)
      [message['aCId']].compact
    end

    def self.message_code_kind(message)
      MESSAGE_CODE_KINDS[message['type']]
    end

    def self.sxl_defines_codes?(type, version, kind, codes, options)
      version = sanitize_version(version.to_s) if options[:lenient]
      catalogue = sxl_catalogue(type, version, kind)
      prefix = sxl_prefix(type, version, options)
      codes.all? do |code|
        unprefixed = prefix && code.start_with?(prefix) ? code[prefix.length..] : code
        catalogue.key?(code) || catalogue.key?(code.to_sym) ||
          catalogue.key?(unprefixed) || catalogue.key?(unprefixed.to_sym)
      end
    end

    def self.message_code_kind_name(kind)
      {
        statuses: 'status',
        commands: 'command',
        alarms: 'alarm'
      }.fetch(kind) { kind.to_s.delete_suffix('s') }
    end

    def self.resolve_sxl(message, schemas:, **options)
      kind = message_code_kind(message)
      codes = message_codes(message)
      return nil unless kind && codes.any?

      matches = matching_sxl_schemas(schemas, kind, codes, options)
      raise_if_no_sxl_match(kind, codes) if matches.empty?
      raise_if_ambiguous_sxl_match(codes, matches) if matches.size > 1

      matches.first
    end

    def self.matching_sxl_schemas(schemas, kind, codes, options)
      sxl_schemas(schemas).select do |type, version|
        sxl_defines_codes?(type, version, kind, codes, options)
      rescue UnknownSchemaError
        false
      end
    end

    def self.sxl_schemas(schemas)
      schemas.reject { |type, _version| type.to_sym == :core }
    end

    def self.raise_if_no_sxl_match(kind, codes)
      raise UnknownMessageCodeError,
            "No accepted SXL defines #{message_code_kind_name(kind)} code(s) #{codes.join(', ')}"
    end

    def self.raise_if_ambiguous_sxl_match(codes, matches)
      names = matches.map { |type, version| "#{type} #{version}" }.join(', ')
      raise AmbiguousMessageCodeError, "Message code(s) #{codes.join(', ')} match multiple accepted SXLs: #{names}"
    end
  end
end
