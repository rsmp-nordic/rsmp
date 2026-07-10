require 'cbor'
require 'digest'
require 'openssl'
require_relative 'cose_sign1'

module RSMP
  module Secure
    # Deterministic CBOR credential bundle used by the v1 profile.
    module CredentialBundle
      TYPE = 'rsmp-secure-credential'.freeze
      VERSION = 1
      EDHOC_CREDENTIAL_FORMAT = 'ccs-cbor'.freeze
      COSE_KEY_TYPE_OKP = 1
      COSE_KEY_ID = 2
      COSE_ALGORITHM_EDDSA = -8
      COSE_CURVE_ED25519 = 6
      CWT_SUBJECT = 2
      CWT_CONFIRMATION = 8
      CWT_CONFIRMATION_COSE_KEY = 1
      KID_BYTES = 16

      module_function

      def create(id:, profile:, private_key:, public_key:)
        payload = encode(unsigned_bundle(id: id,
                                         profile: profile,
                                         public_key: public_key))
        encode(CoseSign1.sign(payload, private_key: private_key))
      end

      def decode(bytes, expected_profile:, trusted_public_key: nil)
        cose_sign1 = Cbor.decode(bytes)
        payload = CoseSign1.payload(cose_sign1)
        bundle = Cbor.decode(payload)

        validate_bundle!(bundle, expected_profile)
        verify_signature!(cose_sign1, bundle, trusted_public_key || public_key(bundle))
        validate_edhoc_credential!(bundle)
        bundle
      rescue CBOR::MalformedFormatError, OpenSSL::PKey::PKeyError, ArgumentError, FrameError => e
        raise ConfigurationError, "invalid credential bundle: #{e.message}"
      end

      def bundle?(bytes)
        cose_sign1 = Cbor.decode(bytes)
        value = Cbor.decode(CoseSign1.payload(cose_sign1))
        value.is_a?(Hash) && value['type'] == TYPE
      rescue CBOR::MalformedFormatError, ArgumentError, FrameError
        false
      end

      def public_key(bundle)
        cose_key = bundle.fetch('cose_key')
        cose_key.fetch(-2)
      end

      def edhoc_credential(bundle)
        bundle.fetch('edhoc_credential')
      end

      def kid(bundle)
        bundle.fetch('kid')
      end

      def id(bundle)
        bundle.fetch('id')
      end

      def encode(value)
        CBOR.encode(normalize(value))
      end

      def verify_signature!(cose_sign1, bundle, verification_key)
        return if CoseSign1.verify(cose_sign1, public_key: verification_key)

        raise ConfigurationError, "credential bundle #{id(bundle).inspect} signature is invalid"
      end

      def unsigned_bundle(id:, profile:, public_key:)
        kid = key_id(public_key)
        {
          'v' => VERSION,
          'type' => TYPE,
          'profile' => profile,
          'id' => id,
          'kid' => kid,
          'cose_key' => cose_key(public_key, kid: kid),
          'edhoc_credential_format' => EDHOC_CREDENTIAL_FORMAT,
          'edhoc_credential' => ccs_credential(id, public_key, kid)
        }
      end

      def key_id(public_key)
        Digest::SHA256.digest(public_key).byteslice(0, KID_BYTES)
      end

      def ccs_credential(id, public_key, kid)
        encode({
                 CWT_SUBJECT => id,
                 CWT_CONFIRMATION => {
                   CWT_CONFIRMATION_COSE_KEY => cose_key(public_key, kid: kid)
                 }
               })
      end

      def cose_key(public_key, kid: nil)
        key = {
          1 => COSE_KEY_TYPE_OKP,
          3 => COSE_ALGORITHM_EDDSA,
          -1 => COSE_CURVE_ED25519,
          -2 => public_key
        }
        key[COSE_KEY_ID] = kid if kid
        key
      end

      def validate_bundle!(bundle, expected_profile)
        validate_bundle_header!(bundle, expected_profile)
        validate_cose_key!(bundle['cose_key'])
        validate_bundle_body!(bundle)
      end

      def validate_bundle_header!(bundle, expected_profile)
        raise ConfigurationError, 'credential bundle must be a CBOR map' unless bundle.is_a?(Hash)

        unless bundle['type'] == TYPE
          raise ConfigurationError, "unsupported credential bundle type #{bundle['type'].inspect}"
        end
        unless bundle['v'] == VERSION
          raise ConfigurationError, "unsupported credential bundle version #{bundle['v'].inspect}"
        end

        return if bundle['profile'] == expected_profile

        message = "credential bundle profile #{bundle['profile'].inspect} does not match #{expected_profile.inspect}"
        raise ConfigurationError, message
      end

      def validate_bundle_body!(bundle)
        unless bundle['id'].is_a?(String) && !bundle['id'].empty?
          raise ConfigurationError, 'credential bundle id is required'
        end

        unless bundle['edhoc_credential_format'] == EDHOC_CREDENTIAL_FORMAT
          raise ConfigurationError, "unsupported EDHOC credential format #{bundle['edhoc_credential_format'].inspect}"
        end

        unless bundle['edhoc_credential'].is_a?(String)
          raise ConfigurationError, 'credential bundle EDHOC credential is required'
        end

        validate_kid!(bundle)
      end

      def validate_kid!(bundle)
        return if bundle['kid'].is_a?(String) && bundle['kid'].bytesize.between?(1, 32)

        raise ConfigurationError, 'credential bundle kid must be 1..32 bytes'
      end

      def validate_cose_key!(cose_key)
        raise ConfigurationError, 'credential bundle COSE_Key must be a CBOR map' unless cose_key.is_a?(Hash)
        raise ConfigurationError, 'credential bundle COSE_Key kty must be OKP' unless cose_key[1] == COSE_KEY_TYPE_OKP

        validate_cose_key_algorithm!(cose_key)
        validate_cose_key_public_key!(cose_key)
        validate_cose_key_kid!(cose_key)
      end

      def validate_cose_key_algorithm!(cose_key)
        unless cose_key[3] == COSE_ALGORITHM_EDDSA
          raise ConfigurationError, 'credential bundle COSE_Key alg must be EdDSA'
        end

        return if cose_key[-1] == COSE_CURVE_ED25519

        raise ConfigurationError, 'credential bundle COSE_Key crv must be Ed25519'
      end

      def validate_cose_key_public_key!(cose_key)
        return if cose_key[-2].is_a?(String) && cose_key[-2].bytesize == 32

        raise ConfigurationError, 'credential bundle public key must be 32 bytes'
      end

      def validate_cose_key_kid!(cose_key)
        return if cose_key[COSE_KEY_ID].is_a?(String) && cose_key[COSE_KEY_ID].bytesize.between?(1, 32)

        raise ConfigurationError, 'credential bundle COSE_Key kid must be 1..32 bytes'
      end

      def validate_edhoc_credential!(bundle)
        unless bundle.fetch('cose_key').fetch(COSE_KEY_ID) == kid(bundle)
          raise ConfigurationError, "credential bundle #{id(bundle).inspect} kid does not match COSE_Key"
        end

        expected = ccs_credential(id(bundle), public_key(bundle), kid(bundle))
        return if bundle['edhoc_credential'] == expected

        raise ConfigurationError, "credential bundle #{id(bundle).inspect} EDHOC credential does not match COSE_Key"
      end

      def normalize(value)
        case value
        when Hash
          value.keys.sort_by { |key| CBOR.encode(key) }.to_h do |key|
            [key, normalize(value[key])]
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
