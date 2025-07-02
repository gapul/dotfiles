#!/bin/bash
# JankyBorders Startup Script
# Poimandres-themed window borders for enhanced visual feedback

# Kill existing borders instance
killall borders 2>/dev/null

# Wait a moment for cleanup
sleep 0.5

# Start borders with Poimandres theme colors (corrected options)
borders \
  active_color=0xff5de4c7 \
  inactive_color=0xff505168 \
  width=3.0 \
  style=round \
  hidpi=on \
  blacklist="Finder,System Preferences,Activity Monitor,Calculator" \
  &

echo "JankyBorders started with Poimandres theme"