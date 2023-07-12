# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

<!-- Add your changelog entry to the relevant subsection -->

<!-- ### Added | Changed | Deprecated | Removed | Fixed | Security -->

<!-- No new entries below this line! -->

## [0.2.0] - 2023-07-12

TLS secret creation: use keys that correlate with keys in secrets created by cert-manager [#17](https://github.com/mruoss/k8s_webhoox/pull/17)

## [0.1.1] - 2023-06-02

### Fixed

- `K8sWebhoox.AdmissionControl.AdmissionReview.check_immutable/2` - only check `UPDATE` operations.

### Changed

- `K8sWebhoox.AdmissionControl.AdmissionReview.check_allowed_values/4` - Add `field_name` used for error message.

### Added

- TLS Bootstrap - Renews certificates if they expire within 30 days from now - [#5](https://github.com/mruoss/k8s_webhoox/pull/5)

## [0.1.0] - 2023-04-09

This is the first release.
