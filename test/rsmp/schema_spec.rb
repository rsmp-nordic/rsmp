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

  it 'resolves SXL definitions using the negotiated core version' do
    Dir.mktmpdir do |dir|
      write_dynamic_defs_sxl(File.join(dir, '1.0.0'))
      subject.load_schema_type(:dynamic_defs, dir, force: true)

      expect(subject.validate(dynamic_defs_status_response('clean'), {
                                core: '3.2.2',
                                dynamic_defs: '1.0.0'
                              })).to be_nil
      expect(subject.validate(dynamic_defs_status_response('clean'), {
                                core: '3.3.0',
                                dynamic_defs: '1.0.0'
                              })).to be_nil

      expect(subject.validate(dynamic_defs_status_response("bad\u0001"), {
                                core: '3.2.2',
                                dynamic_defs: '1.0.0'
                              })).to be_nil
      expect(subject.validate(dynamic_defs_status_response("bad\u0001"), {
                                core: '3.3.0',
                                dynamic_defs: '1.0.0'
                              })).not.to be_nil
    ensure
      subject.remove_schema_type(:dynamic_defs)
    end
  end

  it 'caches core-aware SXL schemas per negotiated core version' do
    Dir.mktmpdir do |dir|
      write_dynamic_defs_sxl(File.join(dir, '1.0.0'))
      subject.load_schema_type(:dynamic_cache, dir, force: true)

      subject.validate(dynamic_defs_status_response('clean'), {
                         core: '3.2.2',
                         dynamic_cache: '1.0.0'
                       })
      subject.validate(dynamic_defs_status_response('clean'), {
                         core: '3.3.0',
                         dynamic_cache: '1.0.0'
                       })

      cache = subject.instance_variable_get(:@core_sxl_schemas)
      expect(cache.keys).to be(:include?, [:dynamic_cache, '1.0.0', '3.2.2'])
      expect(cache.keys).to be(:include?, [:dynamic_cache, '1.0.0', '3.3.0'])
      expect(cache[[:dynamic_cache, '1.0.0', '3.2.2']])
        .not.to be == cache[[:dynamic_cache, '1.0.0', '3.3.0']]
    ensure
      subject.remove_schema_type(:dynamic_cache)
    end
  end

  it 'keeps generated SXL schemas usable with their fallback definitions' do
    Dir.mktmpdir do |dir|
      schema_dir = File.join(dir, '1.0.0')
      write_dynamic_defs_sxl(schema_dir)

      schemer = JSONSchemer.schema(Pathname.new(File.join(schema_dir, 'rsmp.json')))
      expect(schemer.valid?(dynamic_defs_status_response("bad\u0001"))).to be == true
    end
  end

  it 'raises a clear error when negotiated core definitions are missing' do
    Dir.mktmpdir do |dir|
      write_dynamic_defs_sxl(File.join(dir, '1.0.0'))
      subject.load_schema_type(:missing_core_defs, dir, force: true)

      expect do
        subject.validate(dynamic_defs_status_response('clean'), {
                           core: '9.9.9',
                           missing_core_defs: '1.0.0'
                         })
      end.to raise_exception(RSMP::Schema::UnknownSchemaVersionError, message: be =~ /core/)
    ensure
      subject.remove_schema_type(:missing_core_defs)
    end
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
      rsmp_path = File.join(dir, '1.3.0', 'rsmp.json')
      rsmp_json = JSON.parse(File.read(rsmp_path, encoding: 'UTF-8')).merge('prefix' => 'pre/')
      File.write(rsmp_path, JSON.pretty_generate(rsmp_json))
      index_path = File.join(dir, '1.3.0', 'sxl_index.json')
      if File.exist?(index_path)
        index = JSON.parse(File.read(index_path, encoding: 'UTF-8'))
        index['meta'] = index.fetch('meta', {}).merge('prefix' => 'pre/')
        File.write(index_path, JSON.pretty_generate(index))
      end
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
      write_sxl_index(schema_dir, meta: {
                        'name' => 'prefixed',
                        'version' => '1.0.0',
                        'prefix' => 'pre/'
                      })

      subject.load_schema_type(:prefixed, dir, force: true)

      expect(subject.sxl_prefix(:prefixed, '1.0.0')).to be == 'pre/'
    ensure
      subject.remove_schema_type(:prefixed)
    end
  end

  it 'reads SXL catalogues from the generated JSON index' do
    Dir.mktmpdir do |dir|
      schema_dir = File.join(dir, '1.0.0')
      Dir.mkdir(schema_dir)
      File.write(File.join(schema_dir, 'rsmp.json'), {
        '$schema' => 'https://json-schema.org/draft/2020-12/schema',
        'name' => 'cached',
        'version' => '1.0.0'
      }.to_json)
      write_sxl_index(schema_dir,
                      meta: {
                        'name' => 'cached',
                        'version' => '1.0.0'
                      },
                      statuses: {
                        'S0001' => {
                          'required' => %w[signalgroupstatus]
                        }
                      })

      subject.load_schema_type(:cached, dir, force: true)
      expect(subject.status_catalogue(:cached, '1.0.0')).to be == {
        S0001: [:signalgroupstatus]
      }
    ensure
      subject.remove_schema_type(:cached)
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
      write_sxl_index(schema_dir, meta: {
                        'name' => 'prefixed',
                        'version' => '1.0.0',
                        'prefix' => 'pre/'
                      })
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

  def write_sxl_index(schema_dir, meta:, statuses: {}, commands: {}, alarms: {})
    File.write(File.join(schema_dir, 'sxl_index.json'), {
      'meta' => meta,
      'statuses' => statuses,
      'commands' => commands,
      'alarms' => alarms
    }.to_json)
  end

  def dynamic_defs_status_response(value)
    {
      'mType' => 'rSMsg',
      'type' => 'StatusResponse',
      'cId' => 'AA+BBCCC=DDDEE002',
      'sTs' => '2015-06-08T11:49:03.293Z',
      'sS' => [{ 'sCI' => 'S0001', 'n' => 'text', 's' => value, 'q' => 'recent' }],
      'mId' => '859e189e-c973-4b40-90c4-45a7a25f2dda'
    }
  end

  def write_dynamic_defs_sxl(schema_dir)
    FileUtils.mkdir_p(File.join(schema_dir, 'statuses'))
    FileUtils.mkdir_p(File.join(schema_dir, 'defs'))
    write_dynamic_root_schema(schema_dir)
    write_dynamic_statuses_schema(schema_dir)
    write_dynamic_status_schema(schema_dir)
    FileUtils.cp(File.join(schemas_path, 'core', '3.2.2', 'definitions.json'),
                 File.join(schema_dir, 'defs', 'definitions.json'))
    write_sxl_index(schema_dir,
                    meta: {
                      'name' => 'dynamic_defs',
                      'version' => '1.0.0'
                    },
                    statuses: {
                      'S0001' => {
                        'required' => ['text']
                      }
                    })
  end

  def write_dynamic_root_schema(schema_dir)
    File.write(File.join(schema_dir, 'rsmp.json'), {
      '$schema' => 'https://json-schema.org/draft/2020-12/schema',
      'name' => 'dynamic_defs',
      'version' => '1.0.0',
      'allOf' => [
        {
          'if' => {
            'required' => ['type'],
            'properties' => { 'type' => { 'const' => 'StatusResponse' } }
          },
          'then' => { '$ref' => 'statuses/statuses.json' }
        }
      ]
    }.to_json)
  end

  def write_dynamic_statuses_schema(schema_dir)
    File.write(File.join(schema_dir, 'statuses', 'statuses.json'), {
      '$schema' => 'https://json-schema.org/draft/2020-12/schema',
      'properties' => {
        'sS' => {
          'items' => {
            'allOf' => [
              { 'properties' => { 'sCI' => { 'enum' => ['S0001'] } } },
              {
                'if' => {
                  'required' => ['sCI'],
                  'properties' => { 'sCI' => { 'const' => 'S0001' } }
                },
                'then' => { '$ref' => 'S0001.json' }
              }
            ]
          }
        }
      }
    }.to_json)
  end

  def write_dynamic_status_schema(schema_dir)
    File.write(File.join(schema_dir, 'statuses', 'S0001.json'), {
      '$schema' => 'https://json-schema.org/draft/2020-12/schema',
      'properties' => {
        'n' => { 'const' => 'text' },
        's' => { '$ref' => '../defs/definitions.json#/string_list' }
      }
    }.to_json)
  end
end
