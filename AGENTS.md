# Repository instructions

## Chart releases

Treat each chart directory as an independently versioned release artifact.

When runtime-effective chart contents change, including `Chart.yaml`, `Chart.lock`, `.helmignore`, `values.yaml`,
`values.schema.json`, or files under `templates/`, `files/`, `crds/`, or `charts/`:

- Increment the chart's `Chart.yaml` `version` according to Semantic Versioning.
- Replace the `artifacthub.io/changes` annotation with concise, user-facing entries for the new chart version. The
  annotation describes only that version; do not retain entries from the previous version.
- Use structured entries with one of these kinds: `added`, `changed`, `deprecated`, `removed`, `fixed`, or `security`.
- Mention application-image and chart-dependency updates when they are the reason for the chart release.
- Omit CI maintenance, formatting, refactoring, and documentation-only changes from public release notes.
- Add or update the chart's `UPGRADE.md` when users must take manual action or the release contains a breaking change.

Example:

```yaml
annotations:
  artifacthub.io/changes: |
    - kind: fixed
      description: Preserve the configured replica count during upgrades
    - kind: changed
      description: Update the default application image to 2.4.0
```

Existing charts without this annotation adopt it on their next version bump; do not invent historical entries or
republish an existing version solely to add the annotation.

A change to the `common` library chart requires its own version bump. Bump a consuming chart only when its committed
dependency lock or packaged dependency changes; that consuming release must describe the resulting user-visible change.

## Generated catalog

The chart table in `README.md` is generated from chart metadata and must not be edited manually. After changing a chart
name, version, or default image registry or repository, run:

```sh
ruby scripts/update-readme.rb
```

Generic `stateful` and `stateless` charts intentionally use `configurable` as their catalog image. Keep exceptional
display values in `scripts/update-readme.rb` rather than manually changing the generated table.

## Validation

Before finishing chart or release-metadata changes, run:

```sh
ruby scripts/update-readme.rb --check
ruby scripts/validate-release-metadata.rb
ruby scripts/validate-charts.rb
```

CI supplies a Git base reference to release-metadata validation so it can require a version bump for runtime-effective
changes and require new release notes for every changed version.
