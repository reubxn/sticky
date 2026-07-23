import importlib.util
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).with_name("configure-auth-runtime.py")
MODULE_SPEC = importlib.util.spec_from_file_location(
    "configure_auth_runtime",
    SCRIPT_PATH,
)
assert MODULE_SPEC is not None
assert MODULE_SPEC.loader is not None
CONFIGURE_AUTH_RUNTIME = importlib.util.module_from_spec(MODULE_SPEC)
MODULE_SPEC.loader.exec_module(CONFIGURE_AUTH_RUNTIME)


class HTTPSOriginValidationTests(unittest.TestCase):
    def test_accepts_absent_default_and_valid_explicit_ports(self) -> None:
        for origin in (
            "https://worker.example",
            "https://worker.example/",
            "https://worker.example:443",
            "https://worker.example:1",
            "https://worker.example:65535",
        ):
            with self.subTest(origin=origin):
                self.assertEqual(
                    CONFIGURE_AUTH_RUNTIME.validated_https_origin(
                        origin,
                        "ONBOARDING_WORKER_BASE_URL",
                        ".env.local",
                    ),
                    origin.removesuffix("/"),
                )

    def test_rejects_invalid_or_out_of_range_ports(self) -> None:
        for origin in (
            "https://worker.example:",
            "https://worker.example:0",
            "https://worker.example:65536",
            "https://worker.example:not-a-port",
        ):
            with self.subTest(origin=origin):
                with self.assertRaises(SystemExit):
                    CONFIGURE_AUTH_RUNTIME.validated_https_origin(
                        origin,
                        "ONBOARDING_WORKER_BASE_URL",
                        ".env.local",
                    )


if __name__ == "__main__":
    unittest.main()
