#!/usr/bin/env python3
"""Test Python project for nix environment."""

import sys
import json

def main():
    print(f"Python version: {sys.version}")
    print(f"Python executable: {sys.executable}")
    
    # Test basic functionality
    data = {"message": "Hello from nix-managed Python!", "version": sys.version_info[:2]}
    print(json.dumps(data, indent=2))

if __name__ == "__main__":
    main()