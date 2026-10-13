import os
import sys

def read_obj(file_path):
    vertices = []
    tex_coords = []
    normals = []
    faces = []
    objects = []
    materials = []
    current_mtl = None
    
    with open(file_path, 'r') as file:
        for line in file:
            line = line.strip()
            if not line:
                continue
            
            parts = line.split()
            if not parts:
                continue
            
            # 处理顶点数据
            if parts[0] == 'v':
                vertices.append(list(map(float, parts[1:4])))
            elif parts[0] == 'vt':
                tex_coords.append(list(map(float, parts[1:3])))
            elif parts[0] == 'vn':
                normals.append(list(map(float, parts[1:4])))
            
            # 处理面和结构
            elif parts[0] == 'f':
                face = []
                for vertex in parts[1:]:
                    indices = vertex.split('/')
                    # 将索引转为整数（OBJ索引从1开始）
                    v = int(indices[0]) - 1 if indices[0] else None
                    vt = int(indices[1]) - 1 if len(indices) > 1 and indices[1] else None
                    vn = int(indices[2]) - 1 if len(indices) > 2 and indices[2] else None
                    face.append((v, vt, vn))
                faces.append({
                    'vertices': face,
                    'object': objects[-1] if objects else None,
                    'usemtl': current_mtl
                })
            elif parts[0] == 'o':
                objects.append(parts[1])
            elif parts[0] == 'usemtl':
                current_mtl = parts[1]
                materials.append(current_mtl)
    
    return {
        'vertices': vertices,
        'tex_coords': tex_coords,
        'normals': normals,
        'faces': faces,
        'objects': objects,
        'materials': materials
    }

def triangulate_face(face_vertices):
    triangles = []
    # 更智能的四边形三角化（保持顶点顺序）
    if len(face_vertices) == 4:
        # 四边形分解为两个三角形：[0,1,2] + [0,2,3]
        triangles.append([face_vertices[0], face_vertices[1], face_vertices[2]])
        triangles.append([face_vertices[0], face_vertices[2], face_vertices[3]])
        triangles.append([face_vertices[0], face_vertices[1], face_vertices[3]])
    else:
        # 处理多边形（n > 4）
        for i in range(1, len(face_vertices)-1):
            triangles.append([face_vertices[0], face_vertices[i], face_vertices[i+1]])
    return triangles

def write_obj(file_path, data, triangulated_faces):
    with open(file_path, 'w') as file:
        # 写入顶点数据
        for v in data['vertices']:
            file.write(f"v {' '.join(map(str, v))}\n")
        for vt in data['tex_coords']:
            file.write(f"vt {' '.join(map(str, vt))}\n")
        for vn in data['normals']:
            file.write(f"vn {' '.join(map(str, vn))}\n")
        
        # 写入对象和面数据
        current_object = None
        current_mtl = None
        for face_info in triangulated_faces:
            # 处理对象切换
            if face_info['object'] != current_object:
                current_object = face_info['object']
                file.write(f"o {current_object}\n")
            
            # 处理材质切换
            if face_info['usemtl'] != current_mtl:
                current_mtl = face_info['usemtl']
                file.write(f"usemtl {current_mtl}\n")
            
            # 写入三角化后的面
            for triangle in face_info['triangles']:
                face_line = "f "
                for v_data in triangle:
                    v_str = []
                    if v_data[0] is not None:
                        v_str.append(str(v_data[0] + 1))
                    if v_data[1] is not None or v_data[2] is not None:
                        vt_str = str(v_data[1] + 1) if v_data[1] is not None else ''
                        vn_str = str(v_data[2] + 1) if v_data[2] is not None else ''
                        v_str.append(f"{vt_str}/{vn_str}")
                    face_line += '/'.join(v_str) + ' '
                file.write(face_line.strip() + '\n')

def main(input_file):
    # 读取原始数据
    data = read_obj(input_file)
    
    # 三角化所有面
    triangulated_faces = []
    for face in data['faces']:
        triangles = triangulate_face(face['vertices'])
        triangulated_faces.append({
            'object': face['object'],
            'usemtl': face['usemtl'],
            'triangles': triangles
        })
    
    # 生成新文件名
    base_name, _ = os.path.splitext(input_file)
    output_file = f"{base_name}.obj"
    
    # 重命名原文件
    os.rename(input_file, f"{base_name}_old.obj")

    # 写入新文件
    write_obj(output_file, data, triangulated_faces)
    
    print(f"Conversion complete. Original file renamed to {base_name}_old.obj")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Drag OBJ file onto this script to convert.")
    else:
        input_file = sys.argv[1]
        if input_file.endswith('.obj'):
            main(input_file)
        else:
            print("Invalid file type. Only .obj files are supported.")