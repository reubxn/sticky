#!/usr/bin/env python3

import os
import plistlib
import tempfile
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
CLERK_ENV_PATH = REPOSITORY_ROOT / ".env.clerk.local"
CONVEX_ENV_PATH = REPOSITORY_ROOT / ".env.local"
SECRETS_PATH = (
    Path.home()
    / "Library"
    / "Application Support"
    / "com.learning-buddy.clicky"
    / "secrets.plist"
)


def read_env_file(path: Path) -> dict[str, str]:
    if not path.is_file():
        raise SystemExit(f"Missing required local configuration file: {path.name}")

    values: dict[str, str] = {}
    for line_number, raw_line in enumerate(
        path.read_text(encoding="utf-8").splitlines(),
        start=1,
    ):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue

        if line.startswith("export "):
            line = line.removeprefix("export ").strip()

        if "=" not in line:
            raise SystemExit(f"Invalid line {line_number} in {path.name}")

        key, value = line.split("=", 1)
        normalized_value = value.strip()
        if (
            len(normalized_value) >= 2
            and normalized_value[0] == normalized_value[-1]
            and normalized_value[0] in {'"', "'"}
        ):
            normalized_value = normalized_value[1:-1]

        values[key.strip()] = normalized_value

    return values


def required_value(values: dict[str, str], key: str, filename: str) -> str:
    value = values.get(key, "").strip()
    if not value:
        raise SystemExit(f"{key} is missing from {filename}")
    return value


def main() -> None:
    clerk_values = read_env_file(CLERK_ENV_PATH)
    convex_values = read_env_file(CONVEX_ENV_PATH)

    clerk_publishable_key = required_value(
        clerk_values,
        "CLERK_PUBLISHABLE_KEY",
        CLERK_ENV_PATH.name,
    )
    convex_deployment_url = required_value(
        convex_values,
        "CONVEX_URL",
        CONVEX_ENV_PATH.name,
    )

    SECRETS_PATH.parent.mkdir(parents=True, exist_ok=True)
    if SECRETS_PATH.exists():
        with SECRETS_PATH.open("rb") as existing_secrets_file:
            secrets = plistlib.load(existing_secrets_file)
        if not isinstance(secrets, dict):
            raise SystemExit("Existing secrets.plist is not a dictionary")
    else:
        secrets = {}

    secrets["ClerkPublishableKey"] = clerk_publishable_key
    secrets["ConvexDeploymentURL"] = convex_deployment_url

    temporary_file_descriptor, temporary_file_path = tempfile.mkstemp(
        dir=SECRETS_PATH.parent,
        prefix="secrets.",
        suffix=".plist",
    )
    try:
        with os.fdopen(temporary_file_descriptor, "wb") as temporary_file:
            plistlib.dump(secrets, temporary_file)
        os.chmod(temporary_file_path, 0o600)
        os.replace(temporary_file_path, SECRETS_PATH)
    finally:
        if os.path.exists(temporary_file_path):
            os.unlink(temporary_file_path)

    print("Updated authentication runtime configuration without displaying values.")


if __name__ == "__main__":
    main()
