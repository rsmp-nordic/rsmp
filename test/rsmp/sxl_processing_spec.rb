require 'rsmp/sxl/processing'
require 'fileutils'
require 'tmpdir'

describe RSMP::SXL::Processing do
  def write_sxl(root, name:, version:, **options)
    dependencies = options.fetch(:dependencies, {})
    prefix = options[:prefix]
    components = options.fetch(:components, {})
    root_key = options.fetch(:root_key, 'components')
    path = File.join(root, name, version, 'sxl.yaml')
    FileUtils.mkdir_p(File.dirname(path))
    data = {
      'meta' => {
        'name' => name,
        'description' => "#{name} test SXL",
        'version' => version,
        'minimum_core_version' => '3.3.0'
      },
      'dependencies' => dependencies,
      root_key => components
    }
    data['prefix'] = prefix if prefix
    File.write(path, Psych.dump(data))
    path
  end

  def requirement(source)
    RSMP::SXL::Processing::VersionRequirement.new(source)
  end

  it 'implements exact, comparison, combined, and compatibility requirements' do
    expect(requirement('1.3.1').satisfied_by?('1.3.1')).to be == true
    expect(requirement('>=1.3.0 and <2.0.0').satisfied_by?('1.9.0')).to be == true
    expect(requirement('>=1.3.0 and <2.0.0').satisfied_by?('2.0.0')).to be == false
    expect(requirement('~1.3').satisfied_by?('1.9.9')).to be == true
    expect(requirement('~1.3').satisfied_by?('2.0.0')).to be == false
    expect(requirement('~0.3.1').satisfied_by?('0.3.1')).to be == true
    expect(requirement('~0.3.1').satisfied_by?('0.3.2')).to be == false
  end

  it 'requires an exact patch for major-zero compatibility requirements' do
    expect do
      requirement('~0.3')
    end.to raise_exception(
      RSMP::SXL::Processing::Error,
      message: be(:include?, 'must include an exact patch version')
    )
  end

  it 'accepts components and objects and normalizes both to components' do
    Dir.mktmpdir('rsmp-sxl-processing') do |dir|
      documents = %w[components objects].map do |root_key|
        path = write_sxl(
          dir,
          name: root_key,
          version: '1.0.0',
          root_key: root_key,
          components: { 'sign' => { 'statuses' => { 'state' => {} } } }
        )
        RSMP::SXL::Processing::Document.load(path)
      end

      documents.each do |document|
        expect(document.data).to be(:include?, 'components')
        expect(document.data).not.to be(:include?, 'objects')
        expect(document.component_types.map(&:id)).to be == ['sign']
        expect(document.message_codes.map(&:id)).to be == ['state']
      end
    end
  end

  it 'rejects documents containing both components and objects' do
    source = Psych.dump({
                          'meta' => { 'name' => 'ambiguous', 'version' => '1.0.0' },
                          'components' => {},
                          'objects' => {}
                        })

    expect do
      RSMP::SXL::Processing::Document.parse(source)
    end.to raise_exception(
      RSMP::SXL::Processing::Error,
      message: be(:include?, 'use either components or objects, not both')
    )
  end

  it 'selects the newest versions satisfying all direct and transitive requirements' do
    Dir.mktmpdir('rsmp-sxl-processing') do |dir|
      write_sxl(dir, name: 'common', version: '1.4.0')
      write_sxl(dir, name: 'common', version: '1.8.0')
      write_sxl(dir, name: 'base', version: '1.2.0', dependencies: { 'common' => '~1.0' })
      write_sxl(dir, name: 'extension', version: '1.0.0', dependencies: { 'base' => '>=1.0.0' })
      write_sxl(dir, name: 'extension', version: '1.1.0', dependencies: { 'base' => '>=1.2.0' })

      catalogue = RSMP::SXL::Processing::Catalogue.new([dir])
      roots = [['extension', requirement('~1.0')]]
      documents = RSMP::SXL::Processing::Resolver.new(catalogue).resolve(roots)

      expect(documents.to_h { |document| [document.name, document.version_string] }).to be == {
        'base' => '1.2.0',
        'common' => '1.8.0',
        'extension' => '1.1.0'
      }
    end
  end

  it 'combines requirements from multiple roots' do
    Dir.mktmpdir('rsmp-sxl-processing') do |dir|
      write_sxl(dir, name: 'shared', version: '1.4.0')
      write_sxl(dir, name: 'shared', version: '1.8.0')
      write_sxl(dir, name: 'a', version: '1.0.0', dependencies: { 'shared' => '>=1.4.0' })
      write_sxl(dir, name: 'b', version: '1.0.0', dependencies: { 'shared' => '<1.8.0' })
      catalogue = RSMP::SXL::Processing::Catalogue.new([dir])

      roots = [
        ['a', requirement('1.0.0')],
        ['b', requirement('1.0.0')]
      ]
      documents = RSMP::SXL::Processing::Resolver.new(catalogue).resolve(roots)

      expect(documents.to_h { |document| [document.name, document.version_string] }['shared']).to be == '1.4.0'
    end
  end

  it 'rejects cyclic dependencies' do
    Dir.mktmpdir('rsmp-sxl-processing') do |dir|
      write_sxl(dir, name: 'a', version: '1.0.0', dependencies: { 'b' => '1.0.0' })
      write_sxl(dir, name: 'b', version: '1.0.0', dependencies: { 'a' => '1.0.0' })
      catalogue = RSMP::SXL::Processing::Catalogue.new([dir])

      expect do
        RSMP::SXL::Processing::Resolver.new(catalogue).resolve([['a', requirement('1.0.0')]])
      end.to raise_exception(
        RSMP::SXL::Processing::Error,
        message: be(:include?, 'cyclic dependency a -> b -> a')
      )
    end
  end

  it 'applies prefixes before detecting component and message conflicts' do
    Dir.mktmpdir('rsmp-sxl-processing') do |dir|
      first = write_sxl(
        dir,
        name: 'first',
        version: '1.0.0',
        prefix: 'road/',
        components: { 'sign' => { 'statuses' => { 'state' => {} } } }
      )
      second = write_sxl(
        dir,
        name: 'second',
        version: '1.0.0',
        components: { 'road/sign' => { 'commands' => { 'road/state' => {} } } }
      )
      documents = [first, second].map { |path| RSMP::SXL::Processing::Document.load(path) }

      expect do
        RSMP::SXL::Processing::ConflictChecker.check!(documents)
      end.to raise_exception(
        RSMP::SXL::Processing::Error,
        message: be(:include?, 'Conflicting component type "road/sign"')
      )
    end
  end

  it 'creates naturally ordered manifests with deterministic metadata fields' do
    Dir.mktmpdir('rsmp-sxl-processing') do |dir|
      paths = [
        write_sxl(dir, name: 'module10', version: '1.0.0'),
        write_sxl(dir, name: 'module2', version: '1.1.0')
      ]
      documents = paths.map { |path| RSMP::SXL::Processing::Document.load(path) }
      now = Time.utc(2026, 8, 19, 12, 0, 0)

      manifest = RSMP::SXL::Processing::Manifest.create(documents, format: '3.3.0', now: now)

      expect(manifest['meta']).to be == {
        'created_at' => '2026-08-19T12:00:00Z',
        'created_by' => "rsmp v#{RSMP::VERSION}",
        'format' => '3.3.0'
      }
      expect(manifest['sxls'].keys).to be == %w[module2 module10]
    end
  end

  it 'verifies manifest dependency closure and rejects missing dependencies' do
    Dir.mktmpdir('rsmp-sxl-processing') do |dir|
      write_sxl(dir, name: 'base', version: '1.0.0')
      write_sxl(dir, name: 'extension', version: '1.0.0', dependencies: { 'base' => '~1.0' })
      catalogue = RSMP::SXL::Processing::Catalogue.new([dir])
      manifest = {
        'meta' => {
          'created_at' => '2026-08-19T12:00:00Z',
          'created_by' => 'rsmp v1.0.0',
          'format' => '3.3.0'
        },
        'sxls' => { 'extension' => '1.0.0' }
      }

      expect do
        RSMP::SXL::Processing::Manifest.verify!(manifest, catalogue)
      end.to raise_exception(
        RSMP::SXL::Processing::Error,
        message: be(:include?, 'missing dependency base')
      )
    end
  end

  it 'rejects manifests whose SXL map is not naturally ordered' do
    manifest = {
      'meta' => {
        'created_at' => '2026-08-19T12:00:00Z',
        'created_by' => 'rsmp v1.0.0',
        'format' => '3.3.0'
      },
      'sxls' => { 'module10' => '1.0.0', 'module2' => '1.0.0' }
    }

    expect do
      RSMP::SXL::Processing::Manifest.verify!(manifest, RSMP::SXL::Processing::Catalogue.new)
    end.to raise_exception(
      RSMP::SXL::Processing::Error,
      message: be(:include?, 'not in natural name order')
    )
  end
end
