import Foundation
import Testing
@testable import MMTVL

/// M7 step 10. Fixtures are shaped like the live responses in the plan's *Research*.
struct PlexAPITests {
    static let client = PlexAPI.ClientInfo(identifier: "client-uuid", version: "1.0", deviceName: "Mac mini",
                                           platformVersion: "26.0")
    static let server = URL(string: "https://192-168-1-20.abc123.plex.direct:32400")!

    @Test func headersCarryTheClientAndNoTokenWhenNil() {
        let headers = PlexAPI.headers(Self.client, token: nil)
        #expect(headers["X-Plex-Client-Identifier"] == "client-uuid")
        #expect(headers["X-Plex-Product"] == "MMTVL")
        #expect(headers["X-Plex-Version"] == "1.0")
        #expect(headers["X-Plex-Platform"] == "macOS")
        #expect(headers["X-Plex-Platform-Version"] == "26.0")
        #expect(headers["X-Plex-Device"] == "Mac")
        #expect(headers["X-Plex-Device-Name"] == "Mac mini")
        #expect(headers["Accept"] == "application/json")
        #expect(headers["X-Plex-Token"] == nil)
        #expect(PlexAPI.headers(Self.client, token: "tok")["X-Plex-Token"] == "tok")
    }

    @Test func pinRequests() {
        let create = PlexAPI.createPINRequest(Self.client)
        #expect(create.httpMethod == "POST")
        #expect(create.url?.absoluteString == "https://plex.tv/api/v2/pins")
        #expect(create.httpBody == nil)
        #expect(create.value(forHTTPHeaderField: "X-Plex-Client-Identifier") == "client-uuid")
        #expect(create.timeoutInterval == 10)
        let check = PlexAPI.checkPINRequest(id: 42, Self.client)
        #expect(check.httpMethod == "GET")
        #expect(check.url?.absoluteString == "https://plex.tv/api/v2/pins/42")
        #expect(check.value(forHTTPHeaderField: "X-Plex-Client-Identifier") == "client-uuid")
    }

    @Test func resourcesAndIdentityRequests() {
        let resources = PlexAPI.resourcesRequest(token: "user-token", Self.client)
        #expect(resources.url?.absoluteString == "https://plex.tv/api/v2/resources?includeHttps=1&includeRelay=0")
        #expect(resources.value(forHTTPHeaderField: "X-Plex-Token") == "user-token")
        let identity = PlexAPI.identityRequest(connection: Self.server)
        #expect(identity.url?.absoluteString == "https://192-168-1-20.abc123.plex.direct:32400/identity")
        #expect(identity.timeoutInterval == 4)
        #expect(identity.value(forHTTPHeaderField: "X-Plex-Token") == nil)
    }

    @Test func continueWatchingRequests() {
        let hubs = PlexAPI.continueWatchingRequest(server: Self.server, token: "server-token", Self.client, flat: false)
        #expect(hubs.url?.absoluteString == "https://192-168-1-20.abc123.plex.direct:32400/hubs/continueWatching?count=12")
        #expect(hubs.value(forHTTPHeaderField: "X-Plex-Token") == "server-token")
        let flat = PlexAPI.continueWatchingRequest(server: Self.server, token: "server-token", Self.client, flat: true)
        #expect(flat.url?.absoluteString == "https://192-168-1-20.abc123.plex.direct:32400/hubs/continueWatching/items")
        #expect(flat.value(forHTTPHeaderField: "X-Plex-Container-Size") == "12")
        #expect(flat.value(forHTTPHeaderField: "X-Plex-Container-Start") == "0")
    }

