module RSMP
  # Selects the SXL versions accepted by a supervisor-side site proxy.
  module SiteSxlSelection
    def check_sxl_version(message)
      if core_3_3?
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
      selected_sxls = message.sxls.map { |requested| select_sxl(requested) }
      @accepted_sxls, @rejected_sxls = selected_sxls.partition { |item| item['rejected'].nil? }
    end

    def select_sxl(requested)
      configured = configured_sxls.find { |item| item['name'] == requested['name'] }
      return rejected_sxl(requested, 1, 'SXL not supported') unless configured

      if configured['version'].to_s == requested['version'].to_s
        RSMP::Schema.find_schema! requested['name'], requested['version'], lenient: true
        requested.slice('name', 'version', 'prefix')
      else
        rejected_sxl(requested, 2, "Supervisor only supports #{configured['version']}")
      end
    end

    def rejected_sxl(requested, code, reason)
      {
        'name' => requested['name'],
        'version' => requested['version'],
        'rejected' => code,
        'reason' => reason
      }.compact
    end
  end
end
