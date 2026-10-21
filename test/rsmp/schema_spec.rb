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

  RSMP::Schema.core_versions.each do |core_version|
    with "Core #{core_version} subscription intervals" do
      let(:subscription) do
        arg = { 'sCI' => 'S0001', 'n' => 'signalgroupstatus', 'uRt' => '1' }
        arg['sOc'] = true if Gem::Version.new(core_version) >= Gem::Version.new('3.1.5')
        RSMP::StatusSubscribe.new('cId' => 'KK+AG4034=00DL001', 'ntsOId' => '', 'xNId' => '', 'sS' => [arg])
      end

      it 'accepts integer and fractional intervals, including zero for change-only subscriptions' do
        %w[0 0.0 1 0.5 2.5 0.001].each do |interval|
          subscription.attributes['sS'].first['uRt'] = interval
          expect(subscription.validate(core: core_version, tlc: '1.3.0').valid?).to be == true
        end
      end

      it 'rejects malformed intervals and JSON numbers' do
        ['NaN', 'Infinity', '0.5s', '0,5', '', 1, 0.5, nil].each do |interval|
          subscription.attributes['sS'].first['uRt'] = interval
          expect(subscription.validate(core: core_version, tlc: '1.3.0').invalid?).to be == true
        end
      end
    end
  end

  with 'Core 3.3 component identifiers and selectors' do
    let(:definitions) { JSON.parse(File.read(File.join(schemas_path, 'core', '3.3.0', 'definitions.json'))) }
    let(:id_schema) { JSONSchemer.schema(definitions.merge('$ref' => '#/component_id')) }
    let(:selector_schema) { JSONSchemer.schema(definitions.merge('$ref' => '#/component_id_selector')) }

    it 'accepts hierarchical and classic identifiers with the same grammar' do
      %w[sg/1 dl/north/radar/6 tc KK+AG4034=00DL001 sensor_A-2].each do |id|
        expect(id_schema.valid?(id)).to be == true
        expect(selector_schema.valid?(id)).to be == true
      end
    end

    it 'reserves subtree, root and no-component forms for selectors' do
      ['sg/', 'dl/north/', '/', '', nil].each do |selector|
        expect(id_schema.valid?(selector)).to be == false
        expect(selector_schema.valid?(selector)).to be == true
      end
    end

    it 'rejects leading slashes, empty segments, invalid characters and non-string IDs' do
      ['/sg/1', '/sg/', '//', 'sg//1', 'sg//', 'sg 1', 'sg.1', 'sg:1', "sg/1\n", "sg\t1", 1, true, [], {}].each do |id|
        expect(id_schema.valid?(id)).to be == false
        expect(selector_schema.valid?(id)).to be == false
      end
    end

    it 'keeps the earlier Core component ID definition unchanged' do
      old_definitions = JSON.parse(File.read(File.join(schemas_path, 'core', '3.2.2', 'definitions.json')))
      old_schema = JSONSchemer.schema(old_definitions.merge('$ref' => '#/component_id'))
      expect(old_schema.valid?('/sg/1')).to be == true
      expect(old_schema.valid?('')).to be == true
    end

    it 'requires single component IDs in messages until selector use is defined' do
      schema = JSONSchemer.schema(Pathname.new(File.join(schemas_path, 'core', '3.3.0', 'rsmp.json')))
      status = { 'sCI' => 'S0001', 'n' => 'signalgroupstatus' }
      command = { 'cCI' => 'M0001', 'n' => 'value', 'v' => '1' }
      timestamp = '2026-10-02T12:00:00.000Z'
      payloads = {
        'StatusRequest' => { 'sS' => [status] },
        'StatusUnsubscribe' => { 'sS' => [status] },
        'StatusSubscribe' => { 'sS' => [status.merge('uRt' => '1', 'sOc' => true)] },
        'StatusResponse' => { 'sTs' => timestamp, 'sS' => [status.merge('s' => 'R', 'q' => 'recent')] },
        'StatusUpdate' => { 'sTs' => timestamp, 'sS' => [status.merge('s' => 'R', 'q' => 'recent')] },
        'CommandRequest' => { 'arg' => [command.merge('cO' => 'set')] },
        'CommandResponse' => { 'cTS' => timestamp, 'rvs' => [command.merge('age' => 'recent')] },
        'Alarm' => { 'aSp' => 'Request', 'aCId' => 'A0001', 'xACId' => '' }
      }
      payloads.each do |type, payload|
        message = payload.merge('mType' => 'rSMsg', 'type' => type, 'mId' => RSMP::Message.make_m_id)
        %w[sg/1 KK+AG4034=00DL001].each do |id|
          expect(schema.valid?(message.merge('cId' => id))).to be == true
        end
        ['sg/', '/', '', nil, '/sg/1', 'sg//1', 'sg 1'].each do |selector|
          expect(schema.valid?(message.merge('cId' => selector))).to be == false
        end
        expect(schema.valid?(message)).to be == false
      end
    end

    it 'rejects selectors as ComponentList IDs and forbids cId on aggregated status messages' do
      entry = { 'id' => 'sg/1', 'type' => 'tlc/sg', 'name' => 'Signal group' }
      list = RSMP::ComponentList.new('components' => [entry])
      expect(list.validate(core: '3.3.0').valid?).to be == true
      ['sg/', '/', '', nil].each do |selector|
        entry['id'] = selector
        expect(list.validate(core: '3.3.0').invalid?).to be == true
      end
      aggregate = RSMP::AggregatedStatus.new('aSTS' => RSMP::Clock.to_s, 'se' => Array.new(8, false))
      [aggregate, RSMP::AggregatedStatusRequest.new].each do |message|
        expect(message.validate(core: '3.3.0').valid?).to be == true
        ['sg/1', 'sg/', '/', '', nil].each do |selector|
          message.attributes['cId'] = selector
          expect(message.validate(core: '3.3.0').invalid?).to be == true
        end
      end
    end
  end

  with 'version formats' do
    it 'normalizes only unambiguous legacy Core versions' do
      expect(subject.normalize_core_version('3.2')).to be == '3.2.0'
      subject.core_versions.each do |version|
        expect(subject.normalize_core_version(version)).to be == version
      end
      expect(subject.normalize_core_version('3.1')).to be_nil
      expect(subject.normalize_core_version('3.2.0-preview')).to be_nil
      expect(subject.normalize_core_version('9.9.9')).to be_nil
    end

    it 'requires three-part Core versions from 3.3' do
      expect(subject.normalize_core_version('3.3.0')).to be == '3.3.0'
      expect(subject.normalize_core_version('3.3')).to be_nil
    end

    it 'recognizes strict numeric three-part versions' do
      expect(subject.strict_version?('3.3.0')).to be == true
      expect(subject.strict_version?('1.2.0')).to be == true
      expect(subject.strict_version?('1.2')).to be == false
      expect(subject.strict_version?('01.2.0')).to be == false
      expect(subject.strict_version?('1.2.0-preview')).to be == false
      expect(subject.strict_version?('1.2.0+build')).to be == false
    end

    it 'continues accepting two-part SXL versions for legacy Core connections' do
      expect(subject.sanitize_version('1.1')).to be == '1.1.0'
      expect(subject.sanitize_version('1.2')).to be == '1.2.0'
      expect(subject.find_schema(:tlc, '1.1', lenient: true)).not.to be_nil
      expect(subject.find_schema(:tlc, '1.2', lenient: true)).not.to be_nil
    end
  end

  it 'validates core messages without an SXL schema' do
    version_request = {
      'mType' => 'rSMsg',
      'type' => 'Version',
      'step' => 'Request',
      'RSMP' => [{ 'vers' => '3.3.0' }],
      'siteId' => [{ 'sId' => 'RN+SI0001' }],
      'SXL' => '',
      'SXLS' => [],
      'mId' => '8db00f0a-4124-406f-b3f9-ceb0dbe4aeb6'
    }

    expect(subject.validate(version_request, { core: '3.3.0' }).valid?).to be == true
  end

  %w[3.1.2 3.1.3 3.1.4 3.1.5 3.2.0 3.2.1 3.2.2].each do |version|
    it "accepts fractional status update intervals with Core #{version}" do
      message = status_request.merge('type' => 'StatusSubscribe')
      message['sS'].first['uRt'] = '0.1'
      message['sS'].first['sOc'] = false if Gem::Version.new(version) >= Gem::Version.new('3.1.5')

      expect(subject.validate(message, { core: version }).valid?).to be == true
    end
  end

  it 'validates SXL messages using the matching flat SXL schema' do
    validation = subject.validate(status_request, {
                                    core: '3.3.0',
                                    tlc: '1.3.0'
                                  })
    expect(validation.valid?).to be == true
  end

  it 'resolves SXL definitions using the negotiated core version' do
    Dir.mktmpdir do |dir|
      write_dynamic_defs_sxl(File.join(dir, '1.0.0'))
      subject.load_schema_type(:dynamic_defs, dir, force: true)

      expect(subject.validate(dynamic_defs_status_response('clean'), {
                                core: '3.2.2',
                                dynamic_defs: '1.0.0'
                              }).valid?).to be == true
      expect(subject.validate(dynamic_defs_status_response('clean'), {
                                core: '3.3.0',
                                dynamic_defs: '1.0.0'
                              }).valid?).to be == true

      expect(subject.validate(dynamic_defs_status_response("bad\u0001"), {
                                core: '3.2.2',
                                dynamic_defs: '1.0.0'
                              }).valid?).to be == true
      expect(subject.validate(dynamic_defs_status_response("bad\u0001"), {
                                core: '3.3.0',
                                dynamic_defs: '1.0.0'
                              }).invalid?).to be == true
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

  it 'returns invalid when no accepted SXL defines the message code' do
    unknown_status_request = status_request.merge(
      'sS' => [{ 'sCI' => 'S9999', 'n' => 'unknown' }]
    )

    validation = subject.validate(unknown_status_request, {
                                    core: '3.3.0',
                                    tlc: '1.3.0'
                                  })

    expect(validation.invalid?).to be == true
    expect(validation.message).to be =~ /S9999/
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
                          'required' => {
                            'signalgroupstatus' => 'string'
                          }
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

  it 'uses canonical SXL versions in 3.3 request items while preserving the legacy field' do
    proxy = Class.new do
      include RSMP::Proxy::Modules::Versions
    end.new
    proxy.instance_variable_set(:@site_settings, {
                                  'sxls' => [{ 'name' => 'tlc', 'version' => '1.2' }]
                                })

    expect(proxy.sxl_request_items).to be == [{ 'name' => 'tlc', 'version' => '1.2.0' }]
    expect(proxy.version_message_attributes('RN+SI0001', ['3.2'])).to be == {
      'RSMP' => [{ 'vers' => '3.2' }],
      'siteId' => [{ 'sId' => 'RN+SI0001' }],
      'SXL' => '1.2'
    }
  end

  it 'advertises both spellings of the historical Core 3.2 release' do
    proxy = Class.new do
      include RSMP::Proxy::Modules::Versions
    end.new
    proxy.instance_variable_set(:@site_settings, {
                                  'core_version' => '3.2',
                                  'sxls' => []
                                })

    expect(proxy.core_versions).to be == ['3.2.0']
    expect(proxy.advertised_core_versions).to be == ['3.2', '3.2.0']
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
                        'required' => {
                          'text' => 'string'
                        }
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

  with 'Core 3.3.0 message validation' do
    let(:core_version) { '3.3.0' }

    it 'allows omitted component names but rejects empty and non-string names' do
      item = { 'id' => 'g/1', 'type' => 'sg' }
      list = RSMP::ComponentList.new('components' => [item])
      expect(list.validate(core: core_version).valid?).to be == true
      item['name'] = 'Signal group 1'
      expect(list.validate(core: core_version).valid?).to be == true
      ['', nil, 42].each do |name|
        item['name'] = name
        expect(list.validate(core: core_version).invalid?).to be == true
      end
    end

    it 'validates nonnegative numeric subscription strings and the change-only zero exception' do
      request = RSMP::StatusSubscribe.new('cId' => 'a', 'sS' => [
                                            { 'sCI' => 'S0001', 'n' => 'signalgroupstatus', 'uRt' => '2', 'sOc' => false }
                                          ])
      arg = request.attributes['sS'].first
      %w[2 2.5 0.5 0.001].each do |rate|
        [false, true].each do |on_change|
          arg.merge!('uRt' => rate, 'sOc' => on_change)
          expect(request.validate(core: core_version, tlc: '1.3.0').valid?).to be == true
        end
      end
      %w[0 0.0 0.00].each do |rate|
        arg.merge!('uRt' => rate, 'sOc' => true)
        expect(request.validate(core: core_version, tlc: '1.3.0').valid?).to be == true
        arg['sOc'] = false
        expect(request.validate(core: core_version, tlc: '1.3.0').invalid?).to be == true
      end
      ['-1', '-0.5', 'NaN', 'Infinity', '2.5s', '2,5', '', 2, 2.5, nil].each do |rate|
        arg.merge!('uRt' => rate, 'sOc' => true)
        expect(request.validate(core: core_version, tlc: '1.3.0').invalid?).to be == true
      end
    end

    it 'rejects component-addressed aggregated-status fields and reserved site bits' do
      status = RSMP::AggregatedStatus.new('aSTS' => RSMP::Clock.to_s, 'se' => Array.new(8, false))
      expect(status.validate(core: core_version).valid?).to be == true
      %w[cId fP fS].each do |key|
        bad = RSMP::AggregatedStatus.new(status.attributes.merge(key => nil))
        expect(bad.validate(core: core_version).invalid?).to be == true
      end
      [1, 5, 7].each do |index|
        bits = Array.new(8, false)
        bits[index] = true
        bad = RSMP::AggregatedStatus.new(status.attributes.merge('se' => bits))
        expect(bad.validate(core: core_version).invalid?).to be == true
      end
    end
  end
end
