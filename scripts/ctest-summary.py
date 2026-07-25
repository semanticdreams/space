#!/usr/bin/env python3
import os
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET


def testcase_failed(testcase):
    return testcase.find("failure") is not None or testcase.find("error") is not None


def text_of(child):
    if child is None or child.text is None:
        return ""
    return child.text.strip()


def print_failure(testcase):
    name = testcase.attrib.get("name", "<unnamed>")
    print(f"[FAIL] {name}")
    for tag in ("failure", "error", "system-out", "system-err"):
        body = text_of(testcase.find(tag))
        if body:
            print(body)


def print_summary(root):
    total = int(root.attrib.get("tests", "0"))
    failures = int(root.attrib.get("failures", "0")) + int(root.attrib.get("errors", "0"))
    skipped = int(root.attrib.get("skipped", root.attrib.get("disabled", "0")))
    passed = max(total - failures - skipped, 0)
    percent = round((passed / total) * 100) if total > 0 else 100
    print(f"{percent}% tests passed, {failures} tests failed out of {total}")
    if skipped > 0:
        print(f"{skipped} tests skipped")


def main():
    with tempfile.NamedTemporaryFile(prefix="space-ctest-", suffix=".xml", delete=False) as junit:
        junit_path = junit.name

    command = ["ctest", "--quiet", "--output-junit", junit_path]
    command.extend(sys.argv[1:])
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)

    try:
        root = ET.parse(junit_path).getroot()
    except Exception:
        if result.stdout:
            print(result.stdout, end="")
        return result.returncode
    finally:
        try:
            os.unlink(junit_path)
        except FileNotFoundError:
            pass

    failed = [testcase for testcase in root.findall(".//testcase") if testcase_failed(testcase)]
    if failed:
        for index, testcase in enumerate(failed):
            if index > 0:
                print("")
            print_failure(testcase)

    print_summary(root)
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
