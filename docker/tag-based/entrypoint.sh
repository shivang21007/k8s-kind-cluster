#!/bin/sh

# Replace placeholders with real runtime values
sed -i "s/__POD_NAME__/$POD_NAME/g" /usr/share/nginx/html/index.html
sed -i "s/__IMAGE_TAG_/$IMAGE_TAG/g" /usr/share/nginx/html/index.html
sed -i "s/__TIME__/$(date)/g" /usr/share/nginx/html/index.html

# Start nginx
nginx -g "daemon off;"
