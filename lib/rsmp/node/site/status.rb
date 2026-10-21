module RSMP
  # Site-wide status and component change notifications for Core 3.3.
  module SiteStatus
    def aggregated_status_changed(component, _options = {})
      @proxies.each do |proxy|
        if proxy.core_3_3_0_or_newer?
          proxy.send_changed_site_status
        else
          proxy.send_aggregated_status component
        end
      end
    end

    def site_wide_aggregated_status?
      @site_settings['core_version'] == '3.3.0' || @proxies&.any?(&:core_3_3_0_or_newer?)
    end

    # Core 3.3 status includes every SXL, independently of connection negotiation.
    def site_aggregated_status
      bits = Array.new(8, false)
      @components.each_value do |component|
        [0, 2, 3, 4, 6].each { |index| bits[index] ||= component.aggregated_status_bools[index] }
        component.alarms.each_value do |alarm|
          bits[alarm.priority + 1] = true if alarm.active && (1..3).cover?(alarm.priority)
        end
      end
      bits
    end

    def notify_site_status_change
      @proxies.each { |proxy| proxy.send_changed_site_status if proxy.core_3_3_0_or_newer? }
    end

    def component_list_changed
      @proxies&.each { |proxy| proxy.send_component_list if proxy.core_3_3_0_or_newer? && proxy.ready? }
      notify_site_status_change if @proxies
    end
  end
end
