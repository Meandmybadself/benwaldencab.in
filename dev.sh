#!/bin/bash

# Get the local IP address
LOCAL_IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "127.0.0.1")

# Start a simple server on port 8000, accessible from network
echo "Starting server..."
echo "Local access: http://localhost:8000"
echo "Network access: http://$LOCAL_IP:8000"
echo ""
echo "Other devices on your network can access the site at: http://$LOCAL_IP:8000"

python3 -m http.server 8000 --bind 0.0.0.0 > /dev/null 2>&1 &

# Open the URL in the default browser
open "http://localhost:8000"

# Keep the script running
while true; do
    sleep 1
done