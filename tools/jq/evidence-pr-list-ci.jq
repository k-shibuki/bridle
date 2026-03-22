# Program: gh pr list JSON array → open PR rows with ci_status. Args: --argjson prs --argjson cfg
[ $prs[] |
  ci_gate(.statusCheckRollup // []; $cfg) as $g
  | {
      number: .number,
      title: .title,
      head_branch: .headRefName,
      ci_status: $g.ci_status,
      mergeable: (.mergeable // "UNKNOWN"),
      review_threads_total: 0,
      review_threads_unresolved: 0
    }
]
