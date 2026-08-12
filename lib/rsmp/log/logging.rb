#
# RSMP base class
#

module RSMP
  # Logging integration providing `archive` and `logger` helpers.
  module Logging
    # Preserves non-sensitive filtering metadata without retaining plaintext.
    class RedactedSecureMessage
      attr_reader :type, :direction, :original

      def initialize(message)
        @type = safe_type(message).freeze
        @direction = message.direction
        @original = self.class.new(message.original) if message.respond_to?(:original) && message.original
        freeze
      end

      def attributes
        {}
      end

      def m_id; end

      def json; end

      private

      def safe_type(message)
        type = message.type.to_s
        return type.dup if RSMP::Message.message_types.key?(type) || type == 'Alarm'

        message.class.name.split('::').last
      end
    end

    attr_reader :archive, :logger

    def initialize_logging(options)
      @archive = options[:archive] || RSMP::Archive.new
      @logger = options[:logger] || RSMP::Logger.new(options[:log_settings])
    end

    def author; end

    def log(str, options = {})
      str, options = redact_secure_payload(str, options)
      default = { text: str, level: :log, author: author, ip: @ip, port: @port }
      prepared = RSMP::Archive.prepare_item default.merge(options)
      @archive.add prepared
      @logger.log prepared
      prepared
    end

    private

    def redact_secure_payload(str, options)
      message = options[:message]
      return [str, options] unless message
      return [str, options] unless @protocol.respond_to?(:log_decrypted_payloads?)
      return [str, options] if @protocol.log_decrypted_payloads?

      redacted = RedactedSecureMessage.new(message)
      text = "Received secure RSMP #{redacted.type} (payload redacted)"
      text = "Sent secure RSMP #{redacted.type} (payload redacted)" if redacted.direction == :out
      [text, options.except(:exception).merge(message: redacted)]
    end
  end
end
