module RSMP
  # Selects the SXL versions accepted by a supervisor-side site proxy.
  module SiteSxlSelection
    def check_sxl_version(message)
      if core_3_3_0_or_newer?
        select_sxls message
      else
        select_legacy_sxl message
      end
    rescue RSMP::Schema::UnknownSchemaError => e
      dont_acknowledge message, "Rejected #{message.type} message,", e.to_s
    end

    def select_legacy_sxl(message)
      primary = configured_sxls.first
      unless primary
        reason = 'Legacy Version message received, but no SXL is configured'
        dont_acknowledge message, "Rejected #{message.type} message,", reason
        raise HandshakeError, reason
      end

      sanitized_version = RSMP::Schema.sanitize_version(message.attribute('SXL'))
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

      version = RSMP::Schema.sanitize_version(configured['version'].to_s)
      if version == requested['version']
        RSMP::Schema.find_schema! requested['name'], version
        { 'name' => requested['name'], 'status' => 'ok', 'version' => version }
      else
        { 'name' => requested['name'], 'status' => 'mismatch', 'supported' => [version] }
      end
    end
  end
end
