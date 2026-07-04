You are working in the git repository at:

{{workspace_repo}}

This is your workspace. It is an isolated clone: you may change anything inside it, and nothing outside it.

Reference library (read-only inspiration, not a todo list):
- Directory: {{ref_library_dir}}
- Index/abstracts: {{ref_library_index}}

Idea seed:
- idea_id: {{idea_id}}
- prior feedback summary: {{feedback}}
- prior feedback file: {{feedback_file?}}

Task:
1. Read the workspace's `docs/specs/` directory. These are specs that have already been implemented and merged to main. Do NOT duplicate any of them.
2. Read the reference library index to understand the broader spec landscape.
3. Identify 3-5 genuinely new, non-overlapping, independently implementable features.
4. Write each spec at `{{workspace_repo}}/docs/specs/SPEC-<unique>.md`.
5. Return the JSON envelope with one enqueue effect per spec, as described in your persona.

If prior feedback is not "(none)", read the feedback file and address every point. Each spec should be self-contained and can be implemented in parallel with others.