    @Test func imageURLEncodesThePath() {
        let url = PlexAPI.imageURL(server: Self.server, path: "/library/metadata/123/art/1700000000", width: 704, height: 396)
        #expect(url.absoluteString == "https://192-168-1-20.abc123.plex.direct:32400/photo/:/transcode"
            + "?width=704&height=396&minSize=1&upscale=1&url=%2Flibrary%2Fmetadata%2F123%2Fart%2F1700000000")
        #expect(!url.absoluteString.contains("Token"))
    }

    @Test func linkURL() {
        #expect(PlexAPI.linkURL(code: "AB12") == "https://plex.tv/link/?pin=AB12")
    }

    @Test func decodesAPINWithAndWithoutAToken() throws {
        let pending = """
        {"id":1234567,"code":"AB12","product":"MMTVL","trusted":false,"qr":"https://plex.tv/api/v2/pins/qr/AB12",
         "clientIdentifier":"client-uuid","expiresIn":900,"createdAt":"2026-10-06T18:00:00Z",
         "expiresAt":"2026-10-06T18:15:00.123Z","authToken":null,"newRegistration":null}
        """
        let pin = try PlexAPI.decodePIN(Data(pending.utf8))
        #expect(pin.id == 1_234_567)
        #expect(pin.code == "AB12")
        #expect(pin.authToken == nil)
        #expect(pin.expiresAt == PlexAPI.parseDate("2026-10-06T18:15:00.123Z"))
        #expect(pin.expiresAt != nil)

        let claimed = #"{"id":1,"code":"AB12","expiresAt":"2026-10-06T18:15:00Z","authToken":"secret"}"#
        let done = try PlexAPI.decodePIN(Data(claimed.utf8))
        #expect(done.authToken == "secret")
        #expect(done.expiresAt == Date(timeIntervalSince1970: 1_791_310_500))

        let odd = #"{"id":1,"code":"AB12","expiresAt":"tomorrow"}"#
        #expect(try PlexAPI.decodePIN(Data(odd.utf8)).expiresAt == nil)
    }

    @Test func decodesResources() throws {
        let json = """
        [
          {"name":"Living Room","product":"Plex Media Server","provides":"server","clientIdentifier":"srv1",
           "accessToken":"server-token","owned":true,"presence":true,"httpsRequired":false,
           "connections":[
             {"protocol":"https","address":"192.168.1.20","port":32400,"uri":"https://192-168-1-20.abc.plex.direct:32400","local":true,"relay":false,"IPv6":false},
             {"protocol":"http","address":"192.168.1.20","port":32400,"uri":"http://192.168.1.20:32400","local":true,"relay":false,"IPv6":false},
             {"protocol":"https","address":"1.2.3.4","port":443,"uri":"https://1-2-3-4.abc.plex.direct:443","local":false,"relay":true,"IPv6":false}
           ]},
          {"name":"iPhone","product":"Plex for iOS","provides":"client,player","clientIdentifier":"phone1","owned":true}
        ]
        """
        let resources = try PlexAPI.decodeResources(Data(json.utf8))
        #expect(resources.count == 2)
        #expect(resources.map(\.isServer) == [true, false])
        let server = resources[0]
        #expect(server.accessToken == "server-token")
        #expect(server.owned == true)
        #expect(server.connections.count == 3)
        #expect(server.connections[0] == .init(uri: "https://192-168-1-20.abc.plex.direct:32400", local: true, relay: false,
                                               protocol: "https"))
        #expect(server.connections[2].relay)
        #expect(resources[1].connections.isEmpty)
        #expect(PlexAPI.Resource(name: "x", provides: "client,server", clientIdentifier: "y").isServer)
    }

    @Test func decodesIdentity() throws {
        let json = #"{"MediaContainer":{"size":0,"claimed":true,"machineIdentifier":"srv1","version":"1.41.0"}}"#
        #expect(try PlexAPI.decodeIdentity(Data(json.utf8)) == "srv1")
    }

    static let episode = """
    {"ratingKey":"501","type":"episode","title":"The One","grandparentTitle":"Friends","parentIndex":2,"index":7,
     "thumb":"/library/metadata/501/thumb/1","art":"/library/metadata/500/art/1","grandparentThumb":"/g/thumb",
     "grandparentArt":"/g/art","viewOffset":600000,"duration":1500000}
    """
    static let movie = """
    {"ratingKey":601,"type":"movie","title":"Heat","year":1995,"thumb":"/m/thumb","viewOffset":"3000","duration":6000}
    """

    @Test func continueWatchingHubFormPicksHomeContinue() throws {
        let json = """
        {"MediaContainer":{"size":2,"Hub":[
          {"hubIdentifier":"home.ondeck","title":"On Deck","Metadata":[\(Self.movie)]},
          {"hubIdentifier":"home.continue","title":"Continue Watching","Metadata":[\(Self.episode),\(Self.movie)]}
        ]}}
        """
        let items = try PlexAPI.decodeContinueWatching(Data(json.utf8))
        #expect(items.map(\.ratingKey) == ["501", "601"])
        #expect(items[1].viewOffset == 3000)
        #expect(items[1].year == 1995)
    }

    @Test func continueWatchingFirstHubAndFlatForms() throws {
        let firstHub = #"{"MediaContainer":{"Hub":[{"hubIdentifier":"other","Metadata":[\#(Self.movie)]}]}}"#
        #expect(try PlexAPI.decodeContinueWatching(Data(firstHub.utf8)).map(\.title) == ["Heat"])
        let flat = #"{"MediaContainer":{"size":1,"Metadata":[\#(Self.episode)]}}"#
        #expect(try PlexAPI.decodeContinueWatching(Data(flat.utf8)).map(\.title) == ["The One"])
        let empty = #"{"MediaContainer":{"size":0}}"#
        #expect(try PlexAPI.decodeContinueWatching(Data(empty.utf8)).isEmpty)
    }

    @Test func cardLines() throws {
        let episode = try JSONDecoder().decode(PlexAPI.Metadata.self, from: Data(Self.episode.utf8))
        let card = PlexAPI.card(episode)
        #expect(card.title == "Friends")
        #expect(card.subtitle == "S2 E7 · The One")
        #expect(card.imagePath == "/g/art")
        #expect(card.progress == 0.4)

        let movie = try JSONDecoder().decode(PlexAPI.Metadata.self, from: Data(Self.movie.utf8))
        let movieCard = PlexAPI.card(movie)
        #expect(movieCard.title == "Heat")
        #expect(movieCard.subtitle == "1995")
        #expect(movieCard.imagePath == "/m/thumb")
        #expect(movieCard.progress == 0.5)

        let bare = PlexAPI.card(PlexAPI.Metadata(type: "clip", title: "Clip"))
        #expect(bare.subtitle == "")
        #expect(bare.imagePath == nil)
        #expect(bare.progress == nil)
    }

    /// M7c L14.
    @Test func minutesLeft() throws {
        let episode = try JSONDecoder().decode(PlexAPI.Metadata.self, from: Data(Self.episode.utf8))
        #expect(PlexAPI.minutesLeft(episode) == 15)
        let movie = try JSONDecoder().decode(PlexAPI.Metadata.self, from: Data(Self.movie.utf8))
        #expect(PlexAPI.minutesLeft(movie) == 1)
        #expect(PlexAPI.minutesLeft(PlexAPI.Metadata(viewOffset: 10)) == nil)
        #expect(PlexAPI.minutesLeft(PlexAPI.Metadata(viewOffset: 9_000, duration: 6_000)) == 0)
    }

    /// M7c L14 (Q20): the clear logo when the server lists one; a bad `Image` field doesn't fail the item.
    @Test func clearLogo() throws {
        let json = """
        {"ratingKey":"7","type":"movie","title":"Heat",
         "Image":[{"type":"coverPoster","url":"/p"},{"type":"clearLogo","url":"/library/metadata/7/clearLogo/1"}]}
        """
        let item = try JSONDecoder().decode(PlexAPI.Metadata.self, from: Data(json.utf8))
        #expect(PlexAPI.clearLogoPath(item) == "/library/metadata/7/clearLogo/1")
        let movie = try JSONDecoder().decode(PlexAPI.Metadata.self, from: Data(Self.movie.utf8))
        #expect(PlexAPI.clearLogoPath(movie) == nil)
        let odd = try JSONDecoder().decode(PlexAPI.Metadata.self, from: Data(#"{"title":"X","Image":"nope"}"#.utf8))
        #expect(odd.title == "X")
        #expect(PlexAPI.clearLogoPath(odd) == nil)
    }
}
