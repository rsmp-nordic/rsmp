require 'cbor'

module RSMP
  module Secure
    # Deterministic CBOR helper for secure frames and payloads.
    module Cbor
      module_function

      def encode(value)
        CBOR.encode(normalize(value))
      end

      def decode(bytes, deterministic: true)
        value = normalize(CBOR.decode(bytes))
        raise FrameError, 'CBOR value is not deterministic' if deterministic && encode(value) != bytes

        value
      rescue CBOR::MalformedFormatError, ArgumentError => e
        raise FrameError, "Invalid CBOR: #{e.message}"
      end

      def normalize(value)
        case value
        when Hash
          value.keys.sort_by { |key| CBOR.encode(key.to_s) }.to_h do |key|
            [key.to_s, normalize(value[key])]
          end
        when Array
          value.map { |item| normalize(item) }
        else
          value
        end
      end
    end
  end
end
