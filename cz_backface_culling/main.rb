require 'sketchup.rb'

module Chroma

  class BackfaceManager
    LAYER_NAME = "Hide Back Faces"
    @@model_managers = {}

    def initialize(model)
      @model = model
      @@model_managers[@model] = self
      @reset_flag = false

      @view_observer = BackfaceViewObserver.new(self)
      @model.active_view.add_observer(@view_observer)
      @model_observer = BackfaceModelObserver.new(self)
      @model.add_observer(@model_observer)
      @definitions_observer = BackfaceDefinitionsObserver.new(self)
      @model.definitions.add_observer(@definitions_observer)

      update_hidden_faces
    end

    def remove
      @@model_managers.delete(@model)

      @model.active_view.remove_observer(@view_observer)
      @model.remove_observer(@model_observer)
      @model.definitions.remove_observer(@definitions_observer)
    end

    def self.get_manager(model)
      return @@model_managers[model]
    end

    def get_culled_layer
      layer = @model.layers[LAYER_NAME]
      if !layer.nil?
        return layer
      end
      @model.start_operation('Hide Back Faces', true, false, true)
      layer = @model.layers.add(LAYER_NAME)
      layer.visible = false
      layer.page_behavior = LAYER_HIDDEN_BY_DEFAULT
      @model.commit_operation
      return layer
    end

    def front_face_visible(face, cam_eye)
      normal = face.normal
      cam_dir = cam_eye - face.vertices[0].position
      return normal.dot(cam_dir) >= 0
    end

    def update_hidden_faces
      cam_eye = @model.active_view.camera.eye
      culled_layer = get_culled_layer
      layer0 = @model.layers["Layer0"]  # aka "untagged"

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
            elsif entity.layer == culled_layer
              if self.front_face_visible(entity, cam_eye)
                operation.call
                entity.layer = layer0
              end
            elsif entity.layer == layer0
              if !self.front_face_visible(entity, cam_eye)
                operation.call
                entity.layer = culled_layer
              end
            end
          elsif entity.is_a?(Sketchup::Edge) && entity.layer == culled_layer
            # fixes bug with deleting culled faces
            operation.call
            culled_layer.visible = true
            entity.erase!
            culled_layer.visible = false
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

    def unhide_all
      @model.start_operation('Unhide Back Faces', true, false, true)
      if !@model.layers[LAYER_NAME].nil?
        @model.layers.remove(LAYER_NAME, false)
      end
      @model.commit_operation
    end

    # necessary when the active path changes
    def reset
      unhide_all
      update_hidden_faces
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


  class BackfaceViewObserver < Sketchup::ViewObserver
    def initialize(manager)
      @manager = manager
    end

    def onViewChanged(view)
      @manager.update_hidden_faces
    end
  end

  class BackfaceModelObserver < Sketchup::ModelObserver
    def initialize(manager)
      @manager = manager
    end

    def onPreSaveModel(model)
      @manager.unhide_all
    end

    def onPostSaveModel(model)
      @manager.update_hidden_faces
    end

    def onActivePathChanged(model)
      # can't reset immediately or it gets caught in an infinite undo loop
      @manager.reset_delay
    end
  end

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
        manager.remove
      end
    end
  end


  def self.hide_backfaces
    model = Sketchup.active_model
    if BackfaceManager.get_manager(model).nil?
      BackfaceManager.new(model)
    end
  end

  def self.show_backfaces
    manager = BackfaceManager.get_manager(Sketchup.active_model)
    if !manager.nil?
      manager.unhide_all
      manager.remove
    end
  end

  unless file_loaded?(__FILE__)
    menu = UI.menu
    hide_item = menu.add_item('Hide Back Faces') {
      if BackfaceManager.get_manager(Sketchup.active_model).nil?
        self.hide_backfaces
      else
        self.show_backfaces
      end
    }
    menu.set_validation_proc(hide_item) {
      if BackfaceManager.get_manager(Sketchup.active_model).nil?
        MF_UNCHECKED
      else
        MF_CHECKED
      end
    }
    Sketchup.add_observer(BackfaceAppObserver.new)
    file_loaded(__FILE__)
  end

end
