"""task_board — file-based task-board polyfill package.

Public API is re-exported by scripts/task_board_lib.py (the sole import surface;
15 callers). No caller imports the package directly, so __init__ stays a bare
package marker — submodules (io/lock/ops) are imported explicitly where needed.
"""
