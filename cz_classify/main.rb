require 'sketchup.rb'

module Chroma

  def self.get_selected_schemas(selection)
    schemas = {}
    selection.each{ |entity|
      if entity.is_a?(Sketchup::ComponentInstance) ||
          entity.is_a?(Sketchup::Group)
        schema_dict = entity.definition.attribute_dictionary(
          "AppliedSchemaTypes")
        if schema_dict
          schema_dict.each_key{ |key| schemas[key] = true }
        end
      end
    }
    return schemas.keys
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
      Sketchup.active_model.selection.each{ |entity|
        if entity.is_a?(Sketchup::ComponentInstance) ||
            entity.is_a?(Sketchup::Group)
          if !entity.definition.add_classification(result[0], result[1])
            error = true
          end
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
      Sketchup.active_model.selection.each{ |entity|
        if entity.is_a?(Sketchup::ComponentInstance) ||
            entity.is_a?(Sketchup::Group)
          entity.definition.remove_classification(result[0], "")
        end
      }
    }

    UI.add_context_menu_handler{ |context_menu|
      schemas = self.get_selected_schemas(Sketchup.active_model.selection)
      if schemas.length != 0
        submenu = context_menu.add_submenu("Classifications")
        schemas.each { |schema|
          submenu.add_item(schema) { }
        }
      end
    }
  end
end