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
        # https://forums.sketchup.com/t/is-adding-entities-in-local-or-global-coordinates/78079/3
        # this should be the *local* transform relative to component parent.
        # this is a replacement for local_transformation provided by DC, which
        # is buggy and broken like the rest of DC.

        if $local_edit_transforms[component.to_s]
          # TODO bugs with newly created groups????
          return $local_edit_transforms[component.to_s].to_a
        elsif component.parent
          path = component.model.active_path || []
          path.each{ |path_ent|
            if path_ent == component.parent ||
                path_ent.definition == component.parent
              return ($global_edit_transforms[path_ent.to_s].inverse *
                component.transformation).to_a
            end
          }
        end
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

    def self.is_instance_prop(key)
      # currently only one instance property
      return key == "root:Transform"
    end

    def self.friendly_name(component, root)
      if component == root
        return "root"
      elsif component.name && component.name != ""
        return component.name
      else
        return "<" + component.definition.name + ">"
      end
    end

    def self.friendly_definition_name(component)
      if component.is_a?(Sketchup::Group)
        return friendly_name(component, nil)
      else
        return component.definition.name
      end
    end

  end

end