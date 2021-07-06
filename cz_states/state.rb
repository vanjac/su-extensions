module Chroma

  module ComponentState
    STATES_DICT = "cz_states"
    CURRENT_STATE_ATTR = "current"
    ANIM_DICT = "cz_anim"

    def self.get_state_list(component)
      if !component.is_a?(Sketchup::ComponentInstance) &&
          !component.is_a?(Sketchup::Group)
        return []
      end
      states_dict = component.definition.attribute_dictionary(STATES_DICT)
      if states_dict && states_dict.attribute_dictionaries
        return states_dict.attribute_dictionaries.map{ |d| d.name }
      end
      return []
    end

    def self.set_state_list(component, states)
      if states.empty?
        if component.definition.attribute_dictionaries
          # also deletes "current" attribute
          component.definition.attribute_dictionaries.delete(STATES_DICT)
        end
        if component.attribute_dictionaries
          component.attribute_dictionaries.delete(STATES_DICT)
        end
      else
        states_dict = component.definition.attribute_dictionary(STATES_DICT,
          true)
        # delete existing
        if states_dict.attribute_dictionaries
          states_dict.attribute_dictionaries.to_a.each{ |d|
            states_dict.attribute_dictionaries.delete(d)
          }
        end
        states.each{ |state|
          states_dict.set_attribute(state, "empty", 0)
        }
      end

      update_states(component, states)
    end

    def self.update_states(component, states, update_state = nil)
      states_set = Set.new(states)
      iterate_in_groups(component) { |c|
        anim_dict = c.attribute_dictionary(ANIM_DICT)
        if anim_dict && anim_dict.attribute_dictionaries
          anim_dict.attribute_dictionaries.each{ |prop_dict|
            value = nil
            # add states
            states.each{ |state|
              if state == update_state || !prop_dict[state]
                if value.nil?  # could be false
                  value = ComponentProp.get_value(c, prop_dict.name)
                end
                prop_dict[state] = value
              end
            }
            # remove states; convert to array to delete while iterating
            prop_dict.to_a.each{ |key, value|
              if !states_set.include?(key)
                prop_dict.delete_key(key)
              end
            }
          }
        end
      }
    end

    def self.get_state(component)
      return component.get_attribute(STATES_DICT, CURRENT_STATE_ATTR) ||
        component.definition.get_attribute(STATES_DICT, CURRENT_STATE_ATTR)
    end

    def self.set_state(component, state)
      iterate_in_groups(component) { |c|
        anim_dict = c.attribute_dictionary(ANIM_DICT)
        if anim_dict && anim_dict.attribute_dictionaries
          anim_dict.attribute_dictionaries.each{ |prop_dict|
            value = prop_dict[state]
            if value
              ComponentProp.set_value(c, prop_dict.name, value)
            end
          }
        end
      }

      set_current_state(component, state)
    end

    # WITHOUT applying state
    def self.set_current_state(component, state)
      component.set_attribute(STATES_DICT, CURRENT_STATE_ATTR, state)
      component.definition.set_attribute(STATES_DICT, CURRENT_STATE_ATTR, state)
    end

    def self.iterate_in_groups(component, is_root = true, &action)
      if component.is_a?(Sketchup::Group)
        component.make_unique
      end

      action.call(component)

      if is_root || component.is_a?(Sketchup::Group)
        component.definition.entities.each{ |child|
          if child.is_a?(Sketchup::ComponentInstance) ||
              child.is_a?(Sketchup::Group)
            iterate_in_groups(child, false, &action)
          end
        }
      end
    end

    def self.get_animated_props(component)
      anim_dict = component.attribute_dictionary(ANIM_DICT)
      if anim_dict && anim_dict.attribute_dictionaries
        return anim_dict.attribute_dictionaries.map{ |d| d.name }
      end
      return []
    end

    # should call update_states afterwards
    def self.add_animated_prop(component, prop)
      # create the property dictionary
      component.attribute_dictionary(ANIM_DICT, true).
        attribute_dictionary(prop, true)
    end

    def self.remove_animated_prop(component, prop)
      anim_dict = component.attribute_dictionary(ANIM_DICT)
      if anim_dict && anim_dict.attribute_dictionaries
        anim_dict.attribute_dictionaries.delete(prop)
        # clean up empty dictionary
        if anim_dict.attribute_dictionaries.length == 0
          component.attribute_dictionaries.delete(ANIM_DICT)
        end
      end
    end

    def self.clear_animated_props(component)
      if component.attribute_dictionaries
        component.attribute_dictionaries.delete(ANIM_DICT)
      end
    end

    def self.is_valid_child(c, root)
      if !(c.is_a?(Sketchup::ComponentInstance) || c.is_a?(Sketchup::Group))
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
  end  # ComponentState

end
