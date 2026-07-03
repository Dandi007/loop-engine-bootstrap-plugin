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
1. Read the reference library index to understand what has already been specified.
2. Identify a genuinely new, worthwhile proposition that is not a re-skin of any existing spec.
3. Write a concise technical spec at `{{workspace_repo}}/docs/specs/SPEC-<unique>.md`.
4. Return the JSON envelope described in your persona.

If prior feedback is not "(none)", read the feedback file and address every point.
