require 'sketchup.rb'
require 'set'

Sketchup::load 'cz_states/props'

module Chroma

  PAGE_STATE_DICT = "cz_state"
  COMPONENT_STATES_DICT = "cz_states"
  CURRENT_STATE_ATTR = "current"

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

    def self.get_editor(model)
      return @@states_editors[model]
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
      @animated_props = Set[]  # set of [component, prop]

      create_pages
      puts "animated props:"
      @animated_props.each{|item| puts "  " + item.to_s}

      @pages_observer = StatePagesObserver.new(self)
      @component.model.pages.add_observer(@pages_observer)
      @frame_observer_id = Sketchup::Pages.add_frame_change_observer(
        StateFrameObserver.new(self))
    end

    def close
      puts "close editor"
      component.model.pages.remove_observer(@pages_observer)
      Sketchup::Pages.remove_frame_change_observer(@frame_observer_id)

      store_pages
    end

    # not including "use" flags
    def reset_page_properties(page)
      page.delay_time = 0
      page.transition_time = 0
    end

    def delete_all_pages(pages)
      # can't delete in each{}, so we do this instead
      (pages.count - 1).downto(0) { |i|
        pages.erase(pages[i])
      }
    end

    def create_pages
      pages = @component.model.pages
      delete_all_pages(pages)
      states_dict = @component.attribute_dictionary(COMPONENT_STATES_DICT)
      if !states_dict
        return
      end

      states_dict.attribute_dictionaries.each { |s_dict|
        page = pages.add(s_dict.name, 0)
        reset_page_properties(page)
        page_dict = page.attribute_dictionary(PAGE_STATE_DICT, true)
        s_dict.each{ |key, value|
          component, prop = ComponentProps.key_to_component_prop(key, @component)
          if !component
            next
          end
          @animated_props.add([component, prop])
          page_dict[key] = value
        }
      }

      current = states_dict[CURRENT_STATE_ATTR]
      if current
        pages.selected_page = pages[current]
      end
    end

    def store_pages
      @component.attribute_dictionaries.delete(COMPONENT_STATES_DICT)
      states_dict = @component.attribute_dictionary(COMPONENT_STATES_DICT, true)
      pages = @component.model.pages

      pages.each{ |page|
        page_dict = page.attribute_dictionary(PAGE_STATE_DICT)
        if !page_dict
          next
        end
        s_dict = states_dict.attribute_dictionary(page.name, true)
        page_dict.each{ |key, value|
          s_dict[key] = value
        }
      }

      states_dict[CURRENT_STATE_ATTR] = pages.selected_page.name
      delete_all_pages(pages)
    end

    def context_menu(menu, model)
      if model.selection.length == 1  # TODO
        c = model.selection[0]
        props = ComponentProps.get_prop_list(c)
        if props.count == 0
          return
        end
        menu.add_separator
        submenu = menu.add_submenu("Animated Properties")
        props.each{ |prop|
          selected = @animated_props.include?([c, prop])
          item = submenu.add_item(prop) {
            if !selected
              add_prop(c, prop)
            else
              remove_prop(c, prop)
            end
          }
          submenu.set_validation_proc(item) {
            next selected ? MF_CHECKED : MF_UNCHECKED
          }
        }
      end
    end

    # add to existing states
    def add_prop(component, prop)
      @animated_props.add([component, prop])
      key = ComponentProps.component_prop_to_key(component, prop, @component)
      value = ComponentProps.get_prop_value(component, prop)
      @component.model.pages.each{ |page|
        page.set_attribute(PAGE_STATE_DICT, key, value)
      }
    end

    # remove from existing states
    def remove_prop(component, prop)
      @animated_props.delete([component, prop])
      key = ComponentProps.component_prop_to_key(component, prop, @component)
      @component.model.pages.each{ |page|
        page.delete_attribute(PAGE_STATE_DICT, key)
      }
    end

    def update_state(page)
      @animated_props.each{ |item|
        component, prop = item
        key = ComponentProps.component_prop_to_key(component, prop, @component)
        value = ComponentProps.get_prop_value(component, prop)
        page.set_attribute(PAGE_STATE_DICT, key, value)
      }
    end

    def set_state(page)
      state_dict = page.attribute_dictionary(PAGE_STATE_DICT)
      if state_dict
        state_dict.each{ |key, value|
          component, prop = ComponentProps.key_to_component_prop(key, @component)
          if component
            ComponentProps.set_prop_value(component, prop, value)
          else
            # TODO delete the key?
          end
        }
      end
    end
  end

  class StatePagesObserver < Sketchup::PagesObserver
    def initialize(editor)
      @editor = editor
    end

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

      @editor.reset_page_properties(page)
      @editor.update_state(page)
    end
  end

  class StateFrameObserver
    def initialize(editor)
      @editor = editor
    end

    def frameChange(from_page, to_page, percent_done)
      #puts "From page #{from_page.to_s} to #{to_page.to_s} (#{percent_done * 100}%)"
      @editor.set_state(to_page)
    end
  end

  unless file_loaded?(__FILE__)
    # TODO improve interface, error checking...
    UI.menu.add_item('Close Editor') {
      StateModelManager.close_editor(Sketchup.active_model)
    }
    UI.menu.add_item('Update State') {
      editor = StateModelManager.get_editor(Sketchup.active_model)
      editor.update_state(Sketchup.active_model.pages.selected_page)
    }
    # I can't find a way to remove a handler, so we can only add it at the start
    UI.add_context_menu_handler { |menu|
      editor = StateModelManager.get_editor(Sketchup.active_model)
      if editor
        editor.context_menu(menu, Sketchup.active_model)
      else
        model = Sketchup.active_model
        if model.selection.count == 1
          selected = model.selection[0]
          if selected.is_a?(Sketchup::ComponentInstance) ||
              selected.is_a?(Sketchup::Group)
            menu.add_separator
            menu.add_item('Edit States') {
              StateModelManager.edit_states(model, selected)
            }
          end
        end
      end
    }
    file_loaded(__FILE__)
  end

end  # module
