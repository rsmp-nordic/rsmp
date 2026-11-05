module RSMP
  # Selects the SXL versions accepted by a supervisor-side site proxy.
  module SiteSxlSelection
    def check_sxl_version(message)
      if core_3_3_0_or_newer?
        select_sxls message
      else
        select_legacy_sxl message
      end
      build_sxl_interfaces
    rescue RSMP::Schema::UnknownSchemaError => e
      dont_acknowledge message, "Rejected #{message.type} message,", e.to_s
    end

    def select_legacy_sxl(message)
      primary = configured_sxls.first
      raise HandshakeError, 'Legacy Version message received, but no SXL is configured' unless primary

      sanitized_version = RSMP::Schema.sanitize_version(message.attribute('SXL'))
      versions = primary['versions'] || [primary['version']]
      unless versions.include?(sanitized_version)
        raise HandshakeError,
              "SXL #{primary['name']} version #{message.attribute('SXL')} requested, " \
              "but only #{versions.join(', ')} supported; hint: #{versions.first}"
      end
      RSMP::Schema.find_schema! primary['name'], sanitized_version
      @accepted_sxls = [{ 'name' => primary['name'], 'version' => message.attribute('SXL') }]
      @rejected_sxls = []
    end

    def select_sxls(message)
      selected = message.sxls.map { |requested| select_sxl(requested) }
      offered = message.sxls.map { |item| item['name'] }
      configured_sxls.each do |item|
        selected << { 'name' => item['name'], 'status' => 'expected' } unless offered.include?(item['name'])
      end
      @accepted_sxls, @rejected_sxls = selected.partition { |item| item['status'] == 'ok' }
    end

    def select_sxl(requested)
      configured = configured_sxls.find { |item| item['name'] == requested['name'] }
      return { 'name' => requested['name'], 'status' => 'unsupported' } unless configured

      versions = configured['versions'] || [configured['version']]
      version = requested['version']
      if versions.include?(version)
        RSMP::Schema.find_schema! requested['name'], version
        { 'name' => requested['name'], 'status' => 'ok', 'version' => version }
      else
        { 'name' => requested['name'], 'status' => 'mismatch',
          'supported' => versions.sort_by { |item| Gem::Version.new(item) } }
      end
    end
  end
end
