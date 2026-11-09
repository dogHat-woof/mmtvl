#!/usr/bin/env python3
"""M7l L8: writes MMTVL/IPTV/Teams/college-teams.json, the college half of the Teams catalog.

Fetches ESPN's public, undocumented site and core APIs (no key, no cookies) and writes one entry per team:
FBS and FCS football, D-I men's and women's basketball, and D-I baseball. Run by hand when conferences change
(a yearly chore, not a build step); the app never talks to ESPN, it only reads the committed JSON.

  Football:   the core API's FBS (group 80) and FCS (group 81) conferences ("/children") and each one's teams.
  Basketball: the site API's D-I (group 50) standings, which list every conference with its teams.
  Baseball:   ESPN's college-baseball teams that are D-I basketball schools, each under its basketball
              conference (L9; ESPN's own baseball conferences are incomplete). Baseball and basketball ids
              differ for most schools, so they're joined by ESPN's slug ("michigan-wolverines"). ESPN's list
              also has schools with no baseball team; NO_BASEBALL drops them.

Only https to site.api.espn.com and sports.core.api.espn.com is fetched, redirects included; responses are capped
at 8 MB, and every value written is checked (non-empty text, no control, zero-width or bidi characters).

Prints the count per league and per conference, the baseball schools dropped, every alias dropped because two
schools of one league would share it, and any team without a conference. A league far outside its expected size
stops the script, and nothing is written.

Usage (from the repo root): python3 -I scripts/gen-college-teams.py
Tests: python3 -I scripts/test_gen_college_teams.py
Python 3 standard library only.
"""

import json
import os
import re
import ssl
import sys
import tempfile
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request

USER_AGENT = "MMTVL-catalog-script"
TIMEOUT = 20  # seconds
RETRIES = 2
MAX_BYTES = 8 * 1024 * 1024  # per response
ALLOWED_HOSTS = {"site.api.espn.com", "sports.core.api.espn.com"}

SITE = "https://site.api.espn.com/apis/site/v2/sports"
STANDINGS = "https://site.api.espn.com/apis/v2/sports"
CORE = "https://sports.core.api.espn.com/v2/sports"

OUTPUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "MMTVL", "IPTV", "Teams", "college-teams.json")

# League ids (L6) in the order they're written, with ESPN's sport path.
LEAGUES = [
    ("ncaaf", "football/college-football"),
    ("ncaam", "basketball/mens-college-basketball"),
    ("ncaaw", "basketball/womens-college-basketball"),
    ("ncaabase", "baseball/college-baseball"),
]
FOOTBALL_DIVISIONS = [("80", "FBS", ""), ("81", "FCS", " (FCS)")]  # group, label, conference title suffix
BASKETBALL_GROUP = "50"  # NCAA Division I

# Sizes outside these stop the script (step 4's expected counts, with room for a year of realignment).
RANGES = {
    "FBS": (120, 155),
    "FCS": (105, 140),
    "ncaaf": (230, 290),
    "ncaam": (330, 400),
    "ncaaw": (330, 400),
    "ncaabase": (295, 335),
}

# Conference titles: ESPN's full name without " Conference", except these.
CONFERENCE_TITLES = {
    "Atlantic Coast Conference": "ACC",
    "Southeastern Conference": "SEC",
    "Coastal Athletic Association": "CAA",
    "Mid-Eastern Athletic Conference": "MEAC",
    "Southwestern Athletic Conference": "SWAC",
    "United Athletic Conference": "UAC",
    "Metro Conference": "MAAC",  # ESPN's name for the Metro Atlantic Athletic Conference
}

# Hand aliases (L8), keyed by ESPN's location (the school) or shortDisplayName: names guides use that ESPN doesn't.
HAND_ALIASES = {
    "App State": ["Appalachian State"],
    "Grambling": ["Grambling State"],
    "Ole Miss": ["Mississippi"],
    "UConn": ["Connecticut"],
    "Miami": ["Miami (FL)"],
}

