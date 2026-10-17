import Foundation
import Testing

struct MobilePairingTests {
    private let key = String(repeating: "a", count: 64)
    private let pin = String(repeating: "b", count: 64)

    private func invitation(host: String = "home.local") -> String {
        "openstrudel://connect?host=\(host)&port=7789&key=\(key)&pin=\(pin)&name=My%20OpenStrudel"
    }

    @Test func macAndPublicServerUseTheSameInvitation() throws {
        for host in ["home.local", "8.8.8.8", "home.example.com"] {
            let pairing = try MacPairing(url: #require(URL(string: invitation(host: host))))
            #expect(pairing.baseURL == "https://\(host):7789")
            #expect(pairing.name == "My OpenStrudel")
            #expect(pairing.key == key)
            #expect(pairing.pin == pin)
        }
    }

    @Test func ambiguousInvitationsAreRejected() throws {
        let original = invitation()
        for value in [
            original + "&host=other.example.com",
            original + "&key=" + key,
            original + "#anything",
            original.replacingOccurrences(of: "connect?", with: "connect/another?"),
            original.replacingOccurrences(of: "connect?", with: "user@connect?"),
            original.replacingOccurrences(of: "connect?", with: "connect:443?"),
            invitation(host: "my..host"),
            invitation(host: "my.-host")
        ] {
            let url = try #require(URL(string: value))
            #expect(throws: (any Error).self) { try MacPairing(url: url) }
        }
    }

    @Test func namesDecodeSpacesAndLiteralPluses() throws {
        let named = invitation().replacingOccurrences(of: "My%20OpenStrudel", with: "Mac+mini+%2B+iPhone")
        #expect(try MacPairing(url: #require(URL(string: named))).name == "Mac mini + iPhone")
    }

    @Test func cameraAndPastedWebLinksKeepCredentialsOutOfTheWebsiteRequest() throws {
        let native = try #require(URL(string: invitation() + "&keyPin=" + pin))
        let item = MobileInvitation(url: native, expiresAt: "2026-10-17T12:00:00Z")
        let web = item.shareURL
        let components = try #require(URLComponents(url: web, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "https")
        #expect(components.host == "waiwai.is")
        #expect(components.path == "/openstrudel/connect.html")
        #expect(components.query == nil)
        #expect(components.percentEncodedFragment?.removingPercentEncoding == native.absoluteString)
        let pairing = try MacPairing(url: web)
        #expect(pairing.host == "home.local" && pairing.key == key && pairing.pin == "spki:" + pin)
        #expect(pairing.name == "My OpenStrudel")
        // Deployed browser handoff links predate universal links and remain valid.
        let legacy = try #require(URL(string: "https://waiwai.is/openstrudel/connect.html#" + invitation().addingPercentEncoding(withAllowedCharacters: .alphanumerics)!))
        #expect(try MacPairing(url: legacy).pin == pin)
        let start = try Date.ISO8601FormatStyle().parse("2026-10-17T11:59:00Z")
        #expect(item.remainingSeconds(at: start) == 60)
    }

    @Test func webLinksOnlyAcceptTheExactInvitationEndpointAndNativePayload() throws {
        let item = try MobileInvitation(url: #require(URL(string: invitation())), expiresAt: "2026-10-17T12:00:00Z")
        let original = item.shareURL.absoluteString
        for value in [
            original.replacingOccurrences(of: "waiwai.is/", with: "waiwai.is.evil.example/"),
            original.replacingOccurrences(of: "https:", with: "http:"),
            original.replacingOccurrences(of: "waiwai.is/", with: "user@waiwai.is/"),
            original.replacingOccurrences(of: "waiwai.is/", with: "waiwai.is:8080/"),
            original.replacingOccurrences(of: "connect.html#", with: "connect.html?key=leak#"),
            original.replacingOccurrences(of: "connect.html#", with: "other.html#"),
            "https://waiwai.is/openstrudel/connect.html#https%3A%2F%2Fevil.example",
            "https://waiwai.is/openstrudel/connect.html#openstrudel%3A%2F%2Foauth%3Fcode%3Dtest"
        ] {
            let url = try #require(URL(string: value))
            #expect(throws: (any Error).self) { try MacPairing(url: url) }
        }
    }

    @Test func expirationCountdownStopsAtZero() throws {
        let item = try MobileInvitation(url: #require(URL(string: invitation())), expiresAt: "2026-09-30T12:05:00.000Z")
        let start = try Date.ISO8601FormatStyle().parse("2026-09-30T12:00:00Z")
        #expect(item.remainingSeconds(at: start) == 300)
        #expect(item.remainingSeconds(at: start.addingTimeInterval(299.5)) == 1)
        #expect(item.remainingSeconds(at: start.addingTimeInterval(301)) == 0)
    }

    @Test func aMacLinkSaysItWorksOnlyOnItsOwnNetwork() throws {
        let local = try MobileInvitation(url: #require(URL(string: invitation(host: "waiMini.local"))), expiresAt: "2026-10-15T12:00:00Z")
        let server = try MobileInvitation(url: #require(URL(string: invitation(host: "2.29.5.55"))), expiresAt: "2026-10-15T12:00:00Z")
        #expect(local.isLocalNetworkOnly)
        #expect(!server.isLocalNetworkOnly)
    }

    @Test func missingOrWeakCredentialsCannotConnect() throws {
        for value in [invitation().replacingOccurrences(of: key, with: "123456"), invitation().replacingOccurrences(of: pin, with: ""), invitation().replacingOccurrences(of: "7789", with: "0")] {
            let url = try #require(URL(string: value))
            #expect(throws: (any Error).self) { try MacPairing(url: url) }
        }
    }
}
