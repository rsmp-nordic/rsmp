module RSMP
  module SXL
    module Registry
      @interfaces = {}

      def self.register(name, side, klass)
        @interfaces[[name.to_s, side.to_sym]] = klass
      end

      def self.register_interface(klass)
        register sxl_name_for(klass), side_for(klass), klass
      end

      def self.fetch(name, side)
        @interfaces[[name.to_s, side.to_sym]]
      end

      def self.build(proxy, sxl, side)
        klass = fetch(sxl['name'], side) || default_class(side)
        klass.new(proxy: proxy, name: sxl['name'], version: sxl['version'])
      end

      def self.build_for(proxy, sxl)
        case proxy
        when RSMP::SiteProxy
          build(proxy, sxl, :supervisor)
        when RSMP::SupervisorProxy
          build(proxy, sxl, :site)
        else
          raise ArgumentError, "Unknown proxy class #{proxy.class}"
        end
      end

      def self.default_class(side)
        side.to_sym == :site ? SiteInterface : SupervisorInterface
      end

      def self.side_for(klass)
        return :site if klass < SiteInterface
        return :supervisor if klass < SupervisorInterface

        raise ArgumentError, "Cannot infer SXL interface side for #{klass}"
      end

      def self.sxl_name_for(klass)
        namespace = klass.name.split('::')[0...-1].join('::')
        owner = Object.const_get(namespace)
        return owner.sxl_name if owner.respond_to?(:sxl_name)

        raise ArgumentError, "Cannot infer SXL name for #{klass}"
      end
    end
  end
end
