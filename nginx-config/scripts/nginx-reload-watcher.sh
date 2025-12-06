#!/bin/bash

cd /etc/nginx/reload || exit 1

# Watch for create events permanently, process output in a loop
inotifywait -m -e create . | while read -r directory event filename; do
    # Check if the created file is .reload_signal
    echo "Receive $filename create event..."
    if [ "$filename" = ".signal" ]; then
        # Read the content of .reload_signal (if any)
        if [ -s .signal ]; then
            echo "Reading .signal content: $(cat .signal)"
        else
            echo "No content in .signal"
        fi

        # Reload NGINX
        systemctl reload nginx  # Use sudo systemctl reload nginx for system service

        # Remove the signal file
        rm .signal
    fi
done
