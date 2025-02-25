#!/usr/bin/env python3
import os
import re
import sys

def find_includes(file_path):
    """Find all include statements in a file"""
    includes = []
    try:
        with open(file_path, 'r') as f:
            for line in f:
                match = re.search(r'#include [<"](.+?)[>"]', line)
                if match:
                    includes.append(match.group(1))
    except Exception as e:
        print(f"Cannot read file {file_path}: {e}")
    return includes

def build_dependency_dict(directory):
    """Build dependency dictionary"""
    dependencies = {}
    file_map = {}
    
    # Get all device tree files
    dts_files = []
    for root, _, files in os.walk(directory):
        for file in files:
            if file.endswith('.dts') or file.endswith('.dtsi'):
                full_path = os.path.join(root, file)
                dts_files.append(full_path)
                file_map[file] = full_path
    
    # Analyze dependencies
    for file_path in dts_files:
        file_name = os.path.basename(file_path)
        includes = find_includes(file_path)
        dependencies[file_name] = includes
    
    return dependencies, file_map

def print_tree(dependencies, root_file, indent="", visited=None, file_to_id=None):
    """Recursively print dependency tree"""
    if visited is None:
        visited = set()
    
    if root_file in visited:
        print(f"{indent}└── #{file_to_id.get(root_file, '?')} {root_file} (Circular dependency, shown above)")
        return
    
    visited.add(root_file)
    print(f"{indent}└── #{file_to_id.get(root_file, '?')} {root_file}")
    
    if root_file in dependencies:
        new_indent = indent + "    "
        for include in dependencies[root_file]:
            print_tree(dependencies, include, new_indent, visited.copy(), file_to_id)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        directory = "."
    else:
        directory = sys.argv[1]
        
    dependencies, file_map = build_dependency_dict(directory)
    
    # Create file ID mapping
    all_files = sorted(dependencies.keys())
    file_to_id = {file: idx+1 for idx, file in enumerate(all_files)}
    
    # Group files based on dependencies
    files_with_deps = {}
    files_no_deps = {}
    
    for file, deps in dependencies.items():
        if deps:
            files_with_deps[file] = deps
        else:
            files_no_deps[file] = deps
    
    # Print DTS structure header
    print("# Device Tree Files Analysis Report")
    print()
    print("## Overall Statistics")
    print(f"**Total Files: {len(dependencies)}**")
    print(f"**Files with Dependencies: {len(files_with_deps)}**")
    print(f"**Files without Dependencies: {len(files_no_deps)}**")
    print()
    
    # Print explanation of DTS and DTSI
    print("## What are DTS and DTSI files?")
    print("- **DTS** (Device Tree Source): Main device tree files that describe complete hardware")
    print("- **DTSI** (Device Tree Source Include): Reusable fragments meant to be included by DTS files")
    print()
    
    # Print file list with IDs
    print("## File ID Reference")
    print()
    for file, file_id in file_to_id.items():
        file_type = "DTS" if file.endswith(".dts") else "DTSI"
        print(f"#{file_id}: {file} ({file_type})")
    print()
    
    # Print files without dependencies
    print("## Files without Dependencies")
    print()
    for file in sorted(files_no_deps.keys()):
        print(f"#{file_to_id[file]} {file}")
    print()
    
    # Print files with dependencies
    print("## Files with Dependencies")
    print()
    for file in sorted(files_with_deps.keys()):
        deps = files_with_deps[file]
        deps_str = ", ".join([f"#{file_to_id.get(d, '?')} {d}" for d in deps])
        print(f"#{file_to_id[file]} {file} depends on: {deps_str}")
    print()
    
    # Print tree structure
    print("## Dependency Tree Structure")
    print()
    
    # Find the root DTS files
    included_files = set()
    for deps in dependencies.values():
        included_files.update(deps)
        
    root_files = [f for f in dependencies.keys() if f.endswith('.dts') and f not in included_files]
    
    if not root_files:
        # If no clear root files found, use all .dts files
        root_files = [f for f in dependencies.keys() if f.endswith('.dts')]
    
    for root in root_files:
        print_tree(dependencies, root, "", None, file_to_id)
        print()
