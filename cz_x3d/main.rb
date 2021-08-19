require 'sketchup'
require 'rexml/document'
require 'set'

module Chroma
  class X3DWriter
    attr_accessor :debug

    def initialize(version, profile)
      @version = version
      @profile = profile
      @debug = false

      @units = Length::Meter
    end

    def write(model, path)
      @used_materials = Set[] # set of material names

      doc = REXML::Document.new
      doc << REXML::XMLDecl.new('1.0', 'UTF-8')

      root = doc.add_element('X3D')
      root.add_attribute('version', @version)
      root.add_attribute('profile', @profile)
      scene = root.add_element('Scene')

      write_entities(model.entities, scene)

      File.open(path, 'w') do |file|
        doc.write(output: file, indent: @debug ? 2 : -1)
      end
    end

    def write_entities(entities, root)
      # TODO: group by material
      entities.grep(Sketchup::Face) do |face|
        shape = root.add_element('Shape')

        mesh = face.mesh(1 | 4) # UVQFront, Normals
        normals_array = (1..mesh.count_points).map { |i| mesh.normal_at(i) }
        indices_array = mesh.polygons.flatten(1).map { |x| x.abs - 1 }

        tri_set = shape.add_element('IndexedTriangleSet')
        coord = tri_set.add_element('Coordinate')
        coord.add_attribute('point', points_to_mfvec3f(mesh.points))
        normal = tri_set.add_element('Normal')
        normal.add_attribute('vector', vectors_to_mfvec3f(normals_array))
        texcoord = tri_set.add_element('TextureCoordinate')
        texcoord.add_attribute('point', texcoords_to_mfvec2f(mesh.uvs(true)))
        tri_set.add_attribute('index', join_mf(indices_array))

        face_mat = face.material

        if face_mat
          if @used_materials.include? face_mat.name
            shape.add_element('Appearance', {'USE' => face_mat.name})
          else
            appearance = shape.add_element('Appearance')
            appearance.add_attribute('DEF', face_mat.name)
            appearance.add_element('Material')
            face_tex = face_mat.texture
            if face_tex
              # TODO version 4.0 supports textures assigned to Material
              imagetex = appearance.add_element('ImageTexture')
              imagetex.add_attribute('url', path_to_uri(face_tex.filename))
            end
            @used_materials.add(face_mat.name)
          end
        end
      end
    end

    def length_to_units(length)
      length.to_m # TODO version 3.3 supports UNIT statement
    end

    def path_to_uri(path)
      # TODO handle relative paths
      "file:///#{path.gsub('\\', '/')}"
    end

    # FIELDS
    # https://www.web3d.org/documents/specifications/19776-1/V3.3/Part01/EncodingOfFields.html

    def join_mf(sf_array)
      sf_array.join(', ')
    end

    # performs unit conversion
    def point_to_svvec3f(point)
      "#{length_to_units(point.x)} #{length_to_units(point.y)} #{length_to_units(point.z)}"
    end

    def points_to_mfvec3f(points)
      join_mf(points.map { |x| point_to_svvec3f(x) })
    end

    # does NOT perform unit conversion
    def vector_to_sfvec3f(vector)
      "#{vector.x.to_f} #{vector.y.to_f} #{vector.z.to_f}"
    end

    def vectors_to_mfvec3f(vectors)
      join_mf(vectors.map { |x| vector_to_sfvec3f(x) })
    end

    def texcoord_to_svvec2f(point)
      # X3D does not support homogeneous coordinates
      # TODO: use vertex attribute?
      u = point.x.to_f / point.z.to_f
      v = point.y.to_f / point.z.to_f
      "#{u} #{v}"
    end

    def texcoords_to_mfvec2f(points)
      join_mf(points.map { |x| texcoord_to_svvec2f(x) })
    end
  end

  def self.export_x3d
    # path = UI.savepanel('Export X3D', '', '*.x3d')
    writer = X3DWriter.new('3.2', 'Full')
    writer.debug = true
    writer.write(Sketchup.active_model, 'D:\\git\\su-extensions\\test.x3d')
  end

  unless file_loaded?(__FILE__)
    UI.menu.add_item('Export X3D') {
      export_x3d
    }

    file_loaded(__FILE__)
  end
end
