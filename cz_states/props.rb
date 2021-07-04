module Chroma

  class PropsModelObserver < Sketchup::ModelObserver
    @@model_observers = {}

    def initialize(model)
      @last_path = active_path(model)

      @global_edit_transforms = {model => Geom::Transformation.new}
      @path_instances = {model => model}

      @@model_observers[model] = self
    end

    def self.get_observer(model)
      return @@model_observers[model]
    end

    def active_path(model)
      return model.active_path || []
    end

    def close_active(model)
      model.selection.clear
      model.close_active
      onActivePathChanged(model)  # not called automatically :(
    end

    def onActivePathChanged(model)
      path = active_path(model)
      # TODO these assume the path only changes by one item at a time
      if path.count > @last_path.count
        @global_edit_transforms[path.last] = model.edit_transform
        @path_instances[path.last.definition] = path.last
      elsif path.count < @last_path.count
        @global_edit_transforms.delete(@last_path.last)
        @path_instances.delete(@last_path.last.definition)
      end

      @last_path = path
    end

    def get_local_transform(component)
      # https://forums.sketchup.com/t/is-adding-entities-in-local-or-global-coordinates/78079/3
      # this is a replacement for local_transformation provided by DC, which
      # is buggy and broken like the rest of DC.

      parent_inst_on_path = @path_instances[component.parent]
      if @global_edit_transforms[component]
        # TODO possible bugs with newly created groups????
        #puts "component on path!"
        # component.transformation will be identity (ignore)
        return (@global_edit_transforms[parent_inst_on_path].inverse *
          @global_edit_transforms[component])
      elsif @global_edit_transforms[parent_inst_on_path]
        #puts "parent on path!"
        # component.transformation will be in global coordinates
        return (@global_edit_transforms[parent_inst_on_path].inverse *
          component.transformation)
      end
      # component.transformation will be in local coordinates
      return component.transformation
    end

    def set_local_transform(component, transform)
      model = component.model
      if component.parent.is_a?(Sketchup::Model)
        # close all active contexts
        (0...(active_path(model).count)).each{ |i|
          close_active(model)
        }
      else
        # close until component parent is not on path
        while @path_instances[component.parent]
          close_active(model)
        end
      end
      component.transformation = transform
    end
  end

  # reference to a component property
  class ComponentProp
    PROPS_DICT = "cz_props"

    attr_reader :component
    attr_reader :name
    attr_reader :key

    def initialize(component, name, key)
      @component = component
      @name = name
      @key = key
    end

    def self.from_name(component, name, root)
      if component == root
        id_str = "root"
      else
        id_str = component.persistent_id.to_s
      end
      key = id_str + ":" + name
      return ComponentProp.new(component, name, key)
    end

    def self.from_key(key, root)
      id_str, name = key.split(":")
      if id_str == "root"
        component = root
      else
        component = root.model.find_entity_by_persistent_id(id_str.to_i)
        if !component
          puts "can't find component " + id_str
        end
      end
      return ComponentProp.new(component, name, key)
    end

    def ==(o)
      o.class == self.class && o.key == @key
    end

    alias_method :eql?, :==

    def hash
      @key.hash
    end

    def self.get_prop_list(component, root)
      if !component.is_a?(Sketchup::ComponentInstance) &&
          !component.is_a?(Sketchup::Group)
        return []
      end
      # applies to every component
      props = ["Transform", "Color", "Hidden"].map{ |name|
        ComponentProp.from_name(component, name, root)
      }
      # TODO add a has_states? method?
      if component != root && ! ComponentState.get_state_list(component).empty?
        props.push(ComponentProp.from_name(component, "State", root))
      end
      dict = component.attribute_dictionary(PROPS_DICT)
      if dict
        dict.each{ |key, value|
          if value.is_a?(Float) || value.is_a?(Length) ||
              value == true || value == false ||
              value.is_a?(Geom::Vector3d) || value.is_a?(Geom::Point3d) ||
              value.is_a?(Sketchup::Color)
            props.push(ComponentProp.from_name(component, key, root))
          end
        }
      end
      return props
    end

    def get_value
      if @name == "Transform"
        return PropsModelObserver.get_observer(@component.model).
          get_local_transform(@component).to_a
      elsif @name == "Color"
        mat = @component.material
        if !mat
          return Sketchup::Color.new(255, 255, 255)
        else
          return mat.color
        end
      elsif @name == "Hidden"
        return @component.hidden?
      elsif @name == "State"
        return ComponentState.get_current(@component) || ""
      else
        dict = @component.attribute_dictionary(PROPS_DICT)
        if !dict
          return nil
        else
          return dict[@name]
        end
      end
    end

    def set_value(value)
      if @name == "Transform"
        transform = Geom::Transformation.new(value)
        PropsModelObserver.get_observer(@component.model).
          set_local_transform(@component, transform)
      elsif @name == "Color"
        mat = @component.material
        if mat
          mat.color = value
        end
      elsif @name == "Hidden"
        @component.hidden = value
      elsif @name == "State"
        if value != ""
          ComponentState.set_state_in_place(@component, value)
        end
      else
        @component.attribute_dictionary(PROPS_DICT, true)[@name] = value
      end
    end

    def self.is_instance_prop(key)
      # currently only one instance property
      return key == "root:Transform"
    end

    def friendly_name(root)
      ComponentProp.friendly_component_name(@component, root) + " : " + @name
    end

    def self.friendly_component_name(component, root)
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
        return friendly_component_name(component, nil)
      else
        return component.definition.name
      end
    end
  end

end