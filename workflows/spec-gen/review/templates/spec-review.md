Review this candidate spec.

- spec_pr_id: {{spec_pr_id}}
- spec_id: {{spec_id}}
- spec_file: {{spec_file}}
- repo: {{repo}}
- commit: {{commit}}
- spec_path: {{spec_path}}

Your working directory is the candidate repository, so you can Read any file in it.

Reference library (read-only, for duplicate detection):
- Directory: {{ref_library_dir}}
- Index/abstracts: {{ref_library_index}}

Required workflow:
1. Read the spec via the pointer (authoritative content, immune to branch drift):
   run `git -C {{repo}} show {{commit}}:{{spec_path}}` and review its full output.
   If this command fails (bad commit / missing path), the pointer is unresolvable:
   the verdict MUST be REJECT with feedback "pointer unresolvable: <the git error>".
   (`{{spec_file}}` is a derived materialized copy; do not treat it as the source of truth.)
2. Read the reference library index to detect re-skins or duplicates.
3. Decide: `APPROVE` only if the spec is original, complete, and actionable. `REJECT` if it duplicates an existing spec, is incomplete, or weakens acceptance criteria.
4. Return the JSON envelope described in your persona.
