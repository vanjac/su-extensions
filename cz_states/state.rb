module Chroma
  COMPONENT_STATES_DICT = "cz_states"

  module ComponentState
    CURRENT_STATE_ATTR = "current"

    def self.get_state_list(component)
      if !component.is_a?(Sketchup::ComponentInstance) &&
          !component.is_a?(Sketchup::Group)
        return []
      end
      def_states_dict = component.definition.attribute_dictionary(
        COMPONENT_STATES_DICT)
      inst_states_dict = component.attribute_dictionary(COMPONENT_STATES_DICT)
      
      def_keys = (def_states_dict && def_states_dict.attribute_dictionaries)?
        def_states_dict.attribute_dictionaries.map{ |d| d.name } : []
      inst_keys = (inst_states_dict && inst_states_dict.attribute_dictionaries)?
        inst_states_dict.attribute_dictionaries.map{ |d| d.name } : []
      return def_keys | inst_keys
    end

    def self.get_current(component)
      inst_state = component.get_attribute(
        COMPONENT_STATES_DICT, CURRENT_STATE_ATTR)
      if inst_state
        return inst_state
      end
      def_state = component.definition.get_attribute(
        COMPONENT_STATES_DICT, CURRENT_STATE_ATTR)
      return def_state
    end

    def self.set_current(component, state)
      component.set_attribute(COMPONENT_STATES_DICT, CURRENT_STATE_ATTR, state)
      component.definition.set_attribute(
        COMPONENT_STATES_DICT, CURRENT_STATE_ATTR, state)
    end

    def self.apply_state_dict(component, dict)
      # TODO check if valid!!
      dict.each{ |key, value|
        prop = ComponentProp.from_key(key, component)
        prop.set_value(value)
      }
    end

    def self.component_is_valid(c, root)
      if !(c && c.valid? &&
        (c.is_a?(Sketchup::ComponentInstance) || c.is_a?(Sketchup::Group)))
        return false
      end
      if c == root
        return true
      end
      # make sure c is a child of the root, or nested in unique groups (but not
      # components, since those could exist elsewhere)
      loop do
        parent = c.parent
        if parent == root.definition
          return true
        elsif parent.is_a?(Sketchup::ComponentDefinition) && parent.group? &&
            parent.count_instances == 1
          c = parent.instances[0]
        else
          return false
        end
      end
      return true
    end
  end
end

