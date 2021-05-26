require 'sketchup.rb'

module Chroma

  def self.backface_culling_extension
    return @@backface_culling_extension
  end


  # active throughout model lifetime, once created
  class BackfaceManager < Sketchup::LayersObserver
    LAYER_NAME = "Hide Back Faces"
    @@model_managers = {}

    def self.get_manager(model)
      return @@model_managers[model]
    end

    def self.add_manager(model)
      manager = get_manager(model)
      if manager == nil
        manager = BackfaceManager.new(model)
        @@model_managers[model] = manager
      end
      return manager
    end

    def self.backfaces_hidden(model)
      manager = get_manager(model)
      if manager.nil?
        return false
      else
        return manager.active?
      end
    end

    def initialize(model)
      @model = model
      @enabled = false
      @paused = false
      @culled_layer = nil
      @reset_flag = false

      @model.layers.add_observer(self)
    end

    def enable
      if @enabled
        return
      end
      @enabled = true
      @paused = false

      @view_observer = BackfaceViewObserver.new(self)
      @model.active_view.add_observer(@view_observer)
      @model_observer = BackfaceModelObserver.new(self)
      @model.add_observer(@model_observer)
      @definitions_observer = BackfaceDefinitionsObserver.new(self)
      @model.definitions.add_observer(@definitions_observer)

      create_culled_layer
    end

    def disable
      if !@enabled
        return
      end
      @enabled = false

      @model.active_view.remove_observer(@view_observer)
      @view_observer = nil
      @model.remove_observer(@model_observer)
      @model_observer = nil
      @model.definitions.remove_observer(@definitions_observer)
      @definitions_observer = nil

      remove_culled_layer
    end

    def active?
      return @enabled && !@paused
    end

    def pause
      if !@paused
        @paused = true
        notification = UI::Notification.new(Chroma.backface_culling_extension,
          "Hide Back Faces interrupted");
        notification.on_accept("Resume") {
          unpause
        }
        notification.on_dismiss("Stop") {
          disable
        }
        notification.show
        # hack to bring focus back to main window
        dialog = UI::HtmlDialog.new(width: 0, height: 0)
        dialog.show
        dialog.close
      end
    end

    def unpause
      if @paused
        @paused = false
        update_hidden_faces
      end
    end

    def create_culled_layer(transparent = false)
      if @culled_layer.nil?
        @culled_layer = true  # prevent immediate trigger of onLayerAdded
        @model.start_operation('Hide Back Faces', true, false, transparent)
        @culled_layer = @model.layers.add(LAYER_NAME)
        @culled_layer.visible = false
        @culled_layer.page_behavior = LAYER_HIDDEN_BY_DEFAULT
        @model.commit_operation

        update_hidden_faces
      end
    end

    def remove_culled_layer(transparent = false)
      if !@culled_layer.nil?
        if @culled_layer.deleted?
          @culled_layer = nil
          return
        end
        layer = @culled_layer
        @culled_layer = nil  # prevent immediate trigger of onLayerRemoved
        @model.start_operation('Unhide Back Faces', true, false, transparent)
        @model.layers.remove(layer, false)
        @model.commit_operation
      end
    end

    def onLayerAdded(layers, layer)
      if @culled_layer.nil? && layer.name == LAYER_NAME
        #puts "layer added unexpectedly! probably undo/redo"
        @culled_layer = layer
        enable
      end
    end

    def onLayerRemoved(layers, layer)
      # TODO is this guaranteed to execute before onTransactionUndo?
      if !@culled_layer.nil? && layers[LAYER_NAME].nil?
        #puts "layer removed unexpectedly! probably undo/redo"
        @culled_layer = nil
        disable
      end
    end


    def front_face_visible(face, cam_eye)
      normal = face.normal
      cam_dir = cam_eye - face.vertices[0].position
      return normal.dot(cam_dir) >= 0
    end

    def update_hidden_faces
      if !active?
        return
      end
      cam_eye = @model.active_view.camera.eye
      layer0 = @model.layers["Layer0"]  # aka "untagged"
      selection = @model.selection

      operation_started = false
      # prevents starting an empty operation and overwriting the redo stack
      operation = lambda {
        if !operation_started
          operation_started = true
          @model.start_operation('Back Face Culling', true, false, true)
        end
      }

      update_entities = lambda { |entities|
        entities.each{ |entity|
          if entity.is_a?(Sketchup::Face)
            if entity.hidden?
              # ignore
            elsif selection.include?(entity)
              # avoid some crashes with performing operations on hidden faces
              # eg. intersect faces with model
              if entity.layer == @culled_layer
                operation.call
                entity.layer = layer0
              end
            elsif entity.layer == @culled_layer
              if self.front_face_visible(entity, cam_eye)
                operation.call
                entity.layer = layer0
              end
            elsif entity.layer == layer0
              if !self.front_face_visible(entity, cam_eye)
                operation.call
                entity.layer = @culled_layer
              end
            end
          elsif entity.is_a?(Sketchup::Edge) && entity.layer == @culled_layer
            # fixes bug with deleting culled faces
            operation.call
            @culled_layer.visible = true
            entity.erase!
            @culled_layer.visible = false
          end
        }
      }

      update_entities.call(@model.entities)  # root
      path = @model.active_path
      if !path.nil?
        path.each { |context|
          update_entities.call(context.definition.entities)
        }
      end

      if operation_started
        @model.commit_operation
      end
    end

    # necessary when the active path changes
    def reset
      if active?
        remove_culled_layer(true)
        create_culled_layer(true)
      end
    end

    def reset_delay
      if !@reset_flag
        @reset_flag = true
        UI.start_timer(0.1, false) {
          reset
          @reset_flag = false
        }
      end
    end
  end


  # active only when back faces hidden
  class BackfaceViewObserver < Sketchup::ViewObserver
    def initialize(manager)
      @manager = manager
    end

    def onViewChanged(view)
      @manager.update_hidden_faces
    end
  end

  # active only when back faces hidden
  class BackfaceModelObserver < Sketchup::ModelObserver
    def initialize(manager)
      @manager = manager
      @redo_stack = 0
    end

    def onPreSaveModel(model)
      @manager.remove_culled_layer(true)
    end

    def onPostSaveModel(model)
      @manager.create_culled_layer(true)
    end

    def onActivePathChanged(model)
      # can't reset immediately or it gets caught in an infinite undo loop
      @manager.reset_delay
    end

    def onTransactionCommit(manager)
      @redo_stack = 0
      @manager.unpause
    end

    def onTransactionUndo(manager)
      @redo_stack += 1
      @manager.pause
    end

    def onTransactionRedo(manager)
      @redo_stack -= 1
      if @redo_stack <= 0
        @redo_stack = 0
        @manager.unpause
      end
    end
  end

  # active only when back faces hidden
  class BackfaceDefinitionsObserver < Sketchup::DefinitionsObserver
    def initialize(manager)
      @manager = manager
    end

    # a new component or group was created
    def onComponentAdded(definitions, definition)
      # refresh to prevent groups/components from capturing hidden faces
      @manager.reset_delay
    end
  end

  # active always
  class BackfaceAppObserver < Sketchup::AppObserver
    def onNewModel(model)
      resetObservers(model)
    end

    def onOpenModel(model)
      resetObservers(model)
    end

    def resetObservers(model)
      # since model objects are reused on Windows for new models
      manager = BackfaceManager.get_manager(model)
      if !manager.nil?
        manager.disable
      end
    end
  end


  def self.hide_backfaces
    manager = BackfaceManager.add_manager(Sketchup.active_model)
    manager.enable
    manager.unpause
  end

  def self.show_backfaces
    manager = BackfaceManager.add_manager(Sketchup.active_model)
    manager.disable
  end

  unless file_loaded?(__FILE__)
    menu = UI.menu
    hide_item = menu.add_item('Hide Back Faces') {
      if BackfaceManager.backfaces_hidden(Sketchup.active_model)
        self.show_backfaces
      else
        self.hide_backfaces
      end
    }
    menu.set_validation_proc(hide_item) {
      if BackfaceManager.backfaces_hidden(Sketchup.active_model)
        MF_CHECKED
      else
        MF_UNCHECKED
      end
    }
    Sketchup.add_observer(BackfaceAppObserver.new)
    file_loaded(__FILE__)
  end

end
