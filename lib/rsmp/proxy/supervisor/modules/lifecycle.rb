module RSMP
  class SupervisorProxy < Proxy
    module Modules
      # Connection lifecycle helpers for supervisor-side proxies.
      module Lifecycle
        def start_handshake
          send_version_request @site_settings['site_id'], core_versions
        end

        def close
          prune_unbuffered_status_subscriptions
          super
        end
      end
    end
  end
end
