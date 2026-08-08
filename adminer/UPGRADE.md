# Upgrade to 0.2.0

Chart 0.2.0 upgrades the default application image from Adminer 5 to Adminer 6.

If `ADMINER_PLUGINS` is configured, review it before upgrading. Adminer 6 removes the `edit-calendar`, `tinymce`, `json-column`, `pretty-json-column`, `translation`, `email-table`, `dump-php`, and `master-slave` plugins and changes parts of the plugin API. Remove unavailable plugins and verify custom plugin compatibility with Adminer 6.

No manual action is required for installations that do not configure plugins.
