#!/usr/bin/env python3
"""Tests for gen-college-teams.py (no network). Run from the repo root: python3 -I scripts/test_gen_college_teams.py"""

import importlib.util
import io
import os
import sys
import tempfile
import unittest
import urllib.error
import urllib.request

sys.dont_write_bytecode = True  # no __pycache__ in scripts/
_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "gen-college-teams.py")
_spec = importlib.util.spec_from_file_location("gen_college_teams", _path)
gen = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gen)


class URLCheckTests(unittest.TestCase):
    def test_rejects_other_schemes_and_hosts(self):
        for url in [
            "file:///etc/hosts",
            "ftp://sports.core.api.espn.com/x",
            "data:application/json,{}",
            "https://evil.example/v2/sports/football",
            "https://sports.core.api.espn.com.evil.example/",
            "https://evil.example/?u=https://site.api.espn.com/",
            "https://user@sports.core.api.espn.com/v2/",
            "https://sports.core.api.espn.com:8443/v2/",
            "https://sports.core.api.espn.com:bad/v2/",
            "//sports.core.api.espn.com/v2/",
            None,
        ]:
            with self.subTest(url=url), self.assertRaises(gen.CatalogError):
                gen.checked_url(url)

    def test_accepts_and_upgrades_espn_http(self):
        self.assertEqual(gen.checked_url("http://sports.core.api.espn.com/v2/sports/x?lang=en"),
                         "https://sports.core.api.espn.com/v2/sports/x?lang=en")
        self.assertEqual(gen.checked_url("HTTP://sports.core.api.espn.com/v2/x"),
                         "https://sports.core.api.espn.com/v2/x")
        self.assertEqual(gen.checked_url("https://site.api.espn.com/apis/site/v2/x"),
                         "https://site.api.espn.com/apis/site/v2/x")
        self.assertEqual(gen.checked_url("https://SITE.api.espn.com/a"), "https://SITE.api.espn.com/a")

    def test_fetch_refuses_before_connecting(self):
        for url in ["file:///etc/hosts", "https://evil.example/x"]:
            with self.subTest(url=url), self.assertRaises(gen.CatalogError):
                gen.fetch(url)

    def test_opener_has_no_file_ftp_data_or_http_handlers(self):
        for url in ["file:///etc/hosts", "ftp://example.com/x", "data:,x", "http://example.com/"]:
            with self.subTest(url=url), self.assertRaises(urllib.error.URLError):
                gen.OPENER.open(url, timeout=1)

    def test_redirects_are_checked(self):
        handler = gen.CheckedRedirectHandler()
        request = urllib.request.Request("https://sports.core.api.espn.com/v2/a")
        for target in [
            "http://sports.core.api.espn.com/v2/b",  # no silent upgrade on a redirect
            "https://evil.example/v2/b",
            "https://sports.core.api.espn.com.evil.example/b",
            "file:///etc/hosts",
        ]:
            with self.subTest(target=target), self.assertRaises(gen.CatalogError):
                handler.redirect_request(request, None, 302, "Found", {}, target)
        followed = handler.redirect_request(request, None, 302, "Found", {}, "https://site.api.espn.com/b")
        self.assertEqual(followed.full_url, "https://site.api.espn.com/b")


class ResponseSizeTests(unittest.TestCase):
    def test_caps_the_body(self):
        self.assertEqual(gen.read_limited(io.BytesIO(b"x" * 10), limit=10), b"x" * 10)
        with self.assertRaises(gen.CatalogError):
            gen.read_limited(io.BytesIO(b"x" * 11), limit=10)


def good_entry(**changes):
    item = {"id": "ncaaf.michigan-wolverines", "league": "ncaaf", "name": "Michigan Wolverines",
            "school": "Michigan", "nickname": "Wolverines", "conference": "Big Ten", "aliases": ["Michigan"]}
    item.update(changes)
    return item


class ValidationTests(unittest.TestCase):
    def test_good_entry_passes(self):
        gen.validate([good_entry(), good_entry(school="Hawaiʻi", aliases=["Texas A&M", "St. John's"])])

    def test_bad_values_fail(self):
        for changes in [
            {"name": None}, {"name": 12}, {"school": ""}, {"nickname": "  "}, {"conference": " Big Ten"},
            {"name": "Michigan​ Wolverines"},  # zero-width space
            {"name": "Michigan ‮Wolverines"},  # right-to-left override
            {"school": "Mich\u0007igan"},  # control
            {"aliases": "Michigan"}, {"aliases": ["Michigan", None]}, {"aliases": ["Mich igan"]},
        ]:
            with self.subTest(changes=changes), self.assertRaises(gen.CatalogError):
                gen.validate([good_entry(**changes)])

    def test_bad_slug_fails(self):
        team = {"id": "1", "slug": "../x", "displayName": "X Y", "location": "X", "name": "Y"}
        with self.assertRaises(gen.CatalogError):
            gen.entry("ncaaf", team, "Big Ten")


class WriteTests(unittest.TestCase):
    def test_failed_write_leaves_no_temporary_file(self):
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, "college-teams.json")
            with self.assertRaises(TypeError):
                gen.write_catalog([{"not json": {1, 2}}], path)
            self.assertEqual(os.listdir(directory), [])

    def test_write_is_readable_json(self):
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, "college-teams.json")
            gen.write_catalog([good_entry()], path)
            self.assertEqual(os.listdir(directory), ["college-teams.json"])
            self.assertEqual(oct(os.stat(path).st_mode & 0o777), "0o644")


class BaseballTests(unittest.TestCase):
    def test_drops_schools_without_baseball_and_reports_unknown_slugs(self):
        team = lambda i, slug: {"id": str(i), "slug": slug}
        men = [(team(1, "michigan-wolverines"), "Big Ten"), (team(2, "syracuse-orange"), "ACC")]
        members, dropped, unknown = gen.baseball_members(
            [team(10, "michigan-wolverines"), team(11, "syracuse-orange"), team(12, "michigan-wolverines")], men, [])
        self.assertEqual([(t["id"], c) for t, c in members], [("10", "Big Ten")])
        self.assertEqual(dropped, ["syracuse-orange"])
        self.assertIn("wisconsin-badgers", unknown)
        self.assertNotIn("syracuse-orange", unknown)

    def test_maac_title(self):
        self.assertEqual(gen.conference_title("Metro Conference"), "MAAC")
        self.assertEqual(gen.conference_title("Big Ten Conference"), "Big Ten")


if __name__ == "__main__":
    unittest.main(verbosity=1)