# D-I schools in ESPN's college-baseball list that have no D-I baseball team (2026-11-08: absent from Wikipedia's
# "List of NCAA Division I baseball programs" for the 2027 season, and known to have dropped or never had the sport).
# By slug. A slug here that matches no baseball team prints a warning.
NO_BASEBALL = {
    # The user's list (M7l step 4).
    "colorado-buffaloes", "depaul-blue-demons", "idaho-vandals", "iowa-state-cyclones", "marquette-golden-eagles",
    "montana-grizzlies", "providence-friars", "smu-mustangs", "syracuse-orange", "wisconsin-badgers",
    # Also confirmed.
    "american-university-eagles", "boise-state-broncos", "boston-university-terriers", "buffalo-bulls",
    "chattanooga-mocs", "cleveland-state-vikings", "colgate-raiders", "colorado-state-rams", "denver-pioneers",
    "drake-bulldogs", "drexel-dragons", "duquesne-dukes", "eastern-washington-eagles", "furman-paladins",
    "green-bay-phoenix", "hampton-pirates", "howard-bison", "idaho-state-bengals", "kansas-city-roos",
    "loyola-chicago-ramblers", "loyola-maryland-greyhounds", "montana-state-bobcats", "morgan-state-bears",
    "new-hampshire-wildcats", "north-dakota-fighting-hawks", "north-texas-mean-green", "northern-arizona-lumberjacks",
    "northern-iowa-panthers", "portland-state-vikings", "south-carolina-state-bulldogs", "south-dakota-coyotes",
    "southern-utah-thunderbirds", "temple-owls", "tulsa-golden-hurricane", "utah-state-aggies", "utep-miners",
    "vermont-catamounts", "weber-state-wildcats", "wyoming-cowboys",
}

# Baseball schools whose baseball conference isn't their basketball one (L9), by slug: { "slug": "Title" }.
BASEBALL_CONFERENCES = {}

# Characters never written: controls, format characters (zero-width, bidi marks and overrides), surrogates,
# private use, unassigned, line and paragraph separators.
BANNED_CATEGORIES = {"Cc", "Cf", "Cs", "Co", "Cn", "Zl", "Zp"}
SLUG = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*")


class CatalogError(Exception):
    pass


def checked_url(url, upgrade=True):
    """The URL if it's https to one of ESPN's API hosts (http:// upgraded first when `upgrade`), else CatalogError."""
    if not isinstance(url, str):
        raise CatalogError(f"not a URL: {url!r}")
    if upgrade:
        url = re.sub(r"^http://", "https://", url, flags=re.IGNORECASE)  # the core API's $refs are http://
    try:
        parts = urllib.parse.urlsplit(url)
        port = parts.port
    except ValueError:
        raise CatalogError(f"bad URL: {url!r}")
    if parts.scheme != "https" or parts.hostname not in ALLOWED_HOSTS or port not in (None, 443) \
            or parts.username is not None or parts.password is not None:
        raise CatalogError(f"refusing to fetch {parts.scheme}://{parts.hostname or ''}")
    return url


class CheckedRedirectHandler(urllib.request.HTTPRedirectHandler):
    """Follows a redirect only to https on an allowed host (never upgrading http)."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        checked_url(newurl, upgrade=False)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def make_opener():
    """https only (no http, file, ftp or data handlers, no proxies, no cookies), redirects checked hop by hop."""
    opener = urllib.request.OpenerDirector()
    for handler in (
        urllib.request.HTTPSHandler(context=ssl.create_default_context()),
        CheckedRedirectHandler(),
        urllib.request.HTTPDefaultErrorHandler(),
        urllib.request.HTTPErrorProcessor(),
        urllib.request.UnknownHandler(),  # any other scheme: URLError("unknown url type")
    ):
        opener.add_handler(handler)
    return opener


OPENER = make_opener()


def read_limited(response, limit=MAX_BYTES):
    body = response.read(limit + 1)
    if len(body) > limit:
        raise CatalogError(f"response over {limit} bytes")
    return body


def fetch(url):
    """GET a JSON document: a plain User-Agent, no cookies, a 20 s timeout, up to 2 retries."""
    url = checked_url(url)
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    for attempt in range(RETRIES + 1):
        try:
            with OPENER.open(request, timeout=TIMEOUT) as response:
                return json.loads(read_limited(response))
        except (urllib.error.URLError, TimeoutError, ValueError) as error:
            if attempt == RETRIES:
                raise CatalogError(f"{url.split('?')[0]}: {error}")
            time.sleep(1 + attempt)


def digits(value, what):
    """A numeric id or year from a response, as text, before it goes into a URL."""
    text = str(value)
    if not re.fullmatch(r"\d{1,10}", text):
        raise CatalogError(f"bad {what}: {value!r}")
    return text


def ref_id(ref, kind):
    match = re.search(rf"/{kind}/(\d+)", ref if isinstance(ref, str) else "")
    if not match:
        raise CatalogError(f"no {kind} id in {ref!r}")
    return match.group(1)


def conference_title(name):
    if name in CONFERENCE_TITLES:
        return CONFERENCE_TITLES[name]
    return re.sub(r" Conference$", "", name)


def site_teams(path):
    """ESPN's full team list for a sport, by team id, and its season year."""
    league = fetch(f"{SITE}/{path}/teams?limit=1000")["sports"][0]["leagues"][0]
    teams = {item["team"]["id"]: item["team"] for item in league["teams"]}
    return teams, digits(league["season"]["year"], "season")


