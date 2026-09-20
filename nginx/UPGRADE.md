# Upgrade to 0.4.0

The default image changes from Nginx 1.25 to `wodby/nginx:1.30-r0` because the 1.25 image line is no longer maintained.

Check custom Nginx configuration against 1.30 before upgrading. An explicit `image.tag` value continues to override the chart default.
