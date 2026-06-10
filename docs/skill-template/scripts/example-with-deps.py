#!/usr/bin/env python3
"""Example script with PEP 723 inline dependency declaration.

Run with: uv run scripts/example-with-deps.py

PEP 723 lets Python scripts declare their own dependencies inline.
No requirements.txt, no virtualenv setup — uv creates an isolated
environment automatically.

For scripts that use only stdlib (json, sys, re, etc.), PEP 723 is
NOT needed — just run with python3 directly.
"""

# /// script
# dependencies = [
#   "requests>=2.31",
#   "rich>=13.0",
# ]
# requires-python = ">=3.11"
# ///

# import requests
# from rich import print

def main():
    print("This is a template. Uncomment the deps above and imports below.")
    print("Then run: uv run scripts/example-with-deps.py")


if __name__ == "__main__":
    main()
