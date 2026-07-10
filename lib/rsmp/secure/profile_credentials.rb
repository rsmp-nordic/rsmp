require 'openssl'

module RSMP
  module Secure
    # Loads secure credential files and unwraps profile-specific credential formats.
    class ProfileCredentials
      ED25519_PRIVATE_KEY_BYTES = 64
      ED25519_PUBLIC_KEY_BYTES = 32

      def initialize(settings)
        @settings = settings
      end

      def validate!
        local_private_key = private_key
        validate_private_key!(local_private_key)
        local_session_options(local_private_key)
        peer_entries
      end

      def private_key
        read_file('private_key')
      end

      def local_id
        credential = read_file('credential')
        bundle = CredentialBundle.decode(credential, expected_profile: @settings['profile'])
        CredentialBundle.id(bundle)
      end

      def local_session_options(private_key)
        credential = read_file('credential')
        bundle = CredentialBundle.decode(credential, expected_profile: @settings['profile'])
        validate_local_id!(bundle)
        validate_private_key_bundle!(private_key, bundle)
        {
          credential: CredentialBundle.edhoc_credential(bundle),
          credential_format: :kid_cbor,
          kid: CredentialBundle.kid(bundle)
        }
      end

      def peer_entries
        @settings['peers'].map do |peer|
          credential = peer_credential(peer)
          {
            id: credential.fetch(:id),
            public_key: credential.fetch(:public_key),
            credential: credential.fetch(:edhoc_credential),
            kid: credential[:kid]
          }
        end
      end

      private

      def peer_credential(peer)
        credential = read_path(peer['credential'], "peers.#{peer['id']}.credential")
        public_key = read_path(peer['public_key'], "peers.#{peer['id']}.public_key")
        validate_public_key!(public_key, peer)
        bundled_peer_credential(public_key, credential, peer)
      end

      def bundled_peer_credential(public_key, credential, peer)
        bundle = CredentialBundle.decode(
          credential,
          expected_profile: @settings['profile'],
          trusted_public_key: public_key
        )
        bundle_public_key = CredentialBundle.public_key(bundle)
        validate_peer_bundle!(public_key, bundle, bundle_public_key)
        validate_peer_id!(peer, bundle)

        {
          id: CredentialBundle.id(bundle),
          public_key: bundle_public_key,
          edhoc_credential: CredentialBundle.edhoc_credential(bundle),
          kid: CredentialBundle.kid(bundle)
        }
      end

      def validate_private_key!(private_key)
        unless private_key.bytesize == ED25519_PRIVATE_KEY_BYTES
          raise ConfigurationError,
                "secure.private_key must contain a #{ED25519_PRIVATE_KEY_BYTES}-byte Ed25519 private key"
        end

        signing_key = OpenSSL::PKey.new_raw_private_key('Ed25519', private_key.byteslice(0, 32))
        return if signing_key.raw_public_key == private_key.byteslice(32, 32)

        raise ConfigurationError, 'secure.private_key public key does not match its private seed'
      end

      def validate_public_key!(public_key, peer)
        return if public_key.bytesize == ED25519_PUBLIC_KEY_BYTES

        raise ConfigurationError,
              "secure peer #{peer['id']} public_key must contain a #{ED25519_PUBLIC_KEY_BYTES}-byte Ed25519 public key"
      end

      def validate_local_id!(bundle)
        expected_id = @settings[LOCAL_ID_KEY]
        return unless expected_id
        return if CredentialBundle.id(bundle) == expected_id

        raise ConfigurationError,
              "credential bundle #{CredentialBundle.id(bundle).inspect} does not match local id #{expected_id.inspect}"
      end

      def validate_peer_id!(peer, bundle)
        expected_id = peer[PEER_ID_KEY]
        return unless expected_id
        return if CredentialBundle.id(bundle) == expected_id

        raise ConfigurationError,
              "credential bundle #{CredentialBundle.id(bundle).inspect} does not match peer id #{expected_id.inspect}"
      end

      def validate_private_key_bundle!(private_key, bundle)
        return if private_key.byteslice(32, 32) == CredentialBundle.public_key(bundle)

        id = CredentialBundle.id(bundle).inspect
        raise ConfigurationError, "credential bundle #{id} does not match private key"
      end

      def validate_peer_bundle!(public_key, bundle, bundle_public_key)
        return if public_key == bundle_public_key

        id = CredentialBundle.id(bundle).inspect
        raise ConfigurationError, "credential bundle #{id} does not match peer public key"
      end

      def read_file(key)
        path = @settings[key]
        raise ConfigurationError, "secure.#{key} is required" unless path

        read_path(path, key)
      end

      def read_path(path, key)
        path = Secure.expand_config_path(path, @settings)
        raise ConfigurationError, "secure.#{key} file not found: #{path}" unless File.file?(path)

        File.binread(path)
      end
    end
  end
end
