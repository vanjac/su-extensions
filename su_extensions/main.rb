require 'sketchup.rb'
include Geom

module SUExtensions

  class FlyTool

    @@speed = 1
    
    def activate
      @p_mouse_x = nil
      @p_mouse_y = nil
      @look_speed = 0.004
      @fly = Vector3d.new 0,0,0
      update_status
    end

    def onMouseMove(flags, x, y, view)
      if @p_mouse_x == nil
        @p_mouse_x = x
      end
      if @p_mouse_y == nil
        @p_mouse_y = y
      end
      x_move = x - @p_mouse_x
      y_move = y - @p_mouse_y
      @p_mouse_x = x
      @p_mouse_y = y
      if flags != 1
        return
      end

      cam = Sketchup.active_model.active_view.camera
      target = cam.target
      up = cam.up

      side = (cam.target - cam.eye).cross cam.up
      target_trans = Transformation.rotation(
        cam.eye, side, -y_move * @look_speed)
      up = up.transform target_trans
      if up.z < 0 # looking too far up or too far down
        up = cam.up
      else
        target = target.transform target_trans
      end

      target_trans = Transformation.rotation(
        cam.eye, Vector3d.new(0,0,1), -x_move * @look_speed)
      target = target.transform target_trans
      up = up.transform target_trans

      cam.set cam.eye, target, up
    end

    private

    def update_status
      Sketchup.status_text = "Fly. Click and drag to look, arrows/Home/End " \
                             "to move. +/- to adjust speed: #{@@speed}"
    end

    public

    def onKeyDown(key, repeat, flags, view)
      if repeat == 2
        return # ignore key repeat
      end
      # Windows key codes from:
      # https://msdn.microsoft.com/en-us/library/windows/desktop/dd375731(v=vs.85).aspx
      # TODO: add codes for Mac (also for onKeyUp)
      if key == VK_UP
        @fly.x += 1
      elsif key == VK_DOWN
        @fly.x -= 1
      elsif key == VK_RIGHT
        @fly.y += 1
      elsif key == VK_LEFT
        @fly.y -= 1
      elsif key == 0x24 # Home
        @fly.z += 1
      elsif key == 0x23 # End
        @fly.z -= 1
      elsif key == 0x6B # numpad +
        @@speed *= 1.5
        update_status
      elsif key == 0x6D # numpad -
        @@speed /= 1.5
        update_status
      end
    end

    def onKeyUp(key, repeat, flags, view)
      if repeat == 2
        return # ignore key repeat
      end
      if key == VK_UP
        @fly.x -= 1
      elsif key == VK_DOWN
        @fly.x += 1
      elsif key == VK_RIGHT
        @fly.y -= 1
      elsif key == VK_LEFT
        @fly.y += 1
      elsif key == 0x24 # Home
        @fly.z -= 1
      elsif key == 0x23 # End
        @fly.z += 1
      end
    end

    def draw(view)
      cam = Sketchup.active_model.active_view.camera
      positive_x = (cam.target - cam.eye).normalize
      positive_z = cam.up.normalize
      positive_y = positive_x.cross positive_z
      positive_x.length = @fly.x * @@speed
      positive_y.length = @fly.y * @@speed
      positive_z.length = @fly.z * @@speed
      fly_move = positive_x + positive_y + positive_z

      eye = cam.eye + fly_move
      target = cam.target + fly_move

      cam.set eye, target, cam.up
    end

  end # class FlyTool


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


  def self.activate_fly_tool
    Sketchup.active_model.select_tool(FlyTool.new)
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
    menu = UI.menu('Plugins')
    menu.add_item('Fly') {
      self.activate_fly_tool
    }
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
