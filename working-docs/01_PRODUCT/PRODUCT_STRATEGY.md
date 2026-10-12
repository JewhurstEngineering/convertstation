# Product Strategy and Positioning

**Status:** Implementation planning | **Date:** 2026-10-08 | **Working title:** Universal Converter

## One-line pitch
Convert files right on your Mac: drag in, choose the destination format and folder, tune just the settings that matter, and export without sharing source files with the cloud.

## Target personas and jobs
| Persona | Job to be done | Main value |
|---|---|---|
| Software engineer | Turn screen captures into README-friendly loops | reproducible WebP presets and drag/drop |
| Designer | Batch resize and convert export assets | predictable dimensions, alpha behavior, naming |
| Content creator | Deliver media to platform restrictions | filesize targets and visual comparison |
| General Mac user | Change file formats without terminal commands | approachable format list, safe defaults |

## Product principles
1. A conversion is always an explicit source→target operation. Rewrapping or renaming alone is not conversion.
2. Do not advertise unsupported destination formats.
3. A simple successful conversion should take fewer than five deliberate steps after import.
4. Advanced controls are progressive, available to experts but absent from the happy path.
5. Never send user files or filenames off the machine; opt-in crash reporting, if any, must strip paths.
6. Preserve originals. A successful output is checked for decodability before presenting Done.

## Launch scope
**P0** file import, media inspection, animated WebP conversion, output folder, presets, progress, cancellation, error handling, file reveal, accessible UI. **P1** multiple jobs, retry, animated preview, size comparison, persistent preferences. **P2** GIF/MP4 exports, image↔image, Finder Quick Action, reusable batch presets, optional filesize target. **Later** audio, PDF, scripts, smart workflows, CLI.

## Success measures
Instrument locally during dogfood without mandatory telemetry: conversion success rate (target ≥98% across supported fixtures), unexpected output corruption (0), cancellability, correct conflict behavior, responsiveness during 4K conversion, and median user interactions from import to export. Initial numeric thresholds are planning goals, not measured outcomes.

## Commercial direction
Start with a useful free local converter under Jewhurst Engineering. Monetization is an explicit post-validation decision: possible one-time Pro purchase for bulk automations; avoid paid-per-conversion or a mandatory account. Do not add paid tiers in MVP.

## Competitive angle
The differentiator is Mac-native conversion quality, clarity of supported formats and visible control, not an implausible promise to convert every possible file. Need to compare actual output-quality benchmarks, UI speed and reliability before making superiority claims.
