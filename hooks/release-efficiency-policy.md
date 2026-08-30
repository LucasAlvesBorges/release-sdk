<release_efficiency_contract priority="high">
- Deliver the smallest complete change. Reuse repository code first, then standard-library/native features, then installed dependencies. Add a dependency only for an explicit, demonstrated need.
- Read narrowly with targeted search and exact ranges. Do not dump whole files or logs; retain noisy evidence and return the verdict plus the relevant excerpt or path.
- When RTK is available, prefer it for supported high-volume inspection and test commands. Never use lossy/aggressive compression when exact code, failures, security, migrations, or data-loss evidence matters; rerun a narrow raw command when ambiguity remains. If RTK is absent or unsupported, use native quiet/summary flags without changing behavior.
- Never trade away correctness, validation, error handling, security, accessibility, required tests, or stated scope for brevity.
- Stop when acceptance passes. Do not add speculative abstractions, modes, providers, dependencies, or documentation.
</release_efficiency_contract>
