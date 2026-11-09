/// M7f L13: the leagues of the Teams group.
nonisolated enum TeamLeague: String, CaseIterable, Hashable, Sendable {
    case nfl, nba, nhl, mlb

    var title: String { rawValue.uppercased() }

    /// A programme mentions the league with one of these (whole words, folded).
    var words: [String] {
        switch self {
        case .nfl: ["nfl", "football"]
        case .nba: ["nba", "basketball"]
        case .nhl: ["nhl", "hockey"]
        case .mlb: ["mlb", "baseball"]
        }
    }
}

/// A team the user can pick. `name` is how the playlist's game entries write it ("Los Angeles Lakers").
nonisolated struct Team: Identifiable, Hashable, Sendable {
    /// "nba.lal": stable, stored in `iptv-channels.json` `teams`.
    let id: String
    let league: TeamLeague
    let name: String
    /// "Lakers"; matched only with a league word (several leagues share nicknames: Kings, Rangers, Giants).
    let nickname: String
    /// Other full names: renames, moves, "LA" spellings.
    let aliases: [String]

    init(_ id: String, _ league: TeamLeague, _ name: String, _ nickname: String, aliases: [String] = []) {
        self.id = "\(league.rawValue).\(id)"
        self.league = league
        self.name = name
        self.nickname = nickname
        self.aliases = aliases
    }

    /// The name and every alias.
    var fullNames: [String] { [name] + aliases }
}

