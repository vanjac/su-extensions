require 'sketchup.rb'

module Chroma

  ClassificationAttribute = Struct.new(:path, :label, :dict)

  def self.each_definition(selection, &block)
    selection.each{ |entity|
      if entity.is_a?(Sketchup::ComponentInstance) ||
          entity.is_a?(Sketchup::Group)
        block.call(entity.definition)
      end
    }
  end

  def self.get_selected_schemas(selection)
    schemas = {}
    self.each_definition(selection) { |definition|
      schema_dict = definition.attribute_dictionary(
        "AppliedSchemaTypes")
      if schema_dict
        schema_dict.each_key{ |key| schemas[key] = true }
      end
    }
    return schemas.keys
  end

  def self.get_schema_type(definition, schema)
    schema_dict = definition.attribute_dictionary(
      "AppliedSchemaTypes")
    if schema_dict
      return schema_dict[schema]
    else
      return nil
    end
  end

  def self.get_attributes(definition, schema)
    type = self.get_schema_type(definition, schema)
    if !type
      return []
    end
    dict = definition.attribute_dictionary(schema)
    if !dict
      return []
    else
      attr_list = []
      self.get_attributes_recursive(dict, [schema, type], attr_list)
      return attr_list
    end
  end

  def self.get_attributes_recursive(dict, base_path, attr_list)
    if dict["is_hidden"]
      return
    end

    if dict["value"]
      attr_list.push(ClassificationAttribute.new(base_path, base_path[2], dict))
    end

    nested = dict.attribute_dictionaries
    if nested
      nested.each{ |child|
        self.get_attributes_recursive(child, base_path + [child.name],
          attr_list)
      }
    end
  end

  def self.edit_classification_values(definition, schema)
    labels = []
    values = []
    options = []
    self.get_attributes(definition, schema).each{ |a|
      a_type = a.dict["attribute_type"]
      a_opt = a.dict["options"]
      labels.push(a.label + " (" + a_type + ")")
      values.push(definition.get_classification_value(a.path).to_s)
      if a_opt && a_type == "enumeration"
        options.push(a_opt.join("|"))
      else
        options.push("")
      end
    }
    result = UI.inputbox(labels, values, options,
      "Edit " + definition.name + " : " + schema)
  end

  unless file_loaded?(__FILE__)
    UI.menu.add_item('Add Classification') {
      schemas = Sketchup.active_model.classifications.keys
      if schemas.length == 0
        UI.messagebox("No classification schema loaded!", MB_OK)
        next
      end
      result = UI.inputbox(["Schema", "Type"], [schemas[0], ""],
        [schemas.join("|"), ""], "Add classification")
      if !result
        next
      end
      error = false
      self.each_definition(Sketchup.active_model.selection) { |definition|
        if !definition.add_classification(result[0], result[1])
          error = true
        end
      }
      if error
        UI.messagebox("Unrecognized classification type!", MB_OK)
      end
    }

    UI.menu.add_item('Remove Classification') {
      schemas = self.get_selected_schemas(Sketchup.active_model.selection)
      if schemas.length == 0
        UI.messagebox("No classifications for selected objects!", MB_OK)
        next
      end
      result = UI.inputbox(["Schema"], [schemas[0]],
        [schemas.join("|"), ""], "Remove classification")
      if !result
        next
      end
      self.each_definition(Sketchup.active_model.selection) { |definition|
        definition.remove_classification(result[0], "")
      }
    }

    UI.add_context_menu_handler{ |context_menu|
      schemas = self.get_selected_schemas(Sketchup.active_model.selection)
      if schemas.length != 0
        submenu = context_menu.add_submenu("Classifications")
        schemas.each { |schema|
          submenu.add_item(schema) {
            self.edit_classification_values(Sketchup.active_model.selection[0].definition, schema)  # TODO
          }
        }
      end
    }
  end
end