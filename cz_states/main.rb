require 'sketchup.rb'
require 'set'

Sketchup::load 'cz_states/props'
Sketchup::load 'cz_states/state'

module Chroma

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
    PAGE_STATE_DICT = "cz_state"

    attr_reader :component

    def initialize(component)
      @component = component
      @animated_props = Set[]  # set of ComponentProps

      if @component.is_a?(Sketchup::Group)
        @component.make_unique
      end

      create_pages

      # definition state may not match instance state
      current_state = ComponentState.get_current(@component)
      if current_state
        current_page = @component.model.pages[current_state]
        @component.model.pages.selected_page = current_page
        set_state(current_page)
      end

      @pages_observer = StatePagesObserver.new(self)
      @component.model.pages.add_observer(@pages_observer)
      @frame_observer_id = Sketchup::Pages.add_frame_change_observer(
        StateFrameObserver.new(self))

      @@toolbar.show
    end

    def close
      @@toolbar.hide
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
      inst_states_dict = @component.attribute_dictionary(COMPONENT_STATES_DICT)
      def_states_dict = @component.definition.attribute_dictionary(
        COMPONENT_STATES_DICT)

      copy_states_dict_to_pages(def_states_dict, pages)
      copy_states_dict_to_pages(inst_states_dict, pages)  # overrides definition
    end

    def copy_states_dict_to_pages(states_dict, pages)
      if !states_dict
        return
      end

      if states_dict.attribute_dictionaries
        states_dict.attribute_dictionaries.each { |s_dict|
          page = pages[s_dict.name]
          if !page
            page = pages.add(s_dict.name, 0)
            reset_page_properties(page)
          end
          page_dict = page.attribute_dictionary(PAGE_STATE_DICT, true)
          s_dict.each{ |key, value|
            @animated_props.add(ComponentProp.from_key(key, @component))
            page_dict[key] = value
          }
        }
      end
    end

    def store_pages
      definition = @component.definition
      # we can't merge these, even for Groups, because the group could later be
      # converted into a component (which preserves inst/def dictionaries)
      if @component.attribute_dictionary(COMPONENT_STATES_DICT)
        @component.attribute_dictionaries.delete(COMPONENT_STATES_DICT)
      end
      inst_states_dict = @component.attribute_dictionary(
        COMPONENT_STATES_DICT, true)
      if definition.attribute_dictionary(COMPONENT_STATES_DICT)
        definition.attribute_dictionaries.delete(COMPONENT_STATES_DICT)
      end
      def_states_dict = definition.attribute_dictionary(
        COMPONENT_STATES_DICT, true)

      pages = @component.model.pages

      pages.each{ |page|
        page_dict = page.attribute_dictionary(PAGE_STATE_DICT)
        if !page_dict
          next
        end
        page_dict.each{ |key, value|
          if ComponentProp.is_instance_prop(key)
            inst_states_dict.set_attribute(page.name, key, value)
          else
            def_states_dict.set_attribute(page.name, key, value)
          end
        }
      }

      if pages.selected_page
        ComponentState.set_current(@component, pages.selected_page.name)
      end
      delete_all_pages(pages)
    end

    def context_menu(model, menu, separator_lambda)
      if model.selection.length == 1  # TODO
        c = model.selection[0]
        if !ComponentState.component_is_valid(c, @component)
          return
        end
        props = ComponentProp.get_prop_list(c, @component)
        if props.count == 0
          return
        end
        separator_lambda.call
        submenu = menu.add_submenu("Animated Properties")
        props.each{ |prop|
          selected = @animated_props.include?(prop)
          item = submenu.add_item(prop.name) {
            if !selected
              add_prop(prop)
            else
              remove_prop(prop)
            end
          }
          submenu.set_validation_proc(item) {
            next selected ? MF_CHECKED : MF_UNCHECKED
          }
        }
      end
    end

    def edit_animated_properties
      check_animated_props

      def_name = ComponentProp.friendly_definition_name(@component)
      if @animated_props.count == 0
        UI.messagebox("No animated properties for " + def_name)
        return
      end
      props = @animated_props.to_a  # capture consistent order
      names = props.map{ |prop| prop.friendly_name(@component) + " " }
      defaults = [""] * names.count
      lists = ["|Remove"] * names.count
      result = UI.inputbox(names, defaults, lists, def_name +
        " animated properties")
      if !result
        return
      end
      (0...(result.count)).each{ |i|
        if result[i] == "Remove"
          remove_prop(props[i])
        end
      }
    end

    def check_animated_props
      invalid = @animated_props.select{ |prop|
        !ComponentState.component_is_valid(prop.component, @component)
      }
      invalid.each{ |prop|
        puts "deleting prop " + prop.key
        remove_prop(prop)
      }
    end

    # add to existing states
    def add_prop(prop)
      @animated_props.add(prop)
      value = prop.get_value
      @component.model.pages.each{ |page|
        page.set_attribute(PAGE_STATE_DICT, prop.key, value)
      }
    end

    # remove from existing states
    def remove_prop(prop)
      @animated_props.delete(prop)
      @component.model.pages.each{ |page|
        page.delete_attribute(PAGE_STATE_DICT, prop.key)
      }
    end

    def update_state(page)
      check_animated_props
      @animated_props.each{ |prop|
        page.set_attribute(PAGE_STATE_DICT, prop.key, prop.get_value)
      }
    end

    def set_state(page)
      check_animated_props
      state_dict = page.attribute_dictionary(PAGE_STATE_DICT)
      if state_dict
        ComponentState.apply_state_dict(@component, state_dict)
      end
    end

    def self.init_toolbar
      @@toolbar = UI.toolbar("Edit States")

      validation_proc = proc {
        if StateModelManager.get_editor(Sketchup.active_model)
          MF_ENABLED
        else
          MF_GRAYED
        end
      }

      cmd = UI::Command.new('Animated Properties') {
        editor = StateModelManager.get_editor(Sketchup.active_model)
        editor.edit_animated_properties
      }
      cmd.tooltip = cmd.menu_text
      cmd.status_bar_text =
        "List all animated properties, with options to remove."
      cmd.set_validation_proc(&validation_proc)
      cmd.large_icon = icon_path("list_large")
      cmd.small_icon = icon_path("list_small")
      @@toolbar.add_item(cmd)

      cmd = UI::Command.new('Update State') {
        editor = StateModelManager.get_editor(Sketchup.active_model)
        selected_page = Sketchup.active_model.pages.selected_page
        if selected_page
          editor.update_state(Sketchup.active_model.pages.selected_page)
        end
      }
      cmd.tooltip = cmd.menu_text
      cmd.status_bar_text =
        "Refresh selected state with the current values of animated properties"
      cmd.set_validation_proc(&validation_proc)
      cmd.large_icon = icon_path("update_large")
      cmd.small_icon = icon_path("update_small")
      @@toolbar.add_item(cmd)

      cmd = UI::Command.new('Close Editor') {
        StateModelManager.close_editor(Sketchup.active_model)
      }
      cmd.tooltip = cmd.menu_text
      cmd.status_bar_text = "Save component states and exit the editor."
      cmd.set_validation_proc(&validation_proc)
      cmd.large_icon = icon_path("close_large")
      cmd.small_icon = icon_path("close_small")
      @@toolbar.add_item(cmd)

      UI.start_timer(0.1, false) {
        @@toolbar.hide
      }
    end

    def self.icon_path(name)
      return Sketchup.find_support_file(name + ".png", "Plugins/cz_states/")
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

  def self.state_menu(component, menu, separator_lambda)
    states = ComponentState.get_state_list(component)
    if states.count == 0
      return
    end
    current = ComponentState.get_current(component)
    separator_lambda.call
    submenu = menu.add_submenu("States")
    states.each { |state|
      selected = state == current
      item = submenu.add_item(state) {
        # even if already selected
        # TODO
      }
      submenu.set_validation_proc(item) {
        next selected ? MF_CHECKED : MF_UNCHECKED
      }
    }
  end

  unless file_loaded?(__FILE__)
    StatesEditor.init_toolbar

    # I can't find a way to remove a handler, so we can only add it at the start
    UI.add_context_menu_handler { |menu|
      separator = false
      separator_lambda = lambda {
        if !separator
          menu.add_separator
          separator = true
        end
      }

      model = Sketchup.active_model
      selected = model.selection.count == 1 ? model.selection[0] : nil
      editor = StateModelManager.get_editor(Sketchup.active_model)
      if editor
        editor.context_menu(Sketchup.active_model, menu, separator_lambda)
      end

      if selected && (selected.is_a?(Sketchup::ComponentInstance) ||
          selected.is_a?(Sketchup::Group))
        if !editor || editor.component != selected
          state_menu(selected, menu, separator_lambda)
        end
        if !editor
          separator_lambda.call
          menu.add_item('Edit States') {
            StateModelManager.edit_states(model, selected)
          }
        end
      end
    }

    Sketchup.add_observer(PropsAppObserver.new)

    file_loaded(__FILE__)
  end

end  # module
