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
          pairs = value.map do |key, item|
            [normalize_key(key), normalize(item)]
          end
          pairs.sort_by { |key, _item| deterministic_key_order(key) }.to_h
        when Array
          value.map { |item| normalize(item) }
        else
          value
        end
      end

      def normalize_key(key)
        key.is_a?(Integer) ? key : key.to_s
      end

      def deterministic_key_order(key)
        encoded = CBOR.encode(key)
        [encoded.bytesize, encoded]
      end
    end
  end
end
