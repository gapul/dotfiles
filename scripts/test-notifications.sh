#!/usr/bin/env bash
# WezTerm Notification Test Script
set -euo pipefail

echo "🔔 Testing WezTerm notification system..."
echo "=================================="

# Test 1: Basic bell notification
echo "Test 1: Basic bell notification"
printf '\a'
echo "   ✅ Bell sent (should show toast notification)"
sleep 2

# Test 2: Custom notification message  
echo "Test 2: Custom notification message"
printf '\e]9;%s\e\\' "Custom test notification message"
echo "   ✅ Custom message sent"
sleep 2

# Test 3: Command completion simulation
echo "Test 3: Simulating command completion"
start_time=$SECONDS
sleep 4  # Simulate 4-second command
elapsed=$((SECONDS - start_time))
printf '\a'
printf '\e]9;%s\e\\' "Test command completed in ${elapsed}s"
echo "   ✅ Command completion notification sent"
sleep 2

# Test 4: Using notify wrapper
echo "Test 4: Testing notify wrapper function"
if command -v notify &> /dev/null; then
    notify sleep 2
    echo "   ✅ notify wrapper test completed"
else
    echo "   ⚠️  notify function not available (reload shell first)"
fi

# Test 5: Direct WezTerm command (if available)
echo "Test 5: Direct WezTerm notification command"
if command -v wezterm &> /dev/null; then
    wezterm cli send-text --no-paste $'\a'
    echo "   ✅ Direct WezTerm command sent"
else
    echo "   ⚠️  wezterm CLI not available"
fi

echo ""
echo "🎉 Notification tests completed!"
echo "If notifications didn't appear, check:"
echo "  1. Terminal is WezTerm"
echo "  2. macOS notifications are enabled for WezTerm"
echo "  3. WezTerm configuration is loaded"
echo "  4. Shell configuration is reloaded (restart terminal)"