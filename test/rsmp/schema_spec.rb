require 'rsmp'
require 'tmpdir'
require 'fileutils'

describe RSMP::Schema do
  let(:schemas_path) { File.expand_path('../../schemas', __dir__) }

  def status_request
    {
      'mType' => 'rSMsg',
      'type' => 'StatusRequest',
      'ntsOId' => '',
      'xNId' => '',
      'cId' => 'AA+BBCCC=DDDEE002',
      'sS' => [{ 'sCI' => 'S0001', 'n' => 'signalgroupstatus' }],
      'mId' => '859e189e-c973-4b40-90c4-45a7a25f2dda'
    }
  end

  it 'validates core messages without an SXL schema' do
    version_request = {
      'mType' => 'rSMsg',
      'type' => 'Version',
      'step' => 'Request',
      'RSMP' => [{ 'vers' => '3.3.0' }],
      'siteId' => [{ 'sId' => 'RN+SI0001' }],
      'SXLS' => [],
      'mId' => '8db00f0a-4124-406f-b3f9-ceb0dbe4aeb6'
    }

    expect(subject.validate(version_request, { core: '3.3.0' })).to be_nil
  end

  it 'validates SXL messages using the matching flat SXL schema' do
    expect(subject.validate(status_request, {
                              core: '3.3.0',
                              tlc: '1.3.0'
                            })).to be_nil
  end

  it 'raises when an SXL message code matches multiple accepted SXL schemas' do
    subject.load_schema_type(:tlc_copy, File.join(schemas_path, 'tlc'), force: true)

    expect do
      subject.validate(status_request, {
                         core: '3.3.0',
                         tlc: '1.3.0',
                         tlc_copy: '1.3.0'
                       })
    end.to raise_exception(RSMP::Schema::AmbiguousMessageCodeError, message: be =~ /S0001/)
  ensure
    subject.remove_schema_type(:tlc_copy)
  end

  it 'does not use component metadata to resolve duplicate SXL message codes' do
    subject.load_schema_type(:tlc_copy, File.join(schemas_path, 'tlc'), force: true)

    expect do
      subject.resolve_sxl(status_request,
                          schemas: {
                            core: '3.3.0',
                            tlc: '1.3.0',
                            tlc_copy: '1.3.0'
                          })
    end.to raise_exception(RSMP::Schema::AmbiguousMessageCodeError, message: be =~ /S0001/)
  ensure
    subject.remove_schema_type(:tlc_copy)
  end

  it 'raises when no accepted SXL defines the message code' do
    unknown_status_request = status_request.merge(
      'sS' => [{ 'sCI' => 'S9999', 'n' => 'unknown' }]
    )

    expect do
      subject.validate(unknown_status_request, {
                         core: '3.3.0',
                         tlc: '1.3.0'
                       })
    end.to raise_exception(RSMP::Schema::UnknownMessageCodeError, message: be =~ /S9999/)
  end

  it 'resolves SXL messages with an SXL metadata prefix' do
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(File.join(schemas_path, 'tlc', '1.3.0'), File.join(dir, '1.3.0'))
      sxl_path = File.join(dir, '1.3.0', 'sxl.yaml')
      sxl_yaml = File.read(sxl_path).sub("  version: 1.3.0\n", "  version: 1.3.0\n  prefix: pre/\n")
      File.write(sxl_path, sxl_yaml)
      subject.load_schema_type(:prefixed_tlc, dir, force: true)

      prefixed_status_request = status_request.merge(
        'sS' => [{ 'sCI' => 'pre/S0001', 'n' => 'signalgroupstatus' }]
      )

      expect(subject.resolve_sxl(prefixed_status_request, schemas: {
                                   core: '3.3.0',
                                   prefixed_tlc: '1.3.0'
                                 })).to be == [:prefixed_tlc, '1.3.0']
    ensure
      subject.remove_schema_type(:prefixed_tlc)
    end
  end

  it 'requires the core schema key' do
    expect { subject.validate(status_request, { tlc: '1.3.0' }) }
      .to raise_exception(ArgumentError, message: be == 'schemas must include core')
  end

  it 'reads SXL prefix metadata from the loaded schema' do
    Dir.mktmpdir do |dir|
      schema_dir = File.join(dir, '1.0.0')
      Dir.mkdir(schema_dir)
      File.write(File.join(schema_dir, 'rsmp.json'), {
        '$schema' => 'https://json-schema.org/draft/2020-12/schema',
        'name' => 'prefixed',
        'version' => '1.0.0',
        'prefix' => 'pre/'
      }.to_json)

      subject.load_schema_type(:prefixed, dir, force: true)

      expect(subject.sxl_prefix(:prefixed, '1.0.0')).to be == 'pre/'
    ensure
      subject.remove_schema_type(:prefixed)
    end
  end

  it 'uses SXL metadata prefix in Version request items' do
    Dir.mktmpdir do |dir|
      schema_dir = File.join(dir, '1.0.0')
      Dir.mkdir(schema_dir)
      File.write(File.join(schema_dir, 'rsmp.json'), {
        '$schema' => 'https://json-schema.org/draft/2020-12/schema',
        'name' => 'prefixed',
        'version' => '1.0.0',
        'prefix' => 'pre/'
      }.to_json)
      subject.load_schema_type(:prefixed, dir, force: true)

      proxy = Class.new do
        include RSMP::Proxy::Modules::Versions
      end.new
      proxy.instance_variable_set(:@site_settings, {
                                    'sxls' => [{ 'name' => 'prefixed', 'version' => '1.0.0' }]
                                  })

      expect(proxy.sxl_request_items).to be == [
        { 'name' => 'prefixed', 'version' => '1.0.0', 'prefix' => 'pre/' }
      ]
    ensure
      subject.remove_schema_type(:prefixed)
    end
  end
end
