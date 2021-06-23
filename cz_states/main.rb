require 'sketchup.rb'

module Chroma

  module ComponentProps
    DEFAULT_PROPS = ["Transform", "Color", "Hidden"]
    PROPS_DICT = "cz_props"

    def self.get_prop_list(component)
      if !component.is_a?(Sketchup::ComponentInstance) &&
          !component.is_a?(Sketchup::Group)
        return []
      end
      dict = component.attribute_dictionary(PROPS_DICT)
      if !dict
        return DEFAULT_PROPS
      else
        props = DEFAULT_PROPS.clone
        dict.each{ |key, value|
          if value.is_a?(Float) || value.is_a?(Length) ||
              value == true || value == false ||
              value.is_a?(Geom::Vector3d) || value.is_a?(Geom::Point3d) ||
              value.is_a?(Sketchup::Color)
            props.push(key)
          end
        }
        return props
      end
    end

    def self.get_prop_value(component, prop)
      if prop == "Transform"
        return component.transformation.to_a
      elsif prop == "Color"
        mat = component.material
        if !mat
          return Sketchup::Color.new(255, 255, 255)
        else
          return mat.color
        end
      elsif prop == "Hidden"
        return component.hidden?
      else
        dict = component.attribute_dictionary(PROPS_DICT)
        if !dict
          return nil
        else
          return dict[prop]
        end
      end
    end

    def self.set_prop_value(component, prop, value)
      if prop == "Transform"
        component.transformation = Geom::Transformation.new(value)
      elsif prop == "Color"
        mat = component.material
        if mat
          mat.color = value
        end
      elsif prop == "Hidden"
        component.hidden = value
      else
        component.attribute_dictionary(PROPS_DICT, true)[prop] = value
      end
    end
  end

  PAGE_STATE_DICT = "cz_state"

  class StatePagesObserver < Sketchup::PagesObserver

    def onElementAdded(pages, page)
      # remove all data from the page
      page.use_axes = false
      page.use_camera = false
      # deprecated in 2020.1 but no alternatives in 2017
      page.use_hidden = false
      page.use_hidden_layers = false
      page.use_rendering_options = false
      page.use_section_planes = false
      page.use_shadow_info = false
      page.use_style = false
      # reset other properties
      page.delay_time = 0
      page.transition_time = 0

      selection = pages.model.selection
      if selection.length == 1  # TODO
        component = selection[0]
        props = ComponentProps.get_prop_list(component)
        result = UI.inputbox(props, ["No"] * props.length,
          ["Yes|No"] * props.length, "Include properties")
        if !result
          return
        end
        id_str = component.persistent_id.to_s + ":"
        (0...(props.length)).each{ |i|
          if result[i] == "Yes"
            prop = props[i]
            value = ComponentProps.get_prop_value(component, prop)
            page.attribute_dictionary(PAGE_STATE_DICT, true)[id_str + prop] = value
          end
        }
      end
    end
  end

  class StateFrameObserver
    def frameChange(from_page, to_page, percent_done)
      #puts "From page #{from_page.to_s} to #{to_page.to_s} (#{percent_done * 100}%)"

      state_dict = to_page.attribute_dictionary(PAGE_STATE_DICT)
      if state_dict
        state_dict.each{ |key, value|
          id_str, prop = key.split(":")
          component = to_page.model.find_entity_by_persistent_id(id_str.to_i)
          if component
            ComponentProps.set_prop_value(component, prop, value)
          end  # TODO else delete the key?
        }
      end
    end
  end

  unless file_loaded?(__FILE__)
    UI.menu.add_item('State Test') {
      Sketchup.active_model.pages.add_observer(StatePagesObserver.new)
      Sketchup::Pages.add_frame_change_observer(StateFrameObserver.new)
    }
    file_loaded(__FILE__)
  end

end  # module
