#!/bin/bash

echo "Testing Claude Manager Interactive Mode"
echo "========================================"
echo ""
echo "1. Testing TTY detection:"
if [ -t 0 ] && [ -t 1 ]; then
    echo "   ✓ TTY detected - interactive mode should work"
else
    echo "   ✗ No TTY detected - will use simple mode"
fi

echo ""
echo "2. Testing with --debug flag:"
claude-manager --debug 2>&1 | head -15

echo ""
echo "3. To launch interactive mode manually, run:"
echo "   claude-manager --interactive"
echo ""
echo "4. In interactive mode, use these keys:"
echo "   ↑/↓ or j/k  - Navigate"
echo "   Enter       - View conversation"
echo "   /           - Search"
echo "   ESC or q    - Quit"