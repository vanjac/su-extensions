require 'sketchup.rb'

# https://sketchucation.com/forums/viewtopic.php?f=180&t=37083
if defined?($dc_observers)

class DynamicComponentsV1
  # change DC behavior
  def make_unique_if_needed(instance)
    # lol nope
  end
end

# fix a longstanding bug in DC
unless Sketchup::Model.method_defined? :deleted?
  class Sketchup::Model
    def deleted?
      !valid?()
    end
  end
end

class DCFunctionsV1

  protected

  # arguments: current time, key 1 time, key 1 value, key 2 time, key 2 value...
  # two keys at the same time create an instant change
  # use "" as a value to hold previous value
  def keyframe(param_array)
    if param_array.length() < 3
      return 0
    end
    cur_time = param_array[0].to_f
    prev_t = 0
    prev_val = 0
    # TODO binary search?
    i = 1
    while i + 1 < param_array.length()
      key_t = param_array[i].to_f
      key_val_str = param_array[i + 1]
      if key_val_str != ""
        key_val = key_val_str.to_f
      end  # otherwise preserve previous value

      if key_t > cur_time
        if i == 1
          return key_val
        else
          return ((cur_time - prev_t) / (key_t - prev_t)) *
            (key_val - prev_val) + prev_val
        end
      end
      prev_t = key_t
      prev_val = key_val
      i += 2
    end  # while
    return prev_val
  end

end

else  # not defined
  UI.messagebox("Dynamic Components extension not loaded!")
end
