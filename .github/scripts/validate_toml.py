#!/usr/bin/env python3
"""TOML configuration files validator"""

import tomli
import sys
import glob

def main():
    toml_files = glob.glob('configs/**/*.toml', recursive=True)
    
    if not toml_files:
        print('No TOML files found to validate')
        return 0
    
    for file in toml_files:
        print(f'Validating {file}')
        try:
            with open(file, 'rb') as f:
                tomli.load(f)
            print(f'✅ {file} is valid TOML')
        except Exception as e:
            print(f'❌ Invalid TOML in {file}: {e}')
            return 1
    
    print('All TOML files are valid')
    return 0

if __name__ == '__main__':
    sys.exit(main())