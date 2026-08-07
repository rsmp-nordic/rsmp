require 'edhoc'
require 'openssl'

module RSMP
  module Secure
    # Loads the exact pinned CCS credentials and implements ruby-edhoc callbacks.
    class ProfileCredentials
      ED25519_PRIVATE_KEY_BYTES = 64
      ED25519_PUBLIC_KEY_BYTES = 32

      Peer = Struct.new(
        :id, :kid, :credential, :public_key, :rsmp_id, :rsmp_role, :core_versions,
        keyword_init: true
      )

      def initialize(settings)
        @settings = settings
        load_local!
        load_peers!
      end

      def validate!
        validate_private_key!(@private_key)
        validate_private_key_credential!
      end

      attr_reader :private_key

      def local_id
        Credential.id(@local_credential)
      end

      def select_local(context)
        validate_context!(context)
        Edhoc::LocalCredential.new(
          private_key: @private_key,
          identification: Edhoc::Credentials::KID.new(
            identifier: Credential.kid(@local_credential),
            credential: @local_credential_bytes,
            format: :cbor
          )
        )
      end

      def authenticate_peer(context, received)
        validate_context!(context)
        return unless received.kind == :kid && received.identifier

        peer = @peers_by_kid[received.identifier]
        return unless peer

        Edhoc::TrustedCredential.new(
          credential: peer.credential,
          public_key: peer.public_key,
          format: :cbor,
          peer_id: peer.id
        )
      end

      def peer(id)
        @peers_by_id[id]
      end

      def clear!
        wipe!(@private_key)
        wipe!(@local_credential_bytes)
        @peers_by_id.each_value do |peer|
          wipe!(peer.credential)
          wipe!(peer.public_key)
        end
      end

      private

      def load_local!
        @private_key = read_file('private_key')
        @local_credential_bytes = read_file('credential')
        @local_credential = Credential.decode(@local_credential_bytes)
        validate_local_id!
      end

      def load_peers!
        @peers_by_id = {}
        @peers_by_kid = {}
        @settings.fetch('peers').each do |settings|
          peer = load_peer(settings)
          if @peers_by_id.key?(peer.id)
            raise ConfigurationError, "duplicate secure peer credential subject #{peer.id.inspect}"
          end
          if @peers_by_kid.key?(peer.kid)
            raise ConfigurationError, "duplicate secure peer credential KID #{peer.kid.unpack1('H*')}"
          end

          @peers_by_id[peer.id] = peer
          @peers_by_kid[peer.kid] = peer
        end
      end

      def load_peer(settings)
        bytes = read_path(settings['credential'], "peers.#{settings['id']}.credential")
        credential = Credential.decode(bytes)
        validate_peer_id!(settings, credential)
        Peer.new(
          id: Credential.id(credential),
          kid: Credential.kid(credential),
          credential: bytes,
          public_key: Credential.public_key(credential).dup,
          rsmp_id: settings[RSMP_ID_KEY] || Credential.id(credential),
          rsmp_role: settings[RSMP_ROLE_KEY] || 'peer',
          core_versions: Array(settings[CORE_VERSIONS_KEY]).map(&:to_s).freeze
        ).freeze
      end

      def validate_private_key!(private_key)
        unless private_key.bytesize == ED25519_PRIVATE_KEY_BYTES
          raise ConfigurationError,
                "secure.private_key must contain a #{ED25519_PRIVATE_KEY_BYTES}-byte Ed25519 private key"
        end

        signing_key = OpenSSL::PKey.new_raw_private_key('Ed25519', private_key.byteslice(0, 32))
        derived = signing_key.raw_public_key
        supplied = private_key.byteslice(32, ED25519_PUBLIC_KEY_BYTES)
        return if OpenSSL.fixed_length_secure_compare(derived, supplied)

        raise ConfigurationError, 'secure.private_key public key does not match its private seed'
      end

      def validate_private_key_credential!
        expected = @private_key.byteslice(32, ED25519_PUBLIC_KEY_BYTES)
        actual = Credential.public_key(@local_credential)
        return if OpenSSL.fixed_length_secure_compare(expected, actual)

        raise ConfigurationError, "CCS credential #{local_id.inspect} does not match private key"
      end

      def validate_local_id!
        expected = @settings[LOCAL_ID_KEY]
        return unless expected
        return if local_id == expected

        raise ConfigurationError,
              "CCS credential #{local_id.inspect} does not match local id #{expected.inspect}"
      end

      def validate_peer_id!(settings, credential)
        expected = settings[PEER_ID_KEY]
        actual = Credential.id(credential)
        return unless expected
        return if actual == expected

        raise ConfigurationError,
              "CCS credential #{actual.inspect} does not match peer id #{expected.inspect}"
      end

      def validate_context!(context)
        valid = context.method.zero? && context.cipher_suite == 4 && context.authentication == :signature
        return if valid

        raise ConfigurationError, 'EDHOC callback does not match Secure RSMP method 0, suite 4, signature profile'
      end

      def read_file(key)
        path = @settings[key]
        raise ConfigurationError, "secure.#{key} is required" unless path

        read_path(path, key)
      end

      def read_path(path, key)
        raise ConfigurationError, "secure.#{key} is required" unless path

        expanded = Secure.expand_config_path(path, @settings)
        raise ConfigurationError, "secure.#{key} file not found: #{expanded}" unless File.file?(expanded)

        File.binread(expanded)
      end

      def wipe!(value)
        return unless value.is_a?(String) && !value.frozen?

        value.replace("\0" * value.bytesize)
        value.clear
      end
    end
  end
end
