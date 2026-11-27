module RSMP
  class SupervisorProxy < Proxy
    module Modules
      # Connection lifecycle helpers for supervisor-side proxies.
      module Lifecycle
        def close(...)
          prune_unbuffered_status_subscriptions
          super
        end
      end
    end
  end
end
