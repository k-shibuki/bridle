# Common test setup for bridle.
# testthat sources this file once before all test files.

# Ensure optional test dependencies are available
skip_if_not_installed("withr")
