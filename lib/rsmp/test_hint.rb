module RSMP
  # Optional Test Hub convention, not an RSMP acknowledgement of a real message.
  module TestHint
    ORIGINAL_MESSAGE_ID = '00000000-0000-4000-8000-000000000000'.freeze
    PREFIX = 'test: '.freeze

    def self.build(scenario)
      raise ArgumentError, 'scenario must be a nonempty string' unless scenario.is_a?(String) && !scenario.empty?

      MessageNotAck.new('oMId' => ORIGINAL_MESSAGE_ID, 'rea' => PREFIX + JSON.generate('scenario' => scenario))
    end

    def self.scenario(message)
      return unless message.attribute('oMId') == ORIGINAL_MESSAGE_ID

      reason = message.attributes['rea']
      return unless reason.is_a?(String) && reason.start_with?(PREFIX)

      payload = JSON.parse(reason.delete_prefix(PREFIX))
      payload['scenario'] if payload.is_a?(Hash) && payload['scenario'].is_a?(String)
    rescue JSON::ParserError
      nil
    end
  end
end
