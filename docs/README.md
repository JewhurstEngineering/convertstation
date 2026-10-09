# Engineering Documentation Index

**Status:** Implementation planning | **Date:** 2026-10-08 | **Working title:** Universal Converter

This pack is the authoritative multi-document handoff for a native, local-first macOS file conversion utility. `01_PRODUCT/MASTER_PRD.md` contains the foundational complete PRD. All other documents expand particular decisions into implementable contracts. Product name is deliberately provisional.

## Read in this order
1. `01_PRODUCT/MASTER_PRD.md` — goals, user requirements, and initial scope.
2. `01_PRODUCT/PRODUCT_STRATEGY.md` — audience, positioning, success criteria, and roadmap.
3. `02_TECH/ARCHITECTURE.md` — components, boundaries, dependencies, lifecycle.
4. `02_TECH/CONVERSION_ENGINE.md` — provider registry, negotiation, processing contracts.
5. `02_TECH/MOV_TO_WEBP.md` — first vertical slice and exact implementation guidance.
6. `03_EXPERIENCE/UX_SPEC.md` — screens, flows, settings, error treatment.
7. `04_DELIVERY/IMPLEMENTATION_BACKLOG.md` — build tasks, dependencies, exit gates.
8. `04_DELIVERY/TEST_PLAN.md` — quality and fixtures.
9. `05_OPERATIONS/SECURITY_PRIVACY_LICENSING.md` — release safeguards.
10. `06_HANDOFF/CURSOR_CODEX_BUILD_PROMPT.md` — agent implementation instructions.

## Binding decisions
- v1: macOS 14+, native SwiftUI, on-device, MOV → animated WebP. No upload backend.
- Do not claim universal format coverage: only expose capabilities verified by providers.
- Default output directory is chosen explicitly or inherited from last authorized destination. Never silently overwrite sources.
- File import means selecting **local** files, not uploading them to a service.
- Parallelism is bounded and resources are cleaned after all terminal job states.
- Each milestone must ship independently and have acceptance evidence.

## Source and authority
Existing PRD was retained verbatim under `01_PRODUCT/MASTER_PRD.md`; supplements add explicit engineering contracts. If documents disagree, resolve in an ADR before implementation.
