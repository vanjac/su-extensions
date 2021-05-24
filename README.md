A handful of useful extensions for SketchUp. Tested with SketchUp Make 2017 on Windows.

- Fly Tool
- Hide Back Faces (back-face culling)
- Dynamic Animations: extends animation capabilities of Dynamic Components (work in progress)

`install.ps1` can be used to install all plugins for SketchUp 2017 (you will need to restart SketchUp). You can modify the script if you have a different version.

## Hide Back Faces

Adds a toggle under the Extensions menu which hides the back sides of faces -- this is also known as "back-face culling." As you orbit/pan around the scene, faces will be continuously updated. This is especially useful for working with interior spaces, or previewing how a model will appear in game engines that render single-sided polygons. You can reverse faces (by right clicking and choosing "Reverse Faces") to flip which side is considered "front."

Hide Back Faces only applies to untagged faces (aka "Layer 0"), and doesn't apply to groups or components unless you edit them.

The extension works by moving all hidden faces to a separate, hidden tag. The faces are only updated when you move the camera. They may get out of sync while using other tools; just move the camera slightly to update.

You can use Sketchup's shortcut preferences to attach a shortcut to the menu item. I recommend "Shift-K," which mirrors the "K" shortcut for viewing Back Edges. You may also find it useful to attach a shortcut to "Reverse Faces."

### Known issues
These are a result of the limitations of Ruby extensions.
- When back faces are hidden/shown you will lose all Redo commands.
- Select All and box select will only select visible faces. (Triple-clicking will select all connected faces, even hidden.)
- When deleting a selected face that's hidden, some edges will appear to remain. Just move the camera and they'll disappear.
- It can be slow with large numbers of faces in a single object