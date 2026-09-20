# Upgrade to 0.4.0

The default image now uses the maintained `wodby/vinyl:6.0-r0` image. The chart name, workload names, and value paths remain unchanged.

If your values explicitly set `image.repository: wodby/varnish`, update the repository to `wodby/vinyl` and the tag to `6.0-r0` to adopt this revision. Review custom VCL and smoke-test cache behavior before upgrading.
