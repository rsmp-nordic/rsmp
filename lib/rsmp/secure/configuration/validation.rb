module RSMP
  module Secure
    # Fail-closed validation for credential files, transport mode, and bounds.
    module ConfigurationValidation
      def validate_local_identity!(secure_settings)
        secure_settings = settings(secure_settings)
        return unless mode?(secure_settings)

        validate_profile!(secure_settings)
        validate_local_identity_file!(secure_settings, 'private_key')
        validate_local_identity_file!(secure_settings, 'credential')
      end

      def validate_transport_mode!(secure_settings, connection_role:)
        secure_settings = stringify_keys(secure_settings || {})
        return true unless connection_role.to_s == 'server'
        return true unless secure_settings['enabled'] == true && secure_settings['required'] != true

        raise RSMP::ConfigurationError,
              'secure.enabled does not secure an inbound listener; use secure.required: true'
      end

      def validate_peer_files!(secure_settings)
        secure_settings = settings(secure_settings)
        return unless mode?(secure_settings)

        validate_profile!(secure_settings)
        (secure_settings['peers'] || []).each do |peer|
          validate_peer_file!(secure_settings, peer, 'credential')
        end
      end

      def validate_credentials!(secure_settings)
        secure_settings = settings(secure_settings)
        return unless mode?(secure_settings)

        validate_local_identity!(secure_settings)
        peers = secure_settings['peers']
        raise RSMP::ConfigurationError, 'secure peer credentials must be configured on the RSMP peer entry' unless peers
        raise RSMP::ConfigurationError, 'secure.peers must not be empty' if peers.empty?

        validate_rekey_settings!(secure_settings)
        validate_peer_files!(secure_settings)
        ProfileCredentials.new(secure_settings).validate!
      rescue RSMP::Secure::ConfigurationError => e
        raise RSMP::ConfigurationError, e.message
      end

      def validate_rekey_settings!(secure_settings)
        secure_settings = settings(secure_settings)
        validate_bounded_integer!(secure_settings, 'max_frame_size', DEFAULT_MAX_FRAME_SIZE)
        validate_fixed_timeout!(secure_settings, 'handshake_timeout', DEFAULT_HANDSHAKE_TIMEOUT)
        validate_fixed_timeout!(secure_settings, 'rekey_timeout', DEFAULT_REKEY_TIMEOUT)
        validate_bounded_integer!(secure_settings, 'rekey_after_messages', MAX_REKEY_AFTER_MESSAGES, minimum: 3)
        byte_minimum = (2 * secure_settings['max_frame_size']) + 1
        validate_bounded_integer!(secure_settings, 'rekey_after_bytes', MAX_REKEY_AFTER_BYTES,
                                  minimum: byte_minimum)
        validate_bounded_number!(secure_settings, 'rekey_after_seconds', MAX_REKEY_AFTER_SECONDS,
                                 minimum: DEFAULT_REKEY_TIMEOUT)
      end

      private

      def validate_profile!(secure_settings)
        Secure.validate_profile_name!(secure_settings['profile'])
      end

      def validate_local_identity_file!(secure_settings, key)
        path = secure_settings[key]
        raise RSMP::ConfigurationError, "secure.#{key} is required" unless path

        expanded = expand_config_path(path, secure_settings)
        raise RSMP::ConfigurationError, "secure.#{key} file not found: #{expanded}" unless File.file?(expanded)
      end

      def validate_peer_file!(secure_settings, peer, key)
        path = peer[key]
        raise RSMP::ConfigurationError, "secure peer #{peer['id']} #{key} is required" unless path

        expanded = expand_config_path(path, secure_settings)
        return if File.file?(expanded)

        raise RSMP::ConfigurationError, "secure peer #{peer['id']} #{key} file not found: #{expanded}"
      end

      def validate_bounded_integer!(settings, key, maximum, minimum: 1)
        value = settings[key]
        valid = value.is_a?(Integer) && value >= minimum && value <= maximum
        return if valid

        raise RSMP::ConfigurationError, "secure.#{key} must be an integer from #{minimum} through #{maximum}"
      end

      def validate_bounded_number!(settings, key, maximum, minimum: 0)
        value = settings[key]
        valid = value.is_a?(Numeric) && value > minimum && value <= maximum
        return if valid

        raise RSMP::ConfigurationError, "secure.#{key} must be greater than #{minimum} and at most #{maximum}"
      end

      def validate_fixed_timeout!(settings, key, expected)
        return if settings[key] == expected

        raise RSMP::ConfigurationError, "secure.#{key} must be #{expected} seconds"
      end
    end
  end
end
