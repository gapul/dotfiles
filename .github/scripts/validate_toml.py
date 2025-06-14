#!/usr/bin/env python3
"""TOML configuration files validator with enhanced checks"""

import tomli
import sys
import glob
import os

def validate_starship_config(data, filepath):
    """Validate Starship-specific configuration with enhanced checks"""
    print(f"  🔍 Performing Starship-specific validation...")
    
    # Check for common Starship sections (updated for latest Starship version)
    valid_sections = [
        # Core configuration
        'format', 'right_format', 'continuation_prompt', 'scan_timeout',
        'command_timeout', 'add_newline', 'follow_symlinks', '$schema',
        'palettes', 'profiles',
        # Language and tool modules
        'aws', 'azure', 'battery', 'buf', 'bun', 'c', 'character', 'cmake',  
        'cmd_duration', 'cobol', 'conda', 'container', 'crystal', 'daml',
        'dart', 'deno', 'directory', 'direnv', 'docker_context', 'dotnet',
        'elixir', 'elm', 'env_var', 'erlang', 'fennel', 'fill',
        # Version control
        'fossil_branch', 'fossil_metrics', 'gcloud', 'git_branch', 'git_commit',
        'git_metrics', 'git_state', 'git_status', 'gleam', 'golang', 'gradle',
        'guix_shell', 'haskell', 'haxe', 'helm', 'hg_branch', 'hostname',
        # More language modules
        'java', 'jobs', 'julia', 'kotlin', 'kubernetes', 'line_break',
        'localip', 'lua', 'memory_usage', 'meson', 'mojo', 'nats', 'nim',
        'nix_shell', 'nodejs', 'ocaml', 'odin', 'opa', 'openstack', 'os',
        'package', 'perl', 'php', 'pijul_channel', 'pulumi', 'purescript',
        'python', 'quarto', 'raku', 'red', 'rlang', 'ruby', 'rust',
        'scala', 'shell', 'shlvl', 'singularity', 'solidity', 'spack',
        'status', 'sudo', 'swift', 'terraform', 'time', 'typst',
        'username', 'vagrant', 'vcsh', 'vlang', 'zig'
    ]
    
    warnings = []
    errors = []
    
    # Check for potentially invalid keys
    for key in data.keys():
        if key not in valid_sections:
            warnings.append(f"Unknown section '{key}' - may not be supported by Starship")
    
    # Validate core configuration values
    if 'scan_timeout' in data:
        timeout = data['scan_timeout']
        if not isinstance(timeout, int) or timeout < 0 or timeout > 1000:
            warnings.append(f"scan_timeout ({timeout}) should be between 0-1000ms")
    
    if 'command_timeout' in data:
        timeout = data['command_timeout']
        if not isinstance(timeout, int) or timeout < 0 or timeout > 10000:
            warnings.append(f"command_timeout ({timeout}) should be between 0-10000ms")
    
    # Validate format strings
    for format_key in ['format', 'right_format', 'continuation_prompt']:
        if format_key in data:
            format_str = data[format_key]
            if isinstance(format_str, str):
                if not format_str.strip():
                    warnings.append(f"Empty {format_key} string detected")
                # Check for valid module references
                if format_key in ['format', 'right_format'] and '$' not in format_str and len(format_str) > 0:
                    warnings.append(f"{format_key} may be missing module references (no $ found)")
    
    # Validate style configurations
    def validate_style(style_value, module_name):
        if isinstance(style_value, str):
            valid_colors = ['black', 'red', 'green', 'yellow', 'blue', 'purple', 'cyan', 'white', 
                          'bright-black', 'bright-red', 'bright-green', 'bright-yellow', 
                          'bright-blue', 'bright-purple', 'bright-cyan', 'bright-white']
            valid_styles = ['bold', 'italic', 'underline', 'strikethrough', 'dimmed', 'inverted', 'blink']
            
            parts = style_value.split()
            for part in parts:
                if part not in valid_colors and part not in valid_styles and not part.startswith('#') and not part.startswith('rgb('):
                    warnings.append(f"{module_name}: potentially invalid style '{part}' in '{style_value}'")
    
    # Check module-specific configurations
    for section_name, section_data in data.items():
        if isinstance(section_data, dict):
            # Check common module properties
            if 'style' in section_data:
                validate_style(section_data['style'], section_name)
            
            if 'disabled' in section_data and not isinstance(section_data['disabled'], bool):
                warnings.append(f"{section_name}: 'disabled' should be a boolean value")
            
            if 'format' in section_data:
                format_str = section_data['format']
                if isinstance(format_str, str) and not format_str.strip():
                    warnings.append(f"{section_name}: empty format string")
    
    # Check character section specifically
    if 'character' in data and isinstance(data['character'], dict):
        char_config = data['character']
        if 'success_symbol' in char_config and 'error_symbol' in char_config:
            print("  ✅ Character symbols configured")
        
        # Validate symbol lengths (avoid overly long symbols)
        for symbol_key in ['success_symbol', 'error_symbol', 'vimcmd_symbol']:
            if symbol_key in char_config:
                symbol = char_config[symbol_key]
                if isinstance(symbol, str) and len(symbol) > 10:
                    warnings.append(f"character.{symbol_key} is quite long ({len(symbol)} chars)")
    
    # Check for performance recommendations
    checks_passed = 0
    total_checks = 0
    
    # Performance check: scan_timeout
    if 'scan_timeout' in data:
        total_checks += 1
        if data['scan_timeout'] <= 30:
            checks_passed += 1
        else:
            warnings.append("Consider reducing scan_timeout for better performance")
    
    # Performance check: disabled unused modules
    total_checks += 1
    disabled_count = 0
    for section_name, section_data in data.items():
        if isinstance(section_data, dict) and section_data.get('disabled', False):
            disabled_count += 1
    
    if disabled_count > 0:
        checks_passed += 1
        print(f"  ✅ Performance: {disabled_count} unused modules disabled")
    else:
        warnings.append("Consider disabling unused modules for better performance")
    
    # Report validation results
    if errors:
        print(f"  ❌ Starship validation errors:")
        for error in errors:
            print(f"    - {error}")
    
    if warnings:
        print(f"  ⚠️  Starship validation warnings:")
        for warning in warnings:
            print(f"    - {warning}")
    
    if not errors and not warnings:
        print(f"  ✅ Starship configuration looks perfect!")
    elif not errors:
        print(f"  ✅ Starship configuration is valid with {len(warnings)} suggestions")
    
    # Performance summary
    if total_checks > 0:
        perf_score = (checks_passed / total_checks) * 100
        print(f"  📊 Performance score: {perf_score:.0f}% ({checks_passed}/{total_checks} checks passed)")
    
    return len(errors) == 0

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
    import time
    start_time = time.time()
    
    toml_files = glob.glob('configs/**/*.toml', recursive=True)
    
    if not toml_files:
        print('No TOML files found to validate')
        return 0
    
    print(f"🔍 TOML Configuration Validator")
    print(f"Found {len(toml_files)} TOML file(s) to validate")
    print("=" * 50)
    
    all_valid = True
    total_warnings = 0
    total_errors = 0
    validation_results = []
    
    for file in toml_files:
        file_start = time.time()
        result = validate_toml_file(file)
        file_duration = time.time() - file_start
        
        # Extract warnings/errors count from output (simplified approach)
        validation_results.append({
            'file': file,
            'valid': result,
            'duration': file_duration
        })
        
        if not result:
            all_valid = False
        print()  # Add spacing between files
    
    # Summary section
    total_duration = time.time() - start_time
    print("=" * 50)
    print(f"📊 VALIDATION SUMMARY")
    print(f"Total files: {len(toml_files)}")
    print(f"Valid files: {sum(1 for r in validation_results if r['valid'])}")
    print(f"Files with issues: {sum(1 for r in validation_results if not r['valid'])}")
    print(f"Total validation time: {total_duration:.2f}s")
    
    if all_valid:
        print('🎉 All TOML files are valid and well-configured!')
        return 0
    else:
        print('❌ Some TOML files have validation issues')
        return 1

if __name__ == '__main__':
    sys.exit(main())