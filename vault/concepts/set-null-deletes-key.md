# Concept: --set key=null deletes the key

In Helm, `--set foo=null` **removes** `foo` from the coalesced values — it does not set a literal null. This repo uses the idiom deliberately in [[lint-library-gate]]'s negative legs:

- `--set capabilities.apiVersions=null` (`scripts/lint-library.sh:260`) — deletes the force-assume list so CRD-backed Kinds must drop.
- `--set mtls.allowedPrincipals=null` (`:528`, with the explanatory comment at `:527`) — deletes the principal list so the mTLS fail-closed guardrail must trip.

Why it matters: a reader who parses these as "set to null" misreads the tests as checking null-handling rather than absent-key handling, and may "fix" values plumbing that is working correctly. It is also the right tool when a negative test needs to simulate a consumer who omitted a key that fixtures set.

Verified 2026-07-10 by running both renders: the first drops all 7 CRD kinds; the second fails with "mtls.allowedPrincipals is empty". Both legs re-ran green inside the strict gate 2026-07-19 (HEAD 8d09841).

Sources: raw/lint-library-header.md context; `scripts/lint-library.sh:256-271,525-541` read and executed.
