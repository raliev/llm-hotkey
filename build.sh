#!/bin/bash
cd "$(dirname "$0")"
swiftc -O -o text_hotkey text_hotkey.swift -framework Cocoa -framework Carbon -framework CoreGraphics -framework AVFoundation -framework NaturalLanguage 2>&1
