# Shared definitions: merge-gate CI rollup (exclude bot commit_status_name rows from review-bots.json).
# Sourced by concatenation before a program file; expects $cfg with .bots[].
# SSOT with tools/evidence-pull-request.sh merge-gate rollup.

# GitHub statusCheckRollup may list multiple rows per check name (e.g. check-policy
# failed then passed on re-run). Collapse to one row per name: prefer the latest
# COMPLETED row by completedAt; otherwise first row for that name.
def dedupe_roll($roll):
  [ $roll[] | select((.name // "") != "") ]
  | group_by(.name)
  | map(
      ( . | map(select(.status == "COMPLETED" and .completedAt != null)) | sort_by(.completedAt) | last) // .[0]
    );

def filtered_roll($roll; $cfg):
  ([$cfg.bots[] | (.commit_status_name // "") | select(length > 0) | ascii_downcase]) as $npats
  | (if ($npats | length) == 0 then [ $roll[] | select((.name // "") != "") ] else
      [ $roll[] | select(
          (.name // "") as $cn
          | ($cn != "")
            and ([ $npats[] as $p | (($cn | ascii_downcase) == $p) ] | any | not)
        )]
    end);

def ci_gate($roll; $cfg):
  filtered_roll(dedupe_roll($roll); $cfg) as $filtered
  | {
      ci_status: (
        if ($filtered | length) == 0 then "no_checks"
        elif [$filtered[] | select(.conclusion == "FAILURE")] | length > 0 then "failure"
        elif [$filtered[] | select(.status != "COMPLETED")] | length > 0 then "pending"
        elif [$filtered[] | select(
          .status == "COMPLETED"
          and (.conclusion != "SUCCESS" and .conclusion != "FAILURE" and .conclusion != "SKIPPED")
        )] | length > 0 then "failure"
        else "success"
        end
      ),
      ci_checks: (
        [ $filtered[] | {
          name: .name,
          status: (
            if .status != "COMPLETED" then "pending"
            elif .conclusion == "SUCCESS" then "pass"
            elif .conclusion == "FAILURE" then "fail"
            elif .conclusion == "SKIPPED" then "skipped"
            elif .status == "COMPLETED" then "fail"
            else "pending"
            end
          ),
          elapsed_seconds: (
            if .completedAt != null and .startedAt != null then
              ((.completedAt | fromdateiso8601) - (.startedAt | fromdateiso8601))
            else null
            end
          )
        }]
      )
    };
