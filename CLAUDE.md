# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Working Rules

### Plan Writing

- Plans must be **complete and directly executable**. Every step must include concrete code, file paths, and parameter values. No TODO, TBD, or vague placeholders allowed.
- Break tasks into **minimum independently executable steps**. Each step does exactly one thing, with clear structure and explicit ordering.

### Code Refactoring

- Refactored code must preserve **identical observable behavior** to the original. No changes to external API, output, or side effects.
- Before and after refactoring, run the same tests or verification steps to confirm behavioral equivalence.
