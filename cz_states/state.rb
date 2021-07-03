module Chroma
  COMPONENT_STATES_DICT = "cz_states"

  module ComponentState
    CURRENT_STATE_ATTR = "current"

    # return definition, instance AttributeDictionaries
    # either could be nil -- will not create if they don't exist!
    def self.def_inst_state_collections(component)
      def_dict = component.definition.attribute_dictionary(
        COMPONENT_STATES_DICT)
      inst_dict = component.attribute_dictionary(COMPONENT_STATES_DICT)
      return (def_dict ? def_dict.attribute_dictionaries : nil),
        (inst_dict ? inst_dict.attribute_dictionaries : nil)
    end

    def self.get_state_list(component)
      if !component.is_a?(Sketchup::ComponentInstance) &&
          !component.is_a?(Sketchup::Group)
        return []
      end
      def_state_dicts, inst_state_dicts = def_inst_state_collections(component)
      return def_state_dicts ? def_state_dicts.map{ |d| d.name } : []
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

    def self.set_state_in_place(component, state)
      def_state_dicts, inst_state_dicts = def_inst_state_collections(component)
      def_dict = def_state_dicts ? def_state_dicts[state] : nil
      if def_dict
        apply_state_dict(component, def_dict)
      end
      inst_dict = inst_state_dicts ? inst_state_dicts[state] : nil
      if inst_dict
        apply_state_dict(component, inst_dict)
      end
      set_current(component, state)
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

