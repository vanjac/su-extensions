require 'sketchup.rb'
require 'set'

Sketchup::load 'cz_states/props'
Sketchup::load 'cz_states/state'

module Chroma

  module StateModelManager
    # key is model.definitions, because model objects are reused on Windows but
    # definitions objects are not
    @@states_editors = {}

    def self.edit_states(model, component)
      editor = @@states_editors[model.definitions]
      if editor && editor.component != component
        editor.close
        editor = nil
      end
      if !editor
        editor = StatesEditor.new(component)
        @@states_editors[model.definitions] = editor
      end
      return editor
    end

    def self.get_editor(model)
      return @@states_editors[model.definitions]
    end

    def self.close_editor(model)
      editor = @@states_editors.delete(model.definitions)
      if editor
        editor.close
      end
    end
  end

  class StatesEditor
    attr_reader :component
    attr_reader :model

    def initialize(component)
      @component = component
      @model = @component.model  # in case component gets deleted

      create_pages
      ComponentState.update_states(component, get_page_names)

      if @model.pages.selected_page
        # definition state may not match instance state
        set_state(@model.pages.selected_page)
      end

      @pages_observer = StatePagesObserver.new(self)
      @model.pages.add_observer(@pages_observer)
      @frame_observer_id = Sketchup::Pages.add_frame_change_observer(
        StateFrameObserver.new(self))
      @entity_observer = StateEntityObserver.new(self)
      @component.add_observer(@entity_observer)

      @@toolbar.show
    end

    def close
      @@toolbar.hide
      @model.pages.remove_observer(@pages_observer)
      Sketchup::Pages.remove_frame_change_observer(@frame_observer_id)
      if @component.valid?
        @component.remove_observer(@entity_observer)
      end
      delete_all_pages
    end

    # not including "use" flags
    def reset_page_properties(page)
      page.delay_time = 0
      page.transition_time = 0
    end

    def delete_all_pages
      # can't delete in each{}, so we do this instead
      pages = @model.pages
      (pages.count - 1).downto(0) { |i|
        pages.erase(pages[i])
      }
    end

    def create_pages
      delete_all_pages

      ComponentState.get_state_list(@component).each{ |state|
        page = @model.pages.add(state, 0)
        reset_page_properties(page)
      }

      current_state = ComponentState.get_state(@component)
      if current_state
        current_page = @model.pages[current_state]
        if current_page
          @model.pages.selected_page = current_page
        else
          puts "Current state not found! " + current_state
        end
      end
    end

    def store_pages
      ComponentState.set_state_list(@component, get_page_names)
    end

    def get_page_names
      return @model.pages.map{ |page| page.name }
    end

    def context_menu(model, menu, separator_lambda)
      if model.selection.length == 1  # TODO
        c = model.selection[0]
        if !ComponentState.is_valid_child(c, @component)
          return
        end
        props = ComponentProp.get_prop_list(c, @component)
        if props.empty?
          return
        end
        animated_props = Set.new(ComponentState.get_animated_props(c))
        separator_lambda.call
        submenu = menu.add_submenu("Animated Properties")
        props.each{ |prop|
          selected = animated_props.include?(prop)
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

    def edit_animated_properties
      component_props = []  # array of [component, prop]
      ComponentState.iterate_in_groups(@component) { |c|
        ComponentState.get_animated_props(c).each { |prop|
          component_props.push([c, prop])
        }
      }

      def_name = ComponentProp.friendly_definition_name(@component)
      if component_props.empty?
        UI.messagebox("No animated properties for " + def_name)
        return
      end
      names = component_props.map{ |c, prop|
        ComponentProp.friendly_component_name(c, @component) +
          " : " + prop + " "
      }
      defaults = [""] * component_props.count
      lists = ["|Remove"] * component_props.count
      result = UI.inputbox(names, defaults, lists, def_name +
        " animated properties")
      if !result
        return
      end
      (0...(result.count)).each{ |i|
        if result[i] == "Remove"
          c, prop = component_props[i]
          remove_prop(c, prop)
        end
      }
    end

    def add_prop(component, prop)
      ComponentState.add_animated_prop(component, prop)
      ComponentState.update_states(component, get_page_names)
    end

    def remove_prop(component, prop)
      ComponentState.remove_animated_prop(component, prop)
    end

    def update_state(page)
      ComponentState.update_states(component, get_page_names, page.name)
    end

    def set_state(page)
      ComponentState.set_state(@component, page.name)
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
  end  # StatesEditor

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
      @editor.store_pages
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

  class StateEntityObserver < Sketchup::EntityObserver
    def initialize(editor)
      @editor = editor
    end

    def onEraseEntity(entity)
      StateModelManager.close_editor(@editor.model)
    end
  end


  class StateAppObserver < Sketchup::AppObserver
    def initialize
      if Sketchup.active_model
        register_model(Sketchup.active_model)
      end
    end

    # https://github.com/SketchUp/api-issue-tracker/issues/663
    def onNewModel(model)
      register_model(model)
    end

    def onOpenModel(model)
      register_model(model)
    end

    def register_model(model)
      PropsModelObserver.register_model(model)
    end
  end


  def self.states_context_menu(menu)
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
  end

  def self.state_menu(component, menu, separator_lambda)
    states = ComponentState.get_state_list(component)
    if states.empty?
      return
    end
    current = ComponentState.get_state(component)
    separator_lambda.call
    submenu = menu.add_submenu("States")
    states.each { |state|
      selected = state == current
      item = submenu.add_item(state) {
        # even if already selected
        ComponentState.set_state(component, state)
      }
      submenu.set_validation_proc(item) {
        next selected ? MF_CHECKED : MF_UNCHECKED
      }
    }
  end

  unless file_loaded?(__FILE__)
    StatesEditor.init_toolbar

    # I can't find a way to remove a handler, so we can only add it at the start
    UI.add_context_menu_handler { |menu| self.states_context_menu(menu) }

    Sketchup.add_observer(StateAppObserver.new)

    file_loaded(__FILE__)
  end

end  # module
