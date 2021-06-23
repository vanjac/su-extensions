module Chroma

  module ComponentProps
    DEFAULT_PROPS = ["Transform", "Color", "Hidden"]
    PROPS_DICT = "cz_props"

    def self.get_prop_list(component)
      if !component.is_a?(Sketchup::ComponentInstance) &&
          !component.is_a?(Sketchup::Group)
        return []
      end
      dict = component.attribute_dictionary(PROPS_DICT)
      if !dict
        return DEFAULT_PROPS
      else
        props = DEFAULT_PROPS.clone
        dict.each{ |key, value|
          if value.is_a?(Float) || value.is_a?(Length) ||
              value == true || value == false ||
              value.is_a?(Geom::Vector3d) || value.is_a?(Geom::Point3d) ||
              value.is_a?(Sketchup::Color)
            props.push(key)
          end
        }
        return props
      end
    end

    def self.get_prop_value(component, prop)
      if prop == "Transform"
        return component.transformation.to_a
      elsif prop == "Color"
        mat = component.material
        if !mat
          return Sketchup::Color.new(255, 255, 255)
        else
          return mat.color
        end
      elsif prop == "Hidden"
        return component.hidden?
      else
        dict = component.attribute_dictionary(PROPS_DICT)
        if !dict
          return nil
        else
          return dict[prop]
        end
      end
    end

    def self.set_prop_value(component, prop, value)
      if prop == "Transform"
        component.transformation = Geom::Transformation.new(value)
      elsif prop == "Color"
        mat = component.material
        if mat
          mat.color = value
        end
      elsif prop == "Hidden"
        component.hidden = value
      else
        component.attribute_dictionary(PROPS_DICT, true)[prop] = value
      end
    end

    def self.component_prop_to_key(component, prop, root)
      if component == root
        id_str = "root"
      else
        id_str = component.persistent_id.to_s
      end
      return id_str + ":" + prop
    end

    def self.key_to_component_prop(key, root)
      id_str, prop = key.split(":")
      if id_str == "root"
        component = root
      else
        component = root.model.find_entity_by_persistent_id(id_str.to_i)
        if !component
          puts "can't find component " + id_str
        end
      end
      return component, prop
    end

  end

end