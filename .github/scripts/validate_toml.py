#!/usr/bin/env python3
"""TOML configuration files validator with enhanced checks"""

import tomli
import sys
import glob
import os

def validate_starship_config(data, filepath):
    """Validate Starship-specific configuration"""
    print(f"  🔍 Performing Starship-specific validation...")
    
    # Check for common Starship sections
    valid_sections = [
        'format', 'right_format', 'continuation_prompt', 'scan_timeout',
        'command_timeout', 'add_newline', 'aws', 'azure', 'battery',
        'character', 'cmake', 'cmd_duration', 'conda', 'crystal',
        'dart', 'directory', 'docker_context', 'dotnet', 'elixir',
        'elm', 'env_var', 'erlang', 'gcloud', 'git_branch', 'git_commit',
        'git_state', 'git_status', 'golang', 'helm', 'hostname',
        'java', 'jobs', 'julia', 'kubernetes', 'line_break', 'lua',
        'memory_usage', 'nim', 'nix_shell', 'nodejs', 'ocaml',
        'package', 'perl', 'php', 'python', 'red', 'ruby', 'rust',
        'scala', 'shell', 'shlvl', 'status', 'swift', 'terraform',
        'time', 'username', 'vagrant', 'zig'
    ]
    
    warnings = []
    
    # Check for potentially invalid keys
    for key in data.keys():
        if key not in valid_sections:
            warnings.append(f"Unknown section '{key}' - may not be supported by Starship")
    
    # Check format string if present
    if 'format' in data:
        format_str = data['format']
        if isinstance(format_str, str):
            if not format_str.strip():
                warnings.append("Empty format string detected")
            # Basic format validation
            if '$' not in format_str and len(format_str) > 0:
                warnings.append("Format string may be missing module references (no $ found)")
    
    # Check character section
    if 'character' in data and isinstance(data['character'], dict):
        char_config = data['character']
        if 'success_symbol' in char_config and 'error_symbol' in char_config:
            print("  ✅ Character symbols configured")
    
    if warnings:
        print(f"  ⚠️  Starship validation warnings:")
        for warning in warnings:
            print(f"    - {warning}")
    else:
        print(f"  ✅ Starship configuration looks good")
    
    return len(warnings) == 0

def validate_toml_file(filepath):
    """Validate a single TOML file"""
    print(f'Validating {filepath}')
    
    try:
        with open(filepath, 'rb') as f:
            data = tomli.load(f)
        print(f'  ✅ Valid TOML syntax')
        
        # Perform file-specific validation
        filename = os.path.basename(filepath)
        
        if filename == 'starship.toml':
            validate_starship_config(data, filepath)
        
        print(f'✅ {filepath} validation complete')
        return True
        
    except Exception as e:
        print(f'❌ Invalid TOML in {filepath}: {e}')
        return False

def main():
    toml_files = glob.glob('configs/**/*.toml', recursive=True)
    
    if not toml_files:
        print('No TOML files found to validate')
        return 0
    
    print(f"Found {len(toml_files)} TOML file(s) to validate")
    
    all_valid = True
    for file in toml_files:
        if not validate_toml_file(file):
            all_valid = False
        print()  # Add spacing between files
    
    if all_valid:
        print('🎉 All TOML files are valid and well-configured!')
        return 0
    else:
        print('❌ Some TOML files have issues')
        return 1

if __name__ == '__main__':
    sys.exit(main())