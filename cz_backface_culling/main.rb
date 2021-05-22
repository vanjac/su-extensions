require 'sketchup.rb'

# extensions to built in sketchup objects
module Sketchup
  class Model
    attr_accessor :backface_view_observer
    attr_accessor :backface_model_observer
  end
end

module Chroma

  class BackfaceViewObserver < Sketchup::ViewObserver
    attr_accessor :unhide_flag

    def initialize(model)
      @model = model
      @unhide_flag = false
    end

    def get_culled_layer
      layer = @model.layers["culled"]
      if !layer.nil?
        return layer
      end
      layer = @model.layers.add("culled")
      layer.visible = false
      return layer
    end

    def get_layer0
      return @model.layers[0]
    end

    def front_face_visible(face, cam_eye)
      normal = face.normal
      cam_normal = face.vertices[0].position - cam_eye
      return normal.angle_between(cam_normal) >= Math::PI/2
    end

    def update_hidden_faces
      if @unhide_flag
        unhide_all
        @unhide_flag = false
      end

      cam_eye = @model.active_view.camera.eye
      @model.start_operation('Backface Culling', true, false, true)

      culled_layer = get_culled_layer
      layer0 = get_layer0

      @model.active_entities.each{ |entity|
        if entity.is_a?(Sketchup::Face)
          if entity.layer == culled_layer
            if self.front_face_visible(entity, cam_eye)
              entity.layer = layer0
            end
          elsif entity.layer == layer0 && entity.visible?
            if !self.front_face_visible(entity, cam_eye)
              entity.layer = culled_layer
            end
          end
        end
      }

      @model.commit_operation
    end

    def unhide_all
      @model.start_operation('Unhide Backfaces', true, false, true)
      @model.layers.remove("culled")
      @model.commit_operation
    end

    def onViewChanged(view)
      update_hidden_faces
    end
  end

  class BackfaceModelObserver < Sketchup::ModelObserver
    def onPreSaveModel(model)
      model.backface_view_observer.unhide_all
    end

    def onPostSaveModel(model)
      model.backface_view_observer.update_hidden_faces
    end

    def onActivePathChanged(model)
      model.backface_view_observer.unhide_flag = true
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
      # since model objects are reused on windows for new models
      if !model.backface_view_observer.nil?
        model.active_view.remove_observer(model.backface_view_observer)
        model.remove_observer(model.backface_model_observer)
        # no need to unhide all, this is a new model
        model.backface_view_observer = nil
        model.backface_model_observer = nil
      end
    end
  end


  def self.hide_backfaces
    model = Sketchup.active_model
    if model.backface_view_observer.nil?
      model.backface_view_observer = BackfaceViewObserver.new(model)
      model.backface_model_observer = BackfaceModelObserver.new
      model.active_view.add_observer(model.backface_view_observer)
      model.add_observer(model.backface_model_observer)
      model.backface_view_observer.update_hidden_faces
    end
  end

  def self.show_backfaces
    model = Sketchup.active_model
    if !model.backface_view_observer.nil?
      model.active_view.remove_observer(model.backface_view_observer)
      model.remove_observer(model.backface_model_observer)
      model.backface_view_observer.unhide_all
      model.backface_view_observer = nil
      model.backface_model_observer = nil
    end
  end

  unless file_loaded?(__FILE__)
    menu = UI.menu('View')
    menu.add_separator
    hide_item = menu.add_item('Hide Backfaces') {
      if Sketchup.active_model.backface_view_observer.nil?
        self.hide_backfaces
      else
        self.show_backfaces
      end
    }
    menu.set_validation_proc(hide_item) {
      if Sketchup.active_model.backface_view_observer.nil?
        MF_UNCHECKED
      else
        MF_CHECKED
      end
    }
    Sketchup.add_observer(BackfaceAppObserver.new)
    file_loaded(__FILE__)
  end

end
