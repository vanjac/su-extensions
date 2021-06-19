require 'sketchup.rb'

module Chroma

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

  def self.get_classification_paths(definition, schema)
    type = self.get_schema_type(definition, schema)
    if !type
      return []
    end
    dict = definition.attribute_dictionary(schema)
    if !dict
      return []
    else
      return self.get_paths_recursive(dict, [schema, type])
    end
  end

  def self.get_paths_recursive(dict, base_path)
    if !(/[[:upper:]]/.match(dict.name[0]))
      return []
    end

    paths = []
    if dict["value"]
      paths.push(base_path)
    end

    nested = dict.attribute_dictionaries
    if nested
      nested.each{ |child|
        paths += self.get_paths_recursive(child, base_path + [child.name])
      }
    end

    return paths
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
            self.each_definition(Sketchup.active_model.selection) { |definition|
              self.get_classification_paths(definition, schema).each{ |path|
                puts path.join(", ")
              }
            }
          }
        }
      end
    }
  end
end