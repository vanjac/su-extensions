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
    def initialize(model)
      @model = model
      @hidden = []
    end

    def front_face_visible(face, cam_eye)
      normal = face.normal
      cam_normal = face.vertices[0].position - cam_eye
      return normal.angle_between(cam_normal) >= Math::PI/2
    end

    def update_hidden_faces
      cam_eye = @model.active_view.camera.eye
      @model.start_operation('Backface Culling', true, false, true)

      # in case user did "unhide all"
      @hidden.delete_if{ |face| face.deleted? || face.visible? }

      hide = []
      @model.active_entities.each{ |entity|
        if entity.is_a?(Sketchup::Face) && entity.visible?
          if !self.front_face_visible(entity, cam_eye)
            entity.hidden = true
            hide.push entity
          end
        end
      }

      current_parent = (@model.active_path.nil?) ? @model :
                       @model.active_path[-1].definition
      @hidden.delete_if{ |face|
        if self.front_face_visible(face, cam_eye) ||
              face.parent != current_parent
          face.hidden = false
          next true
        end
      }
      @hidden += hide

      @model.commit_operation
    end

    def unhide_all
      @model.start_operation('Unhide Backfaces', true, false, true)
      @hidden.each{ |face|
        if !face.deleted?
          face.hidden = false
        end
      }
      @hidden = []
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
