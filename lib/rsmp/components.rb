# Things shared between sites and site proxies

module RSMP
  module Components
    attr_reader :components, :main

    def initialize_components
      @components = {}
      @main = nil
    end

    def aggregated_status_changed component, options={}
    end

    def setup_components settings
      return unless settings
      check_main_component settings
      settings.each_pair do |type,components_by_type|
        if components_by_type
          components_by_type.each_pair do |id,component_settings|
            @components[id] = build_component(id:id, type:type, settings:component_settings)
            @main = @components[id] if type=='main'
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
        class_name << " component" unless (class_name == 'Component' || class_name == 'ComponentProxy')
        log "Adding component #{component_id} with the inferred type #{class_name}", level: :debug
        component
      else
        raise UnknownComponent.new("Component #{component_id} not found") unless component
      end
    end

  end
end