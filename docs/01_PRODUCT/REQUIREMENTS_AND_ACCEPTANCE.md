# Requirements Catalog and Acceptance Criteria

**Status:** Implementation planning | **Date:** 2026-10-08 | **Working title:** Universal Converter

## Functional requirements
| ID | Priority | Requirement | Acceptance |
|---|---|---|---|
| FR-001 | P0 | Drag/drop and picker import | Valid MOV accepted; unsupported file gets actionable explanation |
| FR-002 | P0 | Source inspection | Show source name, true type, duration, dimensions, frame rate and size |
| FR-003 | P0 | Available targets | Show animated WebP only when valid video can be decoded |
| FR-004 | P0 | Destination selection | User chooses writable folder; destination persists only when authorized |
| FR-005 | P0 | Conversion settings | FPS, width/height, quality, loop, trim settings validated |
| FR-006 | P0 | Asynchronous conversion | UI remains responsive and progress is visible |
| FR-007 | P0 | Cancel | Process terminates, temp output removed, source untouched |
| FR-008 | P0 | Atomic publish | Final result appears only after successful validation and atomic move |
| FR-009 | P0 | Filename collisions | Ask or apply explicitly chosen Keep Both / Replace / Skip policy |
| FR-010 | P0 | Results | Actual output bytes, dimensions and Finder reveal shown |
| FR-011 | P1 | Queue | Each item has independent settings and states |
| FR-012 | P1 | Presets | Save and reuse explicit versioned setting sets |
| FR-013 | P1 | Preview | Verify animation visually and compare to source |
| FR-014 | P2 | More formats | Registry supports other formats without UI condition explosion |

## Quality and non-functional requirements
- Q-001: all conversion work runs off the main actor; view changes do not restart jobs.
- Q-002: user-selected source and destination access is handled with security-scoped access where required.
- Q-003: no arbitrary shell interpolation; launch tools with strongly separated arguments.
- Q-004: binary dependencies have pinned version, checksums, build metadata and license notice.
- Q-005: large files use streaming where possible, not whole-video memory loading.
- Q-006: failed jobs do not leave final corrupted outputs or orphan children.
- Q-007: no network communication is required for successful conversion.
- Q-008: keyboard navigation and VoiceOver cover full primary workflow.

## P0 release signoff
Test three MOV fixtures with differing codecs; 4K sample; VFR sample; invalid file; no-audio MOV; and a short video with alpha where supported. Prove duration and loop behavior, cancellation, destination permission failures, disk-full error and collision policy. Any known incompatible codec must be called out rather than silently misprocessed.
