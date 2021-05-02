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
      elsif key == 0xBB # '+'
        @@speed *= 1.5
        update_status
      elsif key == 0xBD # '-'
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


  class BackFaceObserver < Sketchup::ViewObserver

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
      @@hidden.delete_if{ |face| face.visible? }

      hide = []
      model.entities.each{ |entity|
        if entity.is_a?(Sketchup::Face) && entity.visible?
          if !self.front_face_visible(entity, cam_eye)
            entity.hidden = true
            hide.push entity
          end
        end
      }

      @@hidden.delete_if{ |face|
        if self.front_face_visible(face, cam_eye)
          face.hidden = false
          next true
        end
      }
      @@hidden += hide

      model.commit_operation
    end

    def self.unhide_all
      model = Sketchup.active_model
      model.start_operation('Show Back Faces', true, false, true)
      @@hidden.each{ |entity|
        entity.hidden = false
      }
      @@hidden = []
      model.commit_operation
    end
  
    def onViewChanged(view)
      BackFaceObserver.update_hidden_faces
    end
  end


  def self.activate_fly_tool
    Sketchup.active_model.select_tool(FlyTool.new)
  end

  def self.hide_back_faces
    if $observer_instance.nil?
      $observer_instance = BackFaceObserver.new
      Sketchup.active_model.active_view.add_observer($observer_instance)
      BackFaceObserver.update_hidden_faces
    end
  end

  def self.show_back_faces
    if !$observer_instance.nil?
      Sketchup.active_model.active_view.remove_observer($observer_instance)
      BackFaceObserver.unhide_all
      $observer_instance = nil
    end
  end

  unless file_loaded?(__FILE__)
    menu = UI.menu('Plugins')
    menu.add_item('Fly') {
      self.activate_fly_tool
    }
    menu.add_item('Hide Back Faces') {
      self.hide_back_faces
    }
    menu.add_item('Show Back Faces') {
      self.show_back_faces
    }
    file_loaded(__FILE__)
  end

end # module SUExtensions
