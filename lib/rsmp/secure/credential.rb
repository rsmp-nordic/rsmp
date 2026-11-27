require 'digest'
require 'openssl'

module RSMP
  module Secure
    # Exact deterministic-CBOR CCS credential pinned by the Secure RSMP profile.
    module Credential
      CWT_SUBJECT = 2
      CWT_CONFIRMATION = 8
      CWT_CONFIRMATION_COSE_KEY = 1
      COSE_KEY_TYPE = 1
      COSE_KEY_ID = 2
      COSE_KEY_CURVE = -1
      COSE_KEY_PUBLIC = -2
      COSE_KEY_TYPE_OKP = 1
      COSE_CURVE_ED25519 = 6
      KID_BYTES = 16
      PUBLIC_KEY_BYTES = 32
      REQUIRED_CREDENTIAL_KEYS = [CWT_SUBJECT, CWT_CONFIRMATION].freeze
      REQUIRED_CONFIRMATION_KEYS = [CWT_CONFIRMATION_COSE_KEY].freeze
      REQUIRED_COSE_KEY_KEYS = [COSE_KEY_PUBLIC, COSE_KEY_CURVE, COSE_KEY_TYPE, COSE_KEY_ID].freeze

      module_function

      def create(id:, public_key:)
        id = normalized_identity(id)
        validate_public_key!(public_key)
        Cbor.encode(credential_map(id, public_key))
      end

      def decode(bytes)
        credential = Cbor.decode(bytes)
        validate_exact_keys!(credential, REQUIRED_CREDENTIAL_KEYS, 'credential')
        normalized_identity(credential[CWT_SUBJECT])

        confirmation = credential[CWT_CONFIRMATION]
        validate_exact_keys!(confirmation, REQUIRED_CONFIRMATION_KEYS, 'credential cnf')
        validate_cose_key!(confirmation[CWT_CONFIRMATION_COSE_KEY])
        validate_derived_kid!(confirmation[CWT_CONFIRMATION_COSE_KEY])
        credential
      rescue FrameError, ArgumentError => e
        raise ConfigurationError, "invalid CCS credential: #{e.message}"
      end

      def id(credential)
        credential.fetch(CWT_SUBJECT)
      end

      def cose_key(credential)
        credential.fetch(CWT_CONFIRMATION).fetch(CWT_CONFIRMATION_COSE_KEY)
      end

      def public_key(credential)
        cose_key(credential).fetch(COSE_KEY_PUBLIC)
      end

      def kid(credential)
        cose_key(credential).fetch(COSE_KEY_ID)
      end

      def key_id(public_key)
        Digest::SHA256.digest(public_key).byteslice(0, KID_BYTES)
      end

      def credential_map(id, public_key)
        {
          CWT_SUBJECT => id,
          CWT_CONFIRMATION => {
            CWT_CONFIRMATION_COSE_KEY => {
              COSE_KEY_TYPE => COSE_KEY_TYPE_OKP,
              COSE_KEY_ID => key_id(public_key),
              COSE_KEY_CURVE => COSE_CURVE_ED25519,
              COSE_KEY_PUBLIC => public_key
            }
          }
        }
      end

      def normalized_identity(value)
        text = value.dup.force_encoding(Encoding::UTF_8) if value.is_a?(String)
        valid = text&.valid_encoding? && !text.empty?
        raise ArgumentError, 'credential subject must be a non-empty UTF-8 text string' unless valid

        text
      end

      def validate_public_key!(value)
        return if value.is_a?(String) && value.bytesize == PUBLIC_KEY_BYTES

        raise ArgumentError, "credential public key must be #{PUBLIC_KEY_BYTES} bytes"
      end

      def validate_cose_key!(key)
        validate_exact_keys!(key, REQUIRED_COSE_KEY_KEYS, 'credential COSE_Key')
        raise ArgumentError, 'credential COSE_Key kty must be OKP (1)' unless key[COSE_KEY_TYPE] == COSE_KEY_TYPE_OKP
        unless key[COSE_KEY_CURVE] == COSE_CURVE_ED25519
          raise ArgumentError, 'credential COSE_Key crv must be Ed25519 (6)'
        end

        validate_public_key!(key[COSE_KEY_PUBLIC])
        kid = key[COSE_KEY_ID]
        return if kid.is_a?(String) && kid.bytesize == KID_BYTES

        raise ArgumentError, "credential COSE_Key kid must be #{KID_BYTES} bytes"
      end

      def validate_derived_kid!(key)
        expected = key_id(key.fetch(COSE_KEY_PUBLIC))
        actual = key.fetch(COSE_KEY_ID)
        return if OpenSSL.fixed_length_secure_compare(expected, actual)

        raise ArgumentError, 'credential COSE_Key kid does not match its public key'
      end

      def validate_exact_keys!(value, expected, name)
        raise ArgumentError, "#{name} must be a CBOR map" unless value.is_a?(Hash)
        return if value.keys.sort == expected.sort

        raise ArgumentError, "#{name} must contain exactly the Secure RSMP v1 fields"
      end
    end
  end
end
