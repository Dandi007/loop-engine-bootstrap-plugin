max_passes: ${BOOT_MERGE_MAX_PASSES}
pipelines:
  # ---- Merger: 顺序 merge 所有 ready-to-merge 分支 ----
  - label: merger
    config_dir: ${PLUGIN_ROOT}/workflows/spec-gen/merger
    input:
      workspace_repo: ${WORKSPACE_REPO}
      base_branch: ${WORKSPACE_BASE_BRANCH}
      accept_cmd: ${DD_ACCEPT_CMD}
      trigger_store_dir: ${TRIGGER_STORE_DIR}
      merge_log_dir: ${RUN_ROOT}/logs
    claim:
      store_dir: ${PR_STORE_DIR}
      from: ready-to-merge
      to: merging
      by: merger
      bind:
        pr_id: id
        spec_id: spec_id
        spec_file: spec_file
        branch: branch
        base_commit: base_commit
    pending:
      store_dir: ${PR_STORE_DIR}
      status: ready-to-merge