module RSMP
  module ProxyExtensions
    module Utilities
      def log(str, options = {})
        super(str, options.merge(ip: @ip, port: @port, site_id: @site_id))
      end

      def schemas
        schemas = { core: RSMP::Schema.latest_core_version } # use latest core
        schemas[:core] = core_version if core_version
        schemas[sxl] = RSMP::Schema.sanitize_version(sxl_version.to_s) if sxl && sxl_version
        schemas
      end

      def author
        @node.site_id
      end
    end
  end
end
