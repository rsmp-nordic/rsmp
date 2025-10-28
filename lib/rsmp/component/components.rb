# Things shared between sites and site proxies

module RSMP
  module Components
    attr_reader :components, :main

    def initialize_components
      @components = {}
      @main = nil
    end

    def aggregated_status_changed(component, options = {}); end

    def setup_components(settings)
      return unless settings

      check_main_component settings
      settings.each_pair do |type, components_by_type|
        next unless components_by_type

        components_by_type.each_pair do |id, component_settings|
          component_settings ||= {}
          @components[id] = build_component(id: id, type: type, settings: component_settings)
          @main = @components[id] if type == 'main'
        end
      end
    end

    def check_main_component(settings)
      raise ConfigurationError, 'main component must be defined' unless settings['main'] && settings['main'].size >= 1
      return unless settings['main'].size > 1

      raise ConfigurationError, "only one main component can be defined, found #{settings['main'].keys.join(', ')}"
    end

    def add_component(component)
      @components[component.c_id] = component
    end

    def infer_component_type(component_id)
      raise UnknownComponent, "Component #{component_id} mising and cannot infer type"
    end

    def find_component(component_id, build: true)
      component = @components[component_id]
      return component if component

      return unless build

      inferred_type = infer_component_type component_id
      component = inferred_type.new node: self, id: component_id
      @components[component_id] = component
      class_name = component.class.name.split('::').last
      class_name << ' component' unless %w[Component ComponentProxy].include?(class_name)
      log "Added component #{component_id} with the inferred type #{class_name}", level: :debug
      component
    end

    def clear_alarm_timestamps
      @components.each_value(&:clear_alarm_timestamps)
    end
  end
end
