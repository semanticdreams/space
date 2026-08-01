import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


def dry_run(target: str, extra_env: dict[str, str] | None = None) -> str:
    env = {**subprocess.os.environ}
    if extra_env:
        env.update(extra_env)
    result = subprocess.run(
        ["make", "-n", target],
        cwd=REPO_ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    return result.stdout + result.stderr


def assert_has_profile_flags(output: str, *, profile: str, cef: str) -> None:
    assert f"-DSPACE_BUILD_PROFILE={profile}" in output
    assert f"-DSPACE_ENABLE_CEF={cef}" in output


def test_default_build_uses_single_logged_minimal_configure_and_build() -> None:
    output = dry_run("build")

    assert output.count("./scripts/build-log-runner.sh") == 1
    assert "--log build/logs/build.log" in output
    assert '--label "space minimal build"' in output
    assert "cmake -B build" in output
    assert "cmake --build build -- -j1" in output
    assert_has_profile_flags(output, profile="minimal", cef="OFF")
    assert "-DSPACE_ENABLE_CEF=ON" not in output
    assert "cd build && make" not in output


def test_full_build_uses_same_log_mechanism_with_cef_enabled() -> None:
    output = dry_run("build-full")

    assert output.count("./scripts/build-log-runner.sh") == 1
    assert "--log build/logs/build.log" in output
    assert '--label "space full CEF build"' in output
    assert "cmake -B build" in output
    assert "cmake --build build -- -j1" in output
    assert_has_profile_flags(output, profile="full", cef="ON")


def test_build_jobs_defaults_to_1_and_accepts_override() -> None:
    # Default dry-run uses -j1
    default_output = dry_run("build")
    assert "cmake --build build -- -j1" in default_output

    # Override via BUILD_JOBS environment variable still works
    override_output = dry_run("build", extra_env={"BUILD_JOBS": "3"})
    assert "cmake --build build -- -j3" in override_output

    # build-full also respects the override
    full_override_output = dry_run("build-full", extra_env={"BUILD_JOBS": "3"})
    assert "cmake --build build -- -j3" in full_override_output


def test_cmake_aliases_make_profile_intent_explicit() -> None:
    cmake_output = dry_run("cmake")
    cmake_minimal_output = dry_run("cmake-minimal")
    cmake_full_output = dry_run("cmake-full")

    assert "./scripts/build-log-runner.sh" not in cmake_output
    assert "./scripts/build-log-runner.sh" not in cmake_minimal_output
    assert "./scripts/build-log-runner.sh" not in cmake_full_output
    assert_has_profile_flags(cmake_output, profile="minimal", cef="OFF")
    assert_has_profile_flags(cmake_minimal_output, profile="minimal", cef="OFF")
    assert_has_profile_flags(cmake_full_output, profile="full", cef="ON")


def test_package_oriented_local_targets_use_full_build_path() -> None:
    appimage_output = dry_run("appimage")
    pack_output = dry_run("pack")

    assert_has_profile_flags(appimage_output, profile="full", cef="ON")
    assert_has_profile_flags(pack_output, profile="full", cef="ON")
    assert "./scripts/build-log-runner.sh" in appimage_output
    assert "./scripts/build-log-runner.sh" in pack_output
    assert "./scripts/build-appimage.sh" in appimage_output
    assert "cd build && cpack" in pack_output