def football(path):
    """(team, conference title) for every FBS and FCS conference member."""
    teams, season = site_teams(path)
    base = f"{CORE}/{path.split('/')[0]}/leagues/{path.split('/')[1]}/seasons/{season}"
    members = []
    for group, label, suffix in FOOTBALL_DIVISIONS:
        children = fetch(f"{base}/types/2/groups/{group}/children?limit=500")["items"]
        count = 0
        for child in children:
            conference = fetch(child["$ref"])
            title = conference_title(conference["name"])
            if label not in title:  # "FCS Independents" already says so
                title += suffix
            conference_id = digits(conference["id"], "conference id")
            for item in fetch(f"{base}/types/2/groups/{conference_id}/teams?limit=500")["items"]:
                team_id = ref_id(item["$ref"], "teams")
                team = teams.get(team_id) or fetch(f"{base}/teams/{team_id}")  # a new program may miss the list
                members.append((team, title))
                count += 1
        check_range(label, count)
    return members


def basketball(path):
    """(team, conference title) for every D-I conference member, from the standings."""
    teams, _ = site_teams(path)
    standings = fetch(f"{STANDINGS}/{path}/standings?group={BASKETBALL_GROUP}")
    members = []
    for conference in standings["children"]:
        title = conference_title(conference["name"])
        for entry in standings_entries(conference):
            team_id = entry["team"]["id"]
            members.append((teams.get(team_id, entry["team"]), title))
    return members


def standings_entries(node):
    """A conference's entries, including its divisions' ("Sun Belt - East")."""
    entries = list(node.get("standings", {}).get("entries", []))
    for child in node.get("children", []):
        entries += standings_entries(child)
    return entries


def baseball(path, men, women):
    """ESPN's college-baseball teams that are D-I basketball schools, under the basketball conference (L9)."""
    teams, _ = site_teams(path)
    return baseball_members(teams.values(), men, women)


def baseball_members(teams, men, women):
    """(members, names dropped by NO_BASEBALL, NO_BASEBALL slugs no baseball team has)."""
    conferences = {}
    for team, title in women + men:  # men's last, so it wins where they differ
        conferences[team.get("slug")] = title
    members = {}
    dropped = []
    for team in sorted(teams, key=lambda t: int(digits(t.get("id"), "team id"))):
        slug = team.get("slug")
        if slug not in conferences or slug in members or slug in dropped:  # a school listed twice: the lowest id
            continue
        if slug in NO_BASEBALL:
            dropped.append(slug)
            continue
        members[slug] = (team, BASEBALL_CONFERENCES.get(slug, conferences[slug]))
    seen = {team.get("slug") for team in teams}
    unknown = sorted(NO_BASEBALL - seen)
    return list(members.values()), sorted(dropped), unknown


def normalized(text):
    """TeamMatcher.normalized: case and diacritics folded, anything but letters and digits a space."""
    folded = "".join(c for c in unicodedata.normalize("NFKD", text.casefold()) if not unicodedata.combining(c))
    return " ".join(re.sub(r"[^0-9a-z]+", " ", folded).split())


def aliases(team):
    """shortDisplayName and location when they differ from the name, " St"/" St." also as " State", the hand table."""
    names = []
    for value in (team.get("shortDisplayName", ""), team.get("location", "")):
        if isinstance(value, str) and value:
            names.append(value)
            state = re.sub(r" St\.?$", " State", value)
            if state != value:
                names.append(state)
    for key in (team.get("location"), team.get("shortDisplayName")):
        if isinstance(key, str):
            names += HAND_ALIASES.get(key, [])
    seen = {normalized(team["displayName"]) if isinstance(team.get("displayName"), str) else ""}
    result = []
    for name in names:
        key = normalized(name)
        if key and key not in seen:
            seen.add(key)
            result.append(name)
    return result


def entry(league, team, conference):
    slug = team.get("slug")
    if not isinstance(slug, str) or not SLUG.fullmatch(slug):
        raise CatalogError(f"{league} team {team.get('id')!r} has a bad slug {slug!r}; nothing written")
    return {
        "id": f"{league}.{slug}",
        "league": league,
        "name": team.get("displayName"),
        "school": team.get("location"),
        "nickname": team.get("name"),
        "conference": conference,
        "aliases": aliases(team),
    }


def check_text(value, where):
    if not isinstance(value, str) or not value.strip():
        raise CatalogError(f"{where} is {value!r}, not text; nothing written")
    if value != value.strip() or any(unicodedata.category(c) in BANNED_CATEGORIES for c in value):
        raise CatalogError(f"{where} has stray whitespace or a control, zero-width or bidi character: "
                           f"{value!r}; nothing written")


def validate(entries):
    """Every value written is non-empty text without control, zero-width or bidi characters; else CatalogError."""
    for item in entries:
        where = item.get("id") if isinstance(item.get("id"), str) else repr(item.get("id"))
        for key in ("id", "league", "name", "school", "nickname", "conference"):
            check_text(item.get(key), f"{where} {key}")
        if not isinstance(item.get("aliases"), list):
            raise CatalogError(f"{where} aliases isn't a list; nothing written")
        for alias in item["aliases"]:
            check_text(alias, f"{where} alias")


