require 'rake'
require 'tmpdir'

load File.expand_path('../../Rakefile', __dir__)

describe 'schemas:update' do
  it 'requires a minimum core version in vendored TLC sources' do
    Dir.mktmpdir do |dir|
      source_path = File.join(dir, 'sxl.yaml')
      File.write(source_path, <<~YAML)
        meta:
          name: tlc
        objects: {}
      YAML

      expect do
        require_minimum_core_version!(source_path)
      end.to raise_exception(RuntimeError, message: be(:include?, 'Missing meta.minimum_core_version'))
    end
  end
end
