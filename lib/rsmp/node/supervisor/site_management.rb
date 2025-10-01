module RSMP
  module SupervisorExtensions
    module SiteManagement
      def build_proxy(settings)
        SiteProxy.new settings
      end

      def format_ip_and_port(info)
        return '********' if @logger.settings['hide_ip_and_port']

        "#{info[:ip]}:#{info[:port]}"
      end

      def site_ids_changed
        @site_id_condition.signal
      end

      def site_connected?(site_id)
        !find_site(site_id).nil?
      end

      def find_site_from_ip_port(ip, port)
        @proxies.find { |site| site.ip == ip && site.port == port }
      end

      def find_site(site_id)
        @proxies.find { |site| site_id == :any || site.site_id == site_id }
      end

      def wait_for_site(site_id, timeout:)
        site = find_site site_id
        return site if site

        wait_for_condition(@site_id_condition, timeout: timeout) { find_site site_id }
      rescue Async::TimeoutError
        str = site_id == :any ? 'No site connected' : "Site '#{site_id}' did not connect"
        raise RSMP::TimeoutError, "#{str} within #{timeout}s"
      end

      def wait_for_site_disconnect(site_id, timeout:)
        wait_for_condition(@site_id_condition, timeout: timeout) { !find_site(site_id) }
      rescue Async::TimeoutError
        raise RSMP::TimeoutError, "Site '#{site_id}' did not disconnect within #{timeout}s"
      end

      def check_site_id(site_id)
        site_id_to_site_setting site_id
      end

      def check_site_already_connected(site_id)
        site = find_site(site_id)
        raise HandshakeError, "Site '#{site_id}' already connected" if !site.nil? && site != self
      end

      def site_id_to_site_setting(site_id)
        return {} unless @supervisor_settings['sites']

        @supervisor_settings['sites'].each_pair do |id, settings|
          return settings if id == 'guest' || id == site_id
        end
        raise HandshakeError, "site id #{site_id} unknown"
      end

      def ip_to_site_settings(ip)
        @supervisor_settings['sites'][ip] || @supervisor_settings['sites']['guest']
      end

      def aggregated_status_changed(_site_proxy, _component); end

      private

      def register_proxy(proxy)
        @proxies << proxy
        proxy
      end
    end
  end
end
