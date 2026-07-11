# Raw: values.yaml — security context defaults

Provenance: verbatim copy of `platform-library/values.yaml` lines 457-485, taken 2026-07-10 at HEAD 4fb9386 (branch handover/2026-07-10). Not edited.

```yaml
    # -----------------------------------------------------------------------------
    # Security Context
    # -----------------------------------------------------------------------------
    # Enabled by default. The zero-config output targets the Pod Security
    # Standards "restricted" profile: runAsNonRoot, no privilege escalation,
    # all capabilities dropped, RuntimeDefault seccomp, read-only root
    # filesystem. Set enabled: false on either block to opt out entirely, or
    # override individual fields (e.g. readOnlyRootFilesystem: false for apps
    # that write to their root filesystem; use extraVolumes/extraVolumeMounts
    # with an emptyDir for scratch space instead where possible).
    # Every key except `enabled` is rendered verbatim into the manifest.
    podSecurityContext:
      enabled: true
      fsGroup: 1001
      runAsNonRoot: true
      seccompProfile:
        type: RuntimeDefault

    containerSecurityContext:
      enabled: true
      runAsUser: 1001
      runAsNonRoot: true
      readOnlyRootFilesystem: true
      allowPrivilegeEscalation: false
      capabilities:
        drop:
          - ALL
      seccompProfile:
        type: RuntimeDefault
```
