require 'json'

module RSMP
  module Secure
    class Protocol
      # Enforces the protected Version exchange before ordinary RSMP dispatch.
      class MessageState
        VERSION_ACK_TYPES = %w[MessageAck MessageNotAck].freeze

        def initialize
          clear!
        end

        def clear!
          @inbound_version_id = nil
          @outbound_version_id = nil
          @inbound_version_acknowledged = false
          @outbound_version_acknowledged = false
        end

        def validate!(line, direction:, authorized:)
          attributes = parse(line, direction)
          type = attributes['type']
          if type == 'Version'
            register_version!(attributes, direction)
          elsif VERSION_ACK_TYPES.include?(type)
            validate_version_acknowledgement!(attributes, direction, authorized)
          elsif !authorized
            raise AuthenticationError, "RSMP #{type.inspect} is not permitted before secure authorization"
          end
          attributes
        end

        private

        def parse(line, direction)
          attributes = JSON.parse(line)
          return attributes if attributes.is_a?(Hash)

          raise FrameError, "#{direction.to_s.capitalize} secure RSMP message must be an object"
        rescue JSON::ParserError => e
          raise FrameError, "Invalid #{direction} secure RSMP JSON: #{e.message}"
        end

        def register_version!(attributes, direction)
          variable = direction == :inbound ? :@inbound_version_id : :@outbound_version_id
          existing = instance_variable_get(variable)
          raise AuthenticationError, "Secure connection received a second #{direction} RSMP Version" if existing

          message_id = attributes['mId']
          unless message_id.is_a?(String) && !message_id.empty?
            raise FrameError, "#{direction.to_s.capitalize} RSMP Version must contain a non-empty message id"
          end

          instance_variable_set(variable, message_id.dup.freeze)
        end

        def validate_version_acknowledgement!(attributes, direction, authorized)
          expected, acknowledged_variable = version_acknowledgement_state(direction)
          acknowledged = instance_variable_get(acknowledged_variable)
          if expected && !acknowledged
            validate_version_reference!(attributes, direction, expected)
            instance_variable_set(acknowledged_variable, true)
          elsif !authorized
            raise AuthenticationError,
                  "RSMP #{attributes['type'].inspect} is not permitted without a pending protected Version exchange"
          end
        end

        def validate_version_reference!(attributes, direction, expected)
          return if attributes['oMId'] == expected

          raise AuthenticationError,
                "#{direction.to_s.capitalize} acknowledgement does not acknowledge the protected Version exchange"
        end

        def version_acknowledgement_state(direction)
          if direction == :inbound
            [@outbound_version_id, :@outbound_version_acknowledged]
          else
            [@inbound_version_id, :@inbound_version_acknowledged]
          end
        end
      end
    end
  end
end
