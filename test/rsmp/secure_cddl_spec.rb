require 'cbor'

ENV['CDDL_UNUSED_OK'] ||= '1'

require 'cddl'
require 'openssl'
require 'rsmp'

module SecureCddlSpecSupport
  SCHEMA = File.read(File.expand_path('../../schemas/secure/rsmp-secure-v1.cddl', __dir__)).freeze

  module_function

  def parser
    @parser ||= with_warnings_silenced do
      CDDL::Parser.new(SCHEMA).tap(&:rules)
    end
  end

  def rule(root)
    rules[root] ||= parser.send(:rule_lookup, root, false)
  end

  def validate(root, value)
    parser.instance_variable_set(:@recursion, 0)

    with_warnings_silenced { parser.validate1a(value, rule(root)) }
  end

  def rules
    @rules ||= {}
  end

  def with_warnings_silenced
    previous_verbose = $VERBOSE
    $VERBOSE = nil
    yield
  ensure
    $VERBOSE = previous_verbose
  end
end

describe 'Secure RSMP CDDL schemas' do
  def assert_cddl(root, cbor_bytes)
    assert_cddl_value(root, CBOR.decode(cbor_bytes.b))
  end

  def assert_cddl_value(root, value)
    return true if SecureCddlSpecSupport.validate(root, value)

    raise "CDDL validation failed for #{root}: #{SecureCddlSpecSupport.parser.validate_diag.inspect}"
  end

  def secure_credential(id)
    key = OpenSSL::PKey.generate_key('ED25519')

    RSMP::Secure::CredentialBundle.create(id: id,
                                          profile: RSMP::Secure::PROFILE,
                                          private_key: key.raw_private_key + key.raw_public_key,
                                          public_key: key.raw_public_key)
  end

  it 'validates generated credential bundles and embedded credential structures' do
    credential = secure_credential('RN+SI0001')
    bundle = CBOR.decode(credential)

    expect(assert_cddl('credential-bundle', credential)).to be == true
    expect(assert_cddl_value('cose-key-ed25519', bundle.fetch('cose_key'))).to be == true
    expect(assert_cddl('ccs-credential', bundle.fetch('edhoc_credential'))).to be == true
  end

  it 'validates secure frames and decrypted rekey plaintext' do
    secret = 's' * RSMP::Secure::Channel::EXPORTER_SECRET_BYTES
    channel = RSMP::Secure::Channel.new(secret, role: :initiator)
    data_frame = channel.encrypt_payload(RSMP::Secure::Cbor.encode('mType' => 'rSMsg', 'type' => 'Watchdog'))
    rekey_plaintext = { 'kind' => 'rekey_msg1', 'next_epoch' => 1, 'edhoc' => 'msg1'.b }
    rekey_frame = channel.encrypt_control(rekey_plaintext)
    edhoc_frame = {
      'v' => RSMP::Secure::VERSION,
      'type' => 'edhoc',
      'profile' => RSMP::Secure::PROFILE,
      'msg' => 1,
      'edhoc' => 'edhoc-message-1'.b
    }

    expect(assert_cddl_value('secure-message', edhoc_frame)).to be == true
    expect(assert_cddl_value('edhoc-frame', edhoc_frame)).to be == true
    expect(assert_cddl_value('secure-message', data_frame)).to be == true
    expect(assert_cddl_value('data-frame', data_frame)).to be == true
    expect(assert_cddl_value('secure-message', rekey_frame)).to be == true
    expect(assert_cddl_value('rekey-frame', rekey_frame)).to be == true
    expect(assert_cddl('rekey-plaintext', RSMP::Secure::Cbor.encode(rekey_plaintext))).to be == true
  end

  it 'validates exporter context, HKDF info, and AEAD AAD structures' do
    rsmp_context = RSMP::Secure::Channel.rsmp_context(
      profile: RSMP::Secure::PROFILE,
      initiator_id: 'RN+SI0001',
      responder_id: 'supervisor'
    )
    channel = RSMP::Secure::Channel.new('s' * RSMP::Secure::Channel::EXPORTER_SECRET_BYTES,
                                        role: :initiator,
                                        rsmp_context: rsmp_context)

    expect(assert_cddl('rsmp-context', rsmp_context)).to be == true
    expect(assert_cddl('hkdf-info', RSMP::Secure::Cbor.encode(
                                      'context' => 'rsmp-secure-v1 hkdf',
                                      'label' => 'traffic secret',
                                      'rsmp_context' => rsmp_context
                                    ))).to be == true
    expect(assert_cddl('hkdf-info', RSMP::Secure::Cbor.encode(
                                      'context' => 'rsmp-secure-v1 hkdf',
                                      'label' => 'i2r key'
                                    ))).to be == true
    expect(assert_cddl('secure-aad', channel.send(:aad, 'data', 'i2r', 1))).to be == true
    expect(assert_cddl('secure-aad', channel.send(:aad, 'rekey', 'i2r', 2))).to be == true
  end
end
