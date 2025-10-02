# frozen_string_literal: true

module RSMP
  class Supervisor < Node
    module Modules
      # Manages connected sites and site discovery
      module Sites
        def site_connected?(site_id)
          !find_site(site_id).nil?
        end

        def find_site_from_ip_port(ip, port)
          @proxies.each do |site|
            return site if site.ip == ip && site.port == port
          end
          nil
        end

        def find_site(site_id)
          @proxies.each do |site|
            return site if site_id == :any || site.site_id == site_id
          end
          nil
        end

        def wait_for_site(site_id, timeout:)
          site = find_site site_id
          return site if site

          wait_for_condition(@site_id_condition, timeout: timeout) do
            find_site site_id
          end
        rescue Async::TimeoutError
          str = if site_id == :any
                  'No site connected'
                else
                  "Site '#{site_id}' did not connect"
                end
          raise RSMP::TimeoutError, "#{str} within #{timeout}s"
        end

        def wait_for_site_disconnect(site_id, timeout:)
          wait_for_condition(@site_id_condition, timeout: timeout) { true unless find_site site_id }
        rescue Async::TimeoutError
          raise RSMP::TimeoutError, "Site '#{site_id}' did not disconnect within #{timeout}s"
        end

        def check_site_id(site_id)
          # check_site_already_connected site_id
          site_id_to_site_setting site_id
        end

        def check_site_already_connected(site_id)
          site = find_site(site_id)
          raise HandshakeError, "Site '#{site_id}' already connected" if !site.nil? && site != self
        end

        def site_ids_changed
          @site_id_condition.signal
        end

        def aggregated_status_changed(site_proxy, component); end
      end
    end
  end
end
