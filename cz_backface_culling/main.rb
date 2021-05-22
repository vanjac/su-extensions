require 'sketchup.rb'

# extensions to built in sketchup objects
module Sketchup
  class Model
    attr_accessor :backface_manager
  end
end

module Chroma

  class BackfaceManager
    attr_accessor :view_observer
    attr_accessor :model_observer

    def initialize(model)
      @model = model
      @model.backface_manager = self

      @view_observer = BackfaceViewObserver.new(@model)
      @model.active_view.add_observer(@view_observer)
      @model_observer = BackfaceModelObserver.new
      @model.add_observer(@model_observer)

      @view_observer.update_hidden_faces
    end

    def remove
      @model.backface_manager = nil

      @model.active_view.remove_observer(@view_observer)
      @model.remove_observer(@model_observer)
    end
  end

  class BackfaceViewObserver < Sketchup::ViewObserver
    def initialize(model)
      @model = model
    end

    def get_culled_layer
      layer = @model.layers["culled"]
      if !layer.nil?
        return layer
      end
      layer = @model.layers.add("culled")
      layer.visible = false
      layer.page_behavior = LAYER_HIDDEN_BY_DEFAULT
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
          @model.start_operation('Backface Culling', true, false, true)
        end
      }

      @model.active_entities.each{ |entity|
        if entity.is_a?(Sketchup::Face)
          if entity.layer == culled_layer
            if self.front_face_visible(entity, cam_eye)
              operation.call
              entity.layer = layer0
            end
          elsif entity.layer == layer0 && entity.visible?
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

      if operation_started
        @model.commit_operation
      end
    end

    def unhide_all
      @model.start_operation('Unhide Back Faces', true, false, true)
      if !@model.layers["culled"].nil?
        @model.layers.remove("culled", false)
      end
      @model.commit_operation
    end

    # necessary when the active path changes
    def reset
      unhide_all
      update_hidden_faces
    end

    def onViewChanged(view)
      update_hidden_faces
    end
  end

  class BackfaceModelObserver < Sketchup::ModelObserver
    def onPreSaveModel(model)
      model.backface_manager.view_observer.unhide_all
    end

    def onPostSaveModel(model)
      model.backface_manager.view_observer.update_hidden_faces
    end

    def onActivePathChanged(model)
      # can't reset immediately or it gets caught in an infinite undo loop
      UI.start_timer(0.1, false) { model.backface_manager.view_observer.reset }
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
      if !model.backface_manager.nil?
        model.backface_manager.remove
      end
    end
  end


  def self.hide_backfaces
    model = Sketchup.active_model
    if model.backface_manager.nil?
      BackfaceManager.new(model)
    end
  end

  def self.show_backfaces
    model = Sketchup.active_model
    if !model.backface_manager.nil?
      model.backface_manager.view_observer.unhide_all
      model.backface_manager.remove
    end
  end

  unless file_loaded?(__FILE__)
    menu = UI.menu
    hide_item = menu.add_item('Hide Back Faces') {
      if Sketchup.active_model.backface_manager.nil?
        self.hide_backfaces
      else
        self.show_backfaces
      end
    }
    menu.set_validation_proc(hide_item) {
      if Sketchup.active_model.backface_manager.nil?
        MF_UNCHECKED
      else
        MF_CHECKED
      end
    }
    Sketchup.add_observer(BackfaceAppObserver.new)
    file_loaded(__FILE__)
  end

end
