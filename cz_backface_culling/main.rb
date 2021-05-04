require 'sketchup.rb'

module SUExtensions

  class BackfaceViewObserver < Sketchup::ViewObserver

    @@hidden = []

    def self.front_face_visible(entity, cam_eye)
      normal = entity.normal
      cam_normal = entity.bounds.center - cam_eye
      return normal.angle_between(cam_normal) >= Math::PI/2
    end

    def self.update_hidden_faces
      model = Sketchup.active_model
      cam_eye = model.active_view.camera.eye
      model.start_operation('Backface Culling', true, false, true)

      # in case user did "unhide all"
      @@hidden.delete_if{ |face| face.deleted? || face.visible? }

      hide = []
      model.active_entities.each{ |entity|
        if entity.is_a?(Sketchup::Face) && entity.visible?
          if !self.front_face_visible(entity, cam_eye)
            entity.hidden = true
            hide.push entity
          end
        end
      }

      current_parent = (model.active_path.nil?) ? model :
                       model.active_path[-1].definition
      @@hidden.delete_if{ |face|
        if self.front_face_visible(face, cam_eye) ||
              face.parent != current_parent
          face.hidden = false
          next true
        end
      }
      @@hidden += hide

      model.commit_operation
    end

    def self.unhide_all
      model = Sketchup.active_model
      model.start_operation('Unhide Backfaces', true, false, true)
      @@hidden.each{ |face|
        if !face.deleted?
          face.hidden = false
        end
      }
      @@hidden = []
      model.commit_operation
    end

    def onViewChanged(view)
      BackfaceViewObserver.update_hidden_faces
    end
  end

  class BackfaceModelObserver < Sketchup::ModelObserver
    def onPreSaveModel(model)
      BackfaceViewObserver.unhide_all
    end

    def onPostSaveModel(model)
      BackfaceViewObserver.update_hidden_faces
    end
  end


  def self.hide_back_faces
    if $view_observer.nil?
      $view_observer = BackfaceViewObserver.new
      $model_observer = BackfaceModelObserver.new
      Sketchup.active_model.active_view.add_observer($view_observer)
      Sketchup.active_model.add_observer($model_observer)
      BackfaceViewObserver.update_hidden_faces
    end
  end

  def self.show_back_faces
    if !$view_observer.nil?
      Sketchup.active_model.active_view.remove_observer($view_observer)
      Sketchup.active_model.remove_observer($model_observer)
      BackfaceViewObserver.unhide_all
      $view_observer = nil
      $model_observer = nil
    end
  end

  unless file_loaded?(__FILE__)
    menu = UI.menu('View')
    menu.add_separator
    hide_item = menu.add_item('Hide Backfaces') {
      if $view_observer.nil?
        self.hide_back_faces
      else
        self.show_back_faces
      end
    }
    menu.set_validation_proc(hide_item) {
      if $view_observer.nil?
        MF_UNCHECKED
      else
        MF_CHECKED
      end
    }
    file_loaded(__FILE__)
  end

end # module SUExtensions
