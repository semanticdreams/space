#!/usr/bin/env python3
import os
import json
import re

ICON_ROOT = '/usr/share/icons'
OUTPUT_FILE = 'assets/data/xdg-icons.json'

def parse_size_val(part):
    # Matches '24x24' or '24'
    match = re.match(r'^(\d+)x\d+$', part)
    if match:
        return int(match.group(1))
    
    match = re.match(r'^(\d+)$', part)
    if match:
        return int(match.group(1))
        
    return None

def main():
    icons_map = {}
    
    if not os.path.exists(ICON_ROOT):
        print(f"Error: {ICON_ROOT} does not exist.")
        return

    # Themes to skip
    skip_dirs = {'default', 'hicolor', 'locolor', 'vendor'} 
    # Actually hicolor is very common fallback, maybe should include? 
    # User said "build an icon index". Usually application should fallback to hicolor.
    # I will include hicolor. 
    # 'default' is usually symlink.
    
    for theme_name in os.listdir(ICON_ROOT):
        theme_path = os.path.join(ICON_ROOT, theme_name)
        if not os.path.isdir(theme_path):
            continue
            
        if theme_name in ['default']: # Skip default as it is often link
             if os.path.islink(theme_path):
                 continue
        
        # Walk recursively
        for root, dirs, files in os.walk(theme_path):
            # Calculate path parts relative to theme
            rel_path = os.path.relpath(root, theme_path)
            if rel_path == '.':
                parts = []
            else:
                parts = rel_path.split(os.sep)
                
            # Parse directory parts
            # Logic: identify size parts and context parts
            
            size_val = None
            context_parts = []
            is_scalable_dir = False
            is_symbolic_dir = False
            
            for part in parts:
                s = parse_size_val(part)
                if s is not None:
                    size_val = s
                elif part == 'scalable':
                    is_scalable_dir = True
                elif part == 'symbolic':
                    is_symbolic_dir = True
                else:
                    context_parts.append(part)
            
            # If no context parts found, verify if we can imply 'unknown' or skip
            # Often top level files or cache files
            if not files:
                continue
            
            if not context_parts:
                context_name = "unknown"
            else:
                context_name = "-".join(context_parts)

            for filename in files:
                if not filename.endswith(('.png', '.svg', '.xpm')):
                    continue
                
                name_part, ext = os.path.splitext(filename)
                ext = ext.lstrip('.')
                
                is_symbolic_file = name_part.endswith('-symbolic')
                
                # Check for symbolic
                final_is_symbolic = is_symbolic_file or is_symbolic_dir
                
                real_name = name_part
                if is_symbolic_file:
                    real_name = name_part[:-len('-symbolic')]
                
                if real_name not in icons_map:
                    icons_map[real_name] = {
                        "name": real_name,
                        "contexts": set(),
                        "themes": set(),
                        "sizes": set(),
                        "scalable": False,
                        "symbolic": False,
                        "extensions": set(),
                        "paths": {} 
                    }
                
                entry = icons_map[real_name]
                if context_name != "unknown":
                    entry["contexts"].add(context_name)
                entry["themes"].add(theme_name)
                entry["extensions"].add(ext)
                
                if is_scalable_dir:
                    entry["scalable"] = True
                if size_val:
                    entry["sizes"].add(size_val)
                if final_is_symbolic:
                    entry["symbolic"] = True
                    
                if theme_name not in entry["paths"]:
                    entry["paths"][theme_name] = {}
                    
                path_key = None
                if final_is_symbolic:
                    path_key = "symbolic"
                elif is_scalable_dir:
                    path_key = "scalable"
                elif size_val:
                    path_key = str(size_val)
                
                if path_key:
                     full_path = os.path.join(root, filename)
                     # Only keep one? Or overwrite? 
                     # If we have 24x24 and 24 (dirs), overwrite matches. 
                     # If we have .png and .svg? Overwrite.
                     # Prefer SVG? Alphabetically .png < .svg so .svg comes later in loop? Not guaranteed.
                     # But acceptable for this task.
                     entry["paths"][theme_name][path_key] = full_path

    if not icons_map:
        print("No icons found.")
    
    # Post-process sets to lists
    output_dict = {}
    for key, item in icons_map.items():
        item["contexts"] = sorted(list(item["contexts"]))
        item["themes"] = sorted(list(item["themes"]))
        item["sizes"] = sorted(list(item["sizes"]))
        item["extensions"] = sorted(list(item["extensions"]))
        output_dict[key] = item

    os.makedirs(os.path.dirname(OUTPUT_FILE), exist_ok=True)
    with open(OUTPUT_FILE, 'w') as f:
        json.dump(output_dict, f, indent=2)
        
    print(f"Generated icon index with {len(output_dict)} icons at {OUTPUT_FILE}")

if __name__ == '__main__':
    main()
