"""A configuration that was never built into the image.

The `mounted` service carries the zone replaced.example from its build and gets
/etc/bind from a read-only mount; the mounted configuration must be the one
that counts, and the built one must be gone.
"""
from conftest import MOUNTED, records


# F14 -------------------------------------------------------------------------

def test_the_mounted_zone_answers():
    assert records(MOUNTED, "mounted.example", "A") == ["10.99.0.1"]


def test_its_subdomain_answers():
    assert records(MOUNTED, "www.mounted.example", "CNAME") == ["mounted.example."]


def test_its_mail_server_answers():
    assert records(MOUNTED, "mounted.example", "MX") == ["10 mail.mounted.example."]


def test_the_zone_built_into_the_image_is_gone():
    assert records(MOUNTED, "replaced.example", "A") == []
