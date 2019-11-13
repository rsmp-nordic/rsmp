# Things shared between sites and site proxies

module RSMP
  module SiteBase
    attr_reader :components
    
    def initialize_site
      @components = {}
    end

    def aggrated_status_changed component
    end

    def setup_components settings
      return unless settings
      settings.each_pair do |id,settings|
        @components[id] = build_component(id,settings)
      end
    end

    def add_component component
      @components[component.c_id] = component
    end

    def build_component id, settings={}
      Component.new id: id, node: self, grouped: true
    end

  end
end