/// M7f L13: every NFL, NBA, NHL and MLB team (124), in league order, then alphabetical.
nonisolated enum TeamCatalog {
    static let teams: [Team] = nfl + nba + nhl + mlb

    static let byID: [Team.ID: Team] = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0) })

    static func teams(in league: TeamLeague) -> [Team] {
        teams.filter { $0.league == league }
    }

    private static let nfl: [Team] = [
        Team("ari", .nfl, "Arizona Cardinals", "Cardinals"),
        Team("atl", .nfl, "Atlanta Falcons", "Falcons"),
        Team("bal", .nfl, "Baltimore Ravens", "Ravens"),
        Team("buf", .nfl, "Buffalo Bills", "Bills"),
        Team("car", .nfl, "Carolina Panthers", "Panthers"),
        Team("chi", .nfl, "Chicago Bears", "Bears"),
        Team("cin", .nfl, "Cincinnati Bengals", "Bengals"),
        Team("cle", .nfl, "Cleveland Browns", "Browns"),
        Team("dal", .nfl, "Dallas Cowboys", "Cowboys"),
        Team("den", .nfl, "Denver Broncos", "Broncos"),
        Team("det", .nfl, "Detroit Lions", "Lions"),
        Team("gb", .nfl, "Green Bay Packers", "Packers"),
        Team("hou", .nfl, "Houston Texans", "Texans"),
        Team("ind", .nfl, "Indianapolis Colts", "Colts"),
        Team("jax", .nfl, "Jacksonville Jaguars", "Jaguars"),
        Team("kc", .nfl, "Kansas City Chiefs", "Chiefs"),
        Team("lv", .nfl, "Las Vegas Raiders", "Raiders", aliases: ["Oakland Raiders"]),
        Team("lac", .nfl, "Los Angeles Chargers", "Chargers", aliases: ["LA Chargers", "San Diego Chargers"]),
        Team("lar", .nfl, "Los Angeles Rams", "Rams", aliases: ["LA Rams", "St. Louis Rams"]),
        Team("mia", .nfl, "Miami Dolphins", "Dolphins"),
        Team("min", .nfl, "Minnesota Vikings", "Vikings"),
        Team("ne", .nfl, "New England Patriots", "Patriots"),
        Team("no", .nfl, "New Orleans Saints", "Saints"),
        Team("nyg", .nfl, "New York Giants", "Giants"),
        Team("nyj", .nfl, "New York Jets", "Jets"),
        Team("phi", .nfl, "Philadelphia Eagles", "Eagles"),
        Team("pit", .nfl, "Pittsburgh Steelers", "Steelers"),
        Team("sf", .nfl, "San Francisco 49ers", "49ers"),
        Team("sea", .nfl, "Seattle Seahawks", "Seahawks"),
        Team("tb", .nfl, "Tampa Bay Buccaneers", "Buccaneers"),
        Team("ten", .nfl, "Tennessee Titans", "Titans"),
        Team("wsh", .nfl, "Washington Commanders", "Commanders", aliases: ["Washington Football Team"]),
    ]

    private static let nba: [Team] = [
        Team("atl", .nba, "Atlanta Hawks", "Hawks"),
        Team("bos", .nba, "Boston Celtics", "Celtics"),
        Team("bkn", .nba, "Brooklyn Nets", "Nets"),
        Team("cha", .nba, "Charlotte Hornets", "Hornets"),
        Team("chi", .nba, "Chicago Bulls", "Bulls"),
        Team("cle", .nba, "Cleveland Cavaliers", "Cavaliers"),
        Team("dal", .nba, "Dallas Mavericks", "Mavericks"),
        Team("den", .nba, "Denver Nuggets", "Nuggets"),
        Team("det", .nba, "Detroit Pistons", "Pistons"),
        Team("gs", .nba, "Golden State Warriors", "Warriors"),
        Team("hou", .nba, "Houston Rockets", "Rockets"),
        Team("ind", .nba, "Indiana Pacers", "Pacers"),
        Team("lac", .nba, "Los Angeles Clippers", "Clippers", aliases: ["LA Clippers"]),
        Team("lal", .nba, "Los Angeles Lakers", "Lakers", aliases: ["LA Lakers"]),
        Team("mem", .nba, "Memphis Grizzlies", "Grizzlies"),
        Team("mia", .nba, "Miami Heat", "Heat"),
        Team("mil", .nba, "Milwaukee Bucks", "Bucks"),
        Team("min", .nba, "Minnesota Timberwolves", "Timberwolves"),
        Team("no", .nba, "New Orleans Pelicans", "Pelicans"),
        Team("ny", .nba, "New York Knicks", "Knicks"),
        Team("okc", .nba, "Oklahoma City Thunder", "Thunder"),
        Team("orl", .nba, "Orlando Magic", "Magic"),
        Team("phi", .nba, "Philadelphia 76ers", "76ers"),
        Team("phx", .nba, "Phoenix Suns", "Suns"),
        Team("por", .nba, "Portland Trail Blazers", "Trail Blazers"),
        Team("sac", .nba, "Sacramento Kings", "Kings"),
        Team("sa", .nba, "San Antonio Spurs", "Spurs"),
        Team("tor", .nba, "Toronto Raptors", "Raptors"),
        Team("utah", .nba, "Utah Jazz", "Jazz"),
        Team("wsh", .nba, "Washington Wizards", "Wizards"),
    ]

    private static let nhl: [Team] = [
        Team("ana", .nhl, "Anaheim Ducks", "Ducks"),
        Team("bos", .nhl, "Boston Bruins", "Bruins"),
        Team("buf", .nhl, "Buffalo Sabres", "Sabres"),
        Team("cgy", .nhl, "Calgary Flames", "Flames"),
        Team("car", .nhl, "Carolina Hurricanes", "Hurricanes"),
        Team("chi", .nhl, "Chicago Blackhawks", "Blackhawks"),
        Team("col", .nhl, "Colorado Avalanche", "Avalanche"),
        Team("cbj", .nhl, "Columbus Blue Jackets", "Blue Jackets"),
        Team("dal", .nhl, "Dallas Stars", "Stars"),
        Team("det", .nhl, "Detroit Red Wings", "Red Wings"),
        Team("edm", .nhl, "Edmonton Oilers", "Oilers"),
        Team("fla", .nhl, "Florida Panthers", "Panthers"),
        Team("la", .nhl, "Los Angeles Kings", "Kings", aliases: ["LA Kings"]),
        Team("min", .nhl, "Minnesota Wild", "Wild"),
        Team("mtl", .nhl, "Montreal Canadiens", "Canadiens"),
        Team("nsh", .nhl, "Nashville Predators", "Predators"),
        Team("nj", .nhl, "New Jersey Devils", "Devils"),
        Team("nyi", .nhl, "New York Islanders", "Islanders"),
        Team("nyr", .nhl, "New York Rangers", "Rangers"),
        Team("ott", .nhl, "Ottawa Senators", "Senators"),
        Team("phi", .nhl, "Philadelphia Flyers", "Flyers"),
        Team("pit", .nhl, "Pittsburgh Penguins", "Penguins"),
        Team("sj", .nhl, "San Jose Sharks", "Sharks"),
        Team("sea", .nhl, "Seattle Kraken", "Kraken"),
        Team("stl", .nhl, "St. Louis Blues", "Blues"),
        Team("tb", .nhl, "Tampa Bay Lightning", "Lightning"),
        Team("tor", .nhl, "Toronto Maple Leafs", "Maple Leafs"),
        Team("utah", .nhl, "Utah Mammoth", "Mammoth", aliases: ["Utah Hockey Club"]),
        Team("van", .nhl, "Vancouver Canucks", "Canucks"),
        Team("vgk", .nhl, "Vegas Golden Knights", "Golden Knights"),
        Team("wsh", .nhl, "Washington Capitals", "Capitals"),
        Team("wpg", .nhl, "Winnipeg Jets", "Jets"),
    ]

    private static let mlb: [Team] = [
        Team("ari", .mlb, "Arizona Diamondbacks", "Diamondbacks"),
        Team("ath", .mlb, "Athletics", "Athletics", aliases: ["Oakland Athletics", "Sacramento Athletics", "Las Vegas Athletics"]),
        Team("atl", .mlb, "Atlanta Braves", "Braves"),
        Team("bal", .mlb, "Baltimore Orioles", "Orioles"),
        Team("bos", .mlb, "Boston Red Sox", "Red Sox"),
        Team("chc", .mlb, "Chicago Cubs", "Cubs"),
        Team("cws", .mlb, "Chicago White Sox", "White Sox"),
        Team("cin", .mlb, "Cincinnati Reds", "Reds"),
        Team("cle", .mlb, "Cleveland Guardians", "Guardians", aliases: ["Cleveland Indians"]),
        Team("col", .mlb, "Colorado Rockies", "Rockies"),
        Team("det", .mlb, "Detroit Tigers", "Tigers"),
        Team("hou", .mlb, "Houston Astros", "Astros"),
        Team("kc", .mlb, "Kansas City Royals", "Royals"),
        Team("laa", .mlb, "Los Angeles Angels", "Angels", aliases: ["LA Angels", "Los Angeles Angels of Anaheim"]),
        Team("lad", .mlb, "Los Angeles Dodgers", "Dodgers", aliases: ["LA Dodgers"]),
        Team("mia", .mlb, "Miami Marlins", "Marlins"),
        Team("mil", .mlb, "Milwaukee Brewers", "Brewers"),
        Team("min", .mlb, "Minnesota Twins", "Twins"),
        Team("nym", .mlb, "New York Mets", "Mets"),
        Team("nyy", .mlb, "New York Yankees", "Yankees"),
        Team("phi", .mlb, "Philadelphia Phillies", "Phillies"),
        Team("pit", .mlb, "Pittsburgh Pirates", "Pirates"),
        Team("sd", .mlb, "San Diego Padres", "Padres"),
        Team("sf", .mlb, "San Francisco Giants", "Giants"),
        Team("sea", .mlb, "Seattle Mariners", "Mariners"),
        Team("stl", .mlb, "St. Louis Cardinals", "Cardinals"),
        Team("tb", .mlb, "Tampa Bay Rays", "Rays"),
        Team("tex", .mlb, "Texas Rangers", "Rangers"),
        Team("tor", .mlb, "Toronto Blue Jays", "Blue Jays"),
        Team("wsh", .mlb, "Washington Nationals", "Nationals"),
    ]
}
