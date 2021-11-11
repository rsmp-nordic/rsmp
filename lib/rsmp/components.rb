# Things shared between sites and site proxies

module RSMP
  module Components
    attr_reader :components
    
    def initialize_components
      @components = {}
    end

    def aggregated_status_changed component, options={}
    end

    def setup_components settings
      return unless settings
      check_main_component settings
      settings.each_pair do |type,components_by_type|
        if components_by_type
          components_by_type.each_pair do |id,settings|
            @components[id] = build_component(id:id, type:type, settings:settings)
          end
        end
      end
    end

    def check_main_component settings
      unless settings['main'] && settings['main'].size >= 1
        raise ConfigurationError.new("main component must be defined") 
      end
      if settings['main'].size > 1
        raise ConfigurationError.new("only one main component can be defined, found #{settings['main'].keys.join(', ')}") 
      end
    end

    def add_component component
      @components[component.c_id] = component
    end

    def build_component id:, type:, settings:{}
      Component.new id:id, node: self, grouped: type=='main'
    end

    def infer_component_type component_id
      Component
    end

    def find_component component_id, build: true
      component = @components[component_id]
      return component if component
      if build
        inferred = infer_component_type component_id
        component = inferred.new node: self, id: component_id
        @components[ component_id] = component
        class_name = component.class.name.split('::').last
        log "Inferred #{class_name} component #{component_id}", level: :info
        component
      else
        raise UnknownComponent.new("Component #{component_id} not found") unless component
      end
    end

  end
end