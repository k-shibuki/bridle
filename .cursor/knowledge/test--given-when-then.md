---
trigger: Given When Then, test comment format, GWT comment, test case comment, Given precondition, When action, Then expected
---
# Given / When / Then Comment Format

Every test case must have the following comment format:

```r
# Given: Preconditions
# When:  Action to execute
# Then:  Expected result/verification
```

Write comments directly above test code or within steps, keeping scenarios traceable for readers.

## Example

```r
test_that("validate_graph rejects cycles", {
  # Given: A graph YAML with a circular transition A -> B -> A
  graph <- make_graph(transitions = list(A = "B", B = "A"))

  # When: Validation is run
  # Then: Error is raised with cycle details

  expect_error(
    validate_graph(graph),
    class = "bridle_cycle_error"
  )
})
```
