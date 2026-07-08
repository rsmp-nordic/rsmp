module RSMP
  module Secure
    # Loads secure credential files and unwraps profile-specific credential formats.
    class ProfileCredentials
      def initialize(settings)
        @settings = settings
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
        bundled_peer_credential(public_key, credential)
      end

      def bundled_peer_credential(public_key, credential)
        bundle = CredentialBundle.decode(credential, expected_profile: @settings['profile'])
        bundle_public_key = CredentialBundle.public_key(bundle)
        validate_peer_bundle!(public_key, bundle, bundle_public_key)

        {
          id: CredentialBundle.id(bundle),
          public_key: bundle_public_key,
          edhoc_credential: CredentialBundle.edhoc_credential(bundle),
          kid: CredentialBundle.kid(bundle)
        }
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
