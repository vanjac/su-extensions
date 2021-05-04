require 'sketchup.rb'
include Geom

module Chroma

  class FlyTool

    @@speed = 5

    def activate
      $fly_tool_active = true
      @p_mouse_x = nil
      @p_mouse_y = nil
      @look_speed = 0.004
      # split in two to prevent stuck keys
      @fly_pos = Vector3d.new 0,0,0
      @fly_neg = Vector3d.new 0,0,0
      update_status
    end

    def deactivate(view)
      $fly_tool_active = false
    end

    def resume(view)
      $fly_tool_active = true
      update_status
    end

    def suspend(view)
      $fly_tool_active = false
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
                             "to move. Numpad +/- to adjust speed."
      Sketchup.vcb_label = "Fly Speed"
      update_vcb
    end

    def update_vcb
      Sketchup.vcb_value = @@speed.to_s
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
        @fly_pos.x = 1
      elsif key == VK_DOWN
        @fly_neg.x = -1
      elsif key == VK_RIGHT
        @fly_pos.y = 1
      elsif key == VK_LEFT
        @fly_neg.y = -1
      elsif key == 0x24 # Home
        @fly_pos.z = 1
      elsif key == 0x23 # End
        @fly_neg.z = -1
      elsif key == 0x6B # numpad +
        @@speed *= 1.5
        update_vcb
      elsif key == 0x6D # numpad -
        @@speed /= 1.5
        update_vcb
      end
    end

    def onKeyUp(key, repeat, flags, view)
      if repeat == 2
        return # ignore key repeat
      end
      if key == VK_UP
        @fly_pos.x = 0
      elsif key == VK_DOWN
        @fly_neg.x = 0
      elsif key == VK_RIGHT
        @fly_pos.y = 0
      elsif key == VK_LEFT
        @fly_neg.y = 0
      elsif key == 0x24 # Home
        @fly_pos.z = 0
      elsif key == 0x23 # End
        @fly_neg.z = 0
      end
    end

    def draw(view)
      cam = Sketchup.active_model.active_view.camera
      positive_x = (cam.target - cam.eye).normalize
      positive_z = cam.up.normalize
      positive_y = positive_x.cross positive_z
      fly = @fly_pos + @fly_neg
      positive_x.length = fly.x * @@speed
      positive_y.length = fly.y * @@speed
      positive_z.length = fly.z * @@speed
      fly_move = positive_x + positive_y + positive_z

      eye = cam.eye + fly_move
      target = cam.target + fly_move

      cam.set eye, target, cam.up
    end

  end # class FlyTool


  def self.activate_fly_tool
    Sketchup.active_model.select_tool(FlyTool.new)
  end

  unless file_loaded?(__FILE__)
    menu = UI.menu('Camera')
    menu.add_separator
    fly_item = menu.add_item('Fly') {
      self.activate_fly_tool
    }
    menu.set_validation_proc(fly_item) {
      if $fly_tool_active
        MF_CHECKED
      else
        MF_UNCHECKED
      end
    }
    file_loaded(__FILE__)
  end

end
