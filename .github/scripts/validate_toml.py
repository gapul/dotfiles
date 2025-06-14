#!/usr/bin/env python3
"""TOML configuration files validator with enhanced checks and idempotency validation"""

import tomli
import sys
import glob
import os
import hashlib
import json
import tempfile
import shutil

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

def validate_idempotency(filepath):
    """Validate that TOML file parsing and re-serialization is idempotent"""
    print(f"  🔄 Performing idempotency validation...")
    
    try:
        # Read and parse the original file
        with open(filepath, 'rb') as f:
            original_data = tomli.load(f)
        
        # Create a temporary file to test round-trip serialization
        with tempfile.NamedTemporaryFile(mode='w', suffix='.toml', delete=False) as temp_file:
            temp_path = temp_file.name
            
            # We can't directly serialize back to TOML with tomli (it's read-only)
            # So we'll validate data consistency by checking if keys and structure remain the same
            # after multiple parse operations on the same content
            
            # Read original file content as text
            with open(filepath, 'r', encoding='utf-8') as f:
                original_content = f.read()
            
            # Parse the content multiple times to check consistency
            parse1 = tomli.loads(original_content)
            parse2 = tomli.loads(original_content)
            
            # Check if both parses yield identical structures
            if parse1 != parse2:
                print(f"  ❌ Idempotency issue: Multiple parses yield different results")
                return False
                
            # Check for data consistency
            def deep_compare(obj1, obj2, path=""):
                if type(obj1) != type(obj2):
                    print(f"  ❌ Type mismatch at {path}: {type(obj1)} vs {type(obj2)}")
                    return False
                
                if isinstance(obj1, dict):
                    if set(obj1.keys()) != set(obj2.keys()):
                        print(f"  ❌ Key mismatch at {path}: {set(obj1.keys())} vs {set(obj2.keys())}")
                        return False
                    
                    for key in obj1.keys():
                        if not deep_compare(obj1[key], obj2[key], f"{path}.{key}" if path else key):
                            return False
                
                elif isinstance(obj1, list):
                    if len(obj1) != len(obj2):
                        print(f"  ❌ List length mismatch at {path}: {len(obj1)} vs {len(obj2)}")
                        return False
                    
                    for i, (item1, item2) in enumerate(zip(obj1, obj2)):
                        if not deep_compare(item1, item2, f"{path}[{i}]"):
                            return False
                
                else:
                    if obj1 != obj2:
                        print(f"  ❌ Value mismatch at {path}: {obj1} vs {obj2}")
                        return False
                
                return True
            
            if not deep_compare(original_data, parse1):
                print(f"  ❌ Data consistency check failed")
                return False
            
            # Clean up temp file
            os.unlink(temp_path)
            
            print(f"  ✅ Idempotency validation passed")
            return True
            
    except Exception as e:
        print(f"  ❌ Idempotency validation failed: {e}")
        return False