def drop_ambiguous(entries):
    """Drops an alias from every school of a league whose name, school or alias it would share; returns the drops."""
    owners = {}  # (league, normalized name) -> ids of the teams with it as name, school or alias
    fixed = {}  # the same, for name and school only (which are never dropped)
    for item in entries:
        for name in [item["name"], item["school"]] + item["aliases"]:
            owners.setdefault((item["league"], normalized(name)), set()).add(item["id"])
        for name in (item["name"], item["school"]):
            fixed.setdefault((item["league"], normalized(name)), set()).add(item["id"])
    dropped = []
    for item in entries:
        kept = []
        for alias in item["aliases"]:
            if len(owners[(item["league"], normalized(alias))]) > 1:
                dropped.append((item["league"], alias, item["id"]))
            else:
                kept.append(alias)
        item["aliases"] = kept
    clashes = sorted((league, key, sorted(ids)) for (league, key), ids in fixed.items() if len(ids) > 1)
    return dropped, clashes


def check_range(label, count):
    low, high = RANGES[label]
    if not low <= count <= high:
        raise CatalogError(f"{label} has {count} teams, expected {low}-{high}; nothing written")


def write_catalog(entries, path):
    """Writes the JSON next to `path` and moves it into place; a failed write leaves no temporary file behind."""
    directory = os.path.dirname(path)
    os.makedirs(directory, exist_ok=True)
    handle, temporary = tempfile.mkstemp(dir=directory, suffix=".tmp")
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as file:
            json.dump(entries, file, indent=2, sort_keys=True, ensure_ascii=False)
            file.write("\n")
        os.chmod(temporary, 0o644)  # mkstemp makes it 0600
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def main():
    members = {}
    baseball_dropped, baseball_unknown = [], []
    for league, path in LEAGUES:
        print(f"Fetching {league} ({path})...", file=sys.stderr)
        if league == "ncaaf":
            members[league] = football(path)
        elif league in ("ncaam", "ncaaw"):
            members[league] = basketball(path)
        else:
            members[league], baseball_dropped, baseball_unknown = baseball(path, members["ncaam"], members["ncaaw"])
        check_range(league, len(members[league]))

    entries = []
    for league, _ in LEAGUES:
        entries += [entry(league, team, conference) for team, conference in members[league]]
    validate(entries)

    ids = [item["id"] for item in entries]
    duplicates = sorted({i for i in ids if ids.count(i) > 1})
    if duplicates:
        raise CatalogError(f"duplicate ids {duplicates}; nothing written")

    dropped, clashes = drop_ambiguous(entries)
    used_keys = set()
    for league_members in members.values():
        for team, _ in league_members:
            used_keys.update((team.get("location"), team.get("shortDisplayName")))
    unused = sorted(set(HAND_ALIASES) - used_keys)

    order = {league: index for index, (league, _) in enumerate(LEAGUES)}
    entries.sort(key=lambda i: (order[i["league"]], i["conference"].casefold(), i["name"].casefold(), i["id"]))

    write_catalog(entries, OUTPUT)

    print(f"Wrote {len(entries)} teams to {os.path.relpath(OUTPUT)}")
    for league, _ in LEAGUES:
        items = [i for i in entries if i["league"] == league]
        counts = {}
        for item in items:
            counts[item["conference"]] = counts.get(item["conference"], 0) + 1
        print(f"\n{league}: {len(items)} teams, {len(counts)} conferences")
        for conference in sorted(counts, key=str.casefold):
            print(f"  {conference}: {counts[conference]}")
    print(f"\nBaseball schools dropped (no baseball team): {len(baseball_dropped)}")
    for slug in baseball_dropped:
        print(f"  {slug}")
    for slug in baseball_unknown:
        print(f"Warning: NO_BASEBALL has \"{slug}\", which no baseball team has")
    print("\nAmbiguous aliases dropped:" + ("" if dropped else " none"))
    for league, alias, team_id in sorted(dropped):
        print(f"  {league}: \"{alias}\" from {team_id}")
    if clashes:
        print("\nNames or schools two teams of one league share (kept, can't be told apart):")
        for league, key, team_ids in clashes:
            print(f"  {league}: \"{key}\" {', '.join(team_ids)}")
    missing = [i["id"] for i in entries if not i["conference"]]
    print("\nTeams without a conference: " + (", ".join(missing) if missing else "none"))
    if unused:
        print("\nHand aliases whose key no team has: " + ", ".join(unused))


if __name__ == "__main__":
    try:
        main()
    except CatalogError as error:
        print(f"gen-college-teams: {error}", file=sys.stderr)
        sys.exit(1)
