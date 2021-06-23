require 'sketchup.rb'

Sketchup::load 'cz_states/props'

module Chroma

  PAGE_STATE_DICT = "cz_state"

  module StateModelManager
    @@states_editors = {}

    def self.edit_states(model, component)
      editor = @@states_editors[model]
      if editor && editor.component != component
        editor.close
        editor = nil
      end
      if !editor
        editor = StatesEditor.new(component)
        @@states_editors[model] = editor
      end
      return editor
    end

    def self.close_editor(model)
      editor = @@states_editors.delete(model)
      if editor
        editor.close
      end
    end
  end

  class StatesEditor
    attr_reader :component

    def initialize(component)
      puts "init editor"
      @component = component

      @pages_observer = StatePagesObserver.new
      @component.model.pages.add_observer(@pages_observer)
      @frame_observer_id = Sketchup::Pages.add_frame_change_observer(
        StateFrameObserver.new)
    end

    def close
      puts "close editor"
      component.model.pages.remove_observer(@pages_observer)
      Sketchup::Pages.remove_frame_change_observer(@frame_observer_id)
    end
  end

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
          else
            puts "can't find component " + id_str
            # TODO delete the key?
          end
        }
      end
    end
  end

  unless file_loaded?(__FILE__)
    UI.menu.add_item('Edit States') {
      model = Sketchup.active_model
      StateModelManager.edit_states(model, model.selection[0])
    }
    UI.menu.add_item('Close Editor') {
      StateModelManager.close_editor(Sketchup.active_model)
    }
    file_loaded(__FILE__)
  end

end  # module