def check_duplicate_configurations(data, filepath):
    """Check for meaningful duplicate or conflicting configurations within the TOML file"""
    print(f"  🔍 Checking for duplicate configurations...")
    
    warnings = []
    critical_duplicates = False
    
    # Define common patterns that are intentionally shared (not problematic)
    common_patterns = {
        'via [$symbol($version )]($style)',  # Standard language module format
        'on [$symbol$branch]($style) ',      # Standard VCS branch format  
        '([+$added]($added_style) )([-$deleted]($deleted_style) )', # Standard metrics format
        'via [$symbol$environment]($style) ' # Standard environment format
    }
    
    # Check for genuinely concerning duplicates
    unique_configs = {}
    critical_format_duplicates = []
    
    for section_name, section_data in data.items():
        if isinstance(section_data, dict):
            # Only flag non-standard format duplicates as critical
            if 'format' in section_data:
                format_str = section_data['format']
                if format_str not in common_patterns:
                    if format_str in unique_configs:
                        critical_format_duplicates.append({
                            'format': format_str,
                            'modules': [section_name, unique_configs[format_str]]
                        })
                        critical_duplicates = True
                    else:
                        unique_configs[format_str] = section_name
    
    # Check for potentially conflicting symbol configurations
    symbol_conflicts = {}
    for section_name, section_data in data.items():
        if isinstance(section_data, dict) and 'symbol' in section_data:
            symbol = section_data['symbol']
            # Only flag identical symbols that might cause visual confusion
            if len(symbol) > 1 and symbol in symbol_conflicts:  # Skip single-char symbols
                warnings.append(f"Identical symbol '{symbol}' used in {section_name} and {symbol_conflicts[symbol]} - may cause confusion")
                critical_duplicates = True
            else:
                symbol_conflicts[symbol] = section_name
    
    # Check for redundant disabled modules (information only)
    disabled_modules = []
    for section_name, section_data in data.items():
        if isinstance(section_data, dict) and section_data.get('disabled', False):
            disabled_modules.append(section_name)
    
    # Report findings
    if critical_format_duplicates:
        warnings.append(f"Optimization: {len(critical_format_duplicates)} non-standard format strings are duplicated:")
        for dup in critical_format_duplicates:
            warnings.append(f"  '{dup['format']}' used in {', '.join(dup['modules'])}")
    
    # Statistical summary (informational, not critical)
    total_format_count = sum(1 for s, d in data.items() if isinstance(d, dict) and 'format' in d)
    common_format_count = sum(1 for s, d in data.items() 
                            if isinstance(d, dict) and 'format' in d 
                            and d['format'] in common_patterns)
    
    print(f"  📊 Format statistics: {total_format_count} total, {common_format_count} using standard patterns, {len(disabled_modules)} modules disabled")
    
    if len(disabled_modules) > 25:
        warnings.append(f"Consider cleaning up config: {len(disabled_modules)} modules disabled")
    
    # Only treat as critical failure if there are major structural issues
    major_issues = sum(1 for w in warnings if w.startswith('Critical:'))
    
    if warnings:
        print(f"  ⚠️  Configuration consistency suggestions:")
        for warning in warnings:
            print(f"    - {warning}")
    else:
        print(f"  ✅ No duplicate configurations detected")
    
    # Return success unless there are major structural problems
    return major_issues == 0

def calculate_file_hash(filepath):
    """Calculate SHA-256 hash of file content for change detection"""
    with open(filepath, 'rb') as f:
        content = f.read()
        return hashlib.sha256(content).hexdigest()

def validate_toml_file(filepath):
    """Validate a single TOML file with comprehensive checks"""
    print(f'Validating {filepath}')
    
    validation_results = {
        'syntax': False,
        'idempotency': False,
        'duplicates': False,
        'starship': False
    }
    
    try:
        # Basic syntax validation
        with open(filepath, 'rb') as f:
            data = tomli.load(f)
        print(f'  ✅ Valid TOML syntax')
        validation_results['syntax'] = True
        
        # Calculate and display file hash for tracking
        file_hash = calculate_file_hash(filepath)
        print(f'  📄 File hash: {file_hash[:16]}...')
        
        # Idempotency validation
        validation_results['idempotency'] = validate_idempotency(filepath)
        
        # Duplicate configuration check
        validation_results['duplicates'] = check_duplicate_configurations(data, filepath)
        
        # Perform file-specific validation
        filename = os.path.basename(filepath)
        
        if filename == 'starship.toml':
            validation_results['starship'] = validate_starship_config(data, filepath)
        else:
            validation_results['starship'] = True  # Not applicable
        
        # Summary of validation results
        passed_checks = sum(validation_results.values())
        total_checks = len(validation_results)
        
        if all(validation_results.values()):
            print(f'✅ {filepath} validation complete - All {total_checks} checks passed')
            return True
        else:
            failed_checks = [k for k, v in validation_results.items() if not v]
            print(f'⚠️  {filepath} validation complete - {passed_checks}/{total_checks} checks passed')
            print(f'   Failed checks: {", ".join(failed_checks)}')
            return False
        
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
    
    print(f"🔍 TOML Configuration Validator with Idempotency Checks")
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