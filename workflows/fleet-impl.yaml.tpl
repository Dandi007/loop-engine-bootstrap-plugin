max_passes: ${BOOT_MAX_PASSES}
pipelines:
  # ---- Batch Drafter: 产出 3-5 个 spec ----
  - label: draft
    config_dir: ${PLUGIN_ROOT}/workflows/spec-gen/draft
    input:
      workspace_repo: ${WORKSPACE_REPO}
      spec_pr_store_dir: ${SPEC_PR_STORE_DIR}
      ref_library_dir: ${REF_LIBRARY_DIR}
      ref_library_index: ${REF_LIBRARY_INDEX}
      model: ${BOOT_DRAFT_MODEL}
      runtime: ${BOOT_DRAFT_RUNTIME}
      claude_config_dir: ${BOOT_CLAUDE_CONFIG_DIR}
    claim:
      store_dir: ${IDEA_STORE_DIR}
      from: open
      to: done
      by: draft
      bind:
        idea_id: id
        feedback: feedback
        feedback_file: feedback_file
    pending:
      store_dir: ${IDEA_STORE_DIR}
      status: open

  # ---- Spec Loop: review + rework ----
  - label: spec-review
    config_dir: ${PLUGIN_ROOT}/workflows/spec-gen/review
    input:
      workspace_repo: ${WORKSPACE_REPO}
      spec_verdict_store_dir: ${SPEC_VERDICT_STORE_DIR}
      ref_library_dir: ${REF_LIBRARY_DIR}
      ref_library_index: ${REF_LIBRARY_INDEX}
      model: ${BOOT_REVIEW_MODEL}
      claude_config_dir: ${BOOT_CLAUDE_CONFIG_DIR}
    claim:
      store_dir: ${SPEC_PR_STORE_DIR}
      from: ready
      to: reviewing
      by: spec-review
      bind:
        spec_pr_id: id
        spec_id: spec_id
        spec_file: spec_file
        repo: repo
        commit: commit
        spec_path: spec_path
    pending:
      store_dir: ${SPEC_PR_STORE_DIR}
      status: ready

  - label: spec-rework
    config_dir: ${PLUGIN_ROOT}/workflows/spec-gen/rework
    input:
      idea_store_dir: ${IDEA_STORE_DIR}
      trigger_store_dir: ${TRIGGER_STORE_DIR}
    claim:
      store_dir: ${SPEC_VERDICT_STORE_DIR}
      from: decided
      to: reworked
      by: spec-rework
      bind:
        spec_verdict_id: id
        spec_id: spec_id
        spec_file: spec_file
        verdict: verdict
        feedback: feedback
        feedback_file: feedback_file
        repo: repo
        commit: commit
        spec_path: spec_path
    pending:
      store_dir: ${SPEC_VERDICT_STORE_DIR}
      status: decided

  # ---- Impl Loop: 复用 dev-dispatch spec mode ----
  - label: work
    config_dir: ${DD_PLUGIN_ROOT}/workflows/spec/work
    input:
      workspace_repo: ${WORKSPACE_REPO}
      diff_dir: ${DIFF_DIR}
      pr_store_dir: ${PR_STORE_DIR}
      model: ${DD_WORK_MODEL}
      runtime: ${DD_WORK_RUNTIME}
      claude_config_dir: ${DD_CLAUDE_CONFIG_DIR}
    claim:
      store_dir: ${TRIGGER_STORE_DIR}
      from: open
      to: done
      by: work
      bind:
        spec_id: id
        spec_file: spec_file
        feedback: feedback
        feedback_file: feedback_file
        repo: repo
        commit: commit
        spec_path: spec_path
    pending:
      store_dir: ${TRIGGER_STORE_DIR}
      status: open

  - label: review
    config_dir: ${DD_PLUGIN_ROOT}/workflows/spec/review
    input:
      workspace_repo: ${WORKSPACE_REPO}
      verdict_store_dir: ${VERDICT_STORE_DIR}
      model: ${DD_REVIEW_MODEL}
      claude_config_dir: ${DD_CLAUDE_CONFIG_DIR}
    claim:
      store_dir: ${PR_STORE_DIR}
      from: ready
      to: reviewing
      by: review
      bind:
        pr_id: id
        spec_id: spec_id
        spec_file: spec_file
        branch: branch
        base_commit: base_commit
        diff: diff
        diff_file: diff_file
        repo: repo
        commit: commit
        spec_path: spec_path
    pending:
      store_dir: ${PR_STORE_DIR}
      status: ready

  - label: rework
    config_dir: ${DD_PLUGIN_ROOT}/workflows/spec/rework
    input:
      # B0 豁免（b0-inventory 定案）：dd-plugin spec/rework 是跨 store 直调豁免项，
      # 未迁移 enqueue/complete，payload 仍需 {{loop_store_cli}}——缺它则占位符解析
      # 失败，rework tick 在 start 后同步死亡（B1 Wave1 实证 2026-07-05）。
      loop_store_cli: ${LOOP_STORE_CLI}
      trigger_store_dir: ${TRIGGER_STORE_DIR}
      pr_store_dir: ${PR_STORE_DIR}
    claim:
      store_dir: ${VERDICT_STORE_DIR}
      from: decided
      to: reworked
      by: rework
      bind:
        verdict_id: id
        pr_id: pr_id
        spec_id: spec_id
        spec_file: spec_file
        verdict: verdict
        feedback: feedback
        feedback_file: feedback_file
        repo: repo
        commit: commit
        spec_path: spec_path
    pending:
      store_dir: ${VERDICT_STORE_DIR}
      status: decided

  # ---- INV-3 guard: spec 必须在 diff 里 ----
  - label: spec-check
    config_dir: ${PLUGIN_ROOT}/workflows/spec-gen/spec-check
    input:
      workspace_repo: ${WORKSPACE_REPO}
      trigger_store_dir: ${TRIGGER_STORE_DIR}
    claim:
      store_dir: ${PR_STORE_DIR}
      from: approved
      to: checking
      by: spec-check
      bind:
        pr_id: id
        spec_id: spec_id
        spec_file: spec_file
        branch: branch
        base_commit: base_commit
        repo: repo
        commit: commit
        spec_path: spec_path
    pending:
      store_dir: ${PR_STORE_DIR}
      status: approved

  # ---- Deploy-Verify: 只测试不 merge, 标记 ready-to-merge ----
  - label: deploy-verify
    config_dir: ${PLUGIN_ROOT}/workflows/spec-gen/deploy-verify
    input:
      workspace_repo: ${WORKSPACE_REPO}
      accept_cmd: ${DD_ACCEPT_CMD}
      trigger_store_dir: ${TRIGGER_STORE_DIR}
      deploy_log_dir: ${RUN_ROOT}/logs
    claim:
      store_dir: ${PR_STORE_DIR}
      from: ready-to-deploy
      to: verifying
      by: deploy-verify
      bind:
        pr_id: id
        spec_id: spec_id
        spec_file: spec_file
        branch: branch
        base_commit: base_commit
        repo: repo
        commit: commit
        spec_path: spec_path
    pending:
      store_dir: ${PR_STORE_DIR}
      status: ready-to-deploy