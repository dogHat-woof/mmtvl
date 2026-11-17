import Foundation
import Testing
@testable import MMTVL

/// MR step 3 (D34, L9): the licenses data, the framework drift guard and the bundled notices file.
struct ThirdPartyLicensesTests {
    @Test func idsAreUnique() {
        let ids = ThirdPartyLicenses.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func mmtvlComesFirstAndTheRestAreSortedByName() {
        let all = ThirdPartyLicenses.all
        #expect(all.first?.id == "mmtvl")
        #expect(all.first == ThirdPartyLicenses.mmtvl)
        let rest = all.dropFirst().map(\.name)
        let sorted = rest.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        #expect(rest == sorted)
        #expect(!all.dropFirst().contains { $0.id == "mmtvl" })
    }

    @Test func everyComponentIsFilledIn() {
        for component in ThirdPartyLicenses.all {
            #expect(component.url.hasPrefix("https://"), "\(component.id)")
            #expect(!component.name.isEmpty, "\(component.id)")
            #expect(!component.version.isEmpty, "\(component.id)")
            #expect(!component.license.isEmpty, "\(component.id)")
            #expect(!component.copyright.isEmpty, "\(component.id)")
        }
    }

    /// A new MPVKit version with a new library fails here until the library gets a component.
    @Test func everyEmbeddedFrameworkBelongsToExactlyOneComponent() throws {
        let frameworksURL = try #require(Bundle.main.privateFrameworksURL)
        let names = try FileManager.default.contentsOfDirectory(atPath: frameworksURL.path)
            .filter { $0.hasSuffix(".framework") }
            .map { String($0.dropLast(".framework".count)) }
        #expect(!names.isEmpty)
        for name in names {
            let owners = ThirdPartyLicenses.all.filter { $0.frameworks.contains(name) }
            #expect(owners.count == 1, "\(name) belongs to \(owners.map(\.id))")
        }
        // And nothing lists a framework that isn't shipped, or lists one twice.
        let listed = ThirdPartyLicenses.all.flatMap(\.frameworks)
        #expect(Set(listed).count == listed.count)
        #expect(Set(listed) == Set(names))
    }

    @Test func componentByIDFindsEachOne() {
        for component in ThirdPartyLicenses.all {
            #expect(ThirdPartyLicenses.component(id: component.id) == component)
        }
        #expect(ThirdPartyLicenses.component(id: "no-such-component") == nil)
    }

    @Test func theNoticesFileIsBundledAndNamesEveryComponent() throws {
        let url = try #require(Bundle.main.url(forResource: ThirdPartyLicenses.noticesResource,
                                               withExtension: ThirdPartyLicenses.noticesExtension))
        #expect(url.lastPathComponent == "THIRD_PARTY_NOTICES.md")
        let text = try String(contentsOf: url, encoding: .utf8)
        for component in ThirdPartyLicenses.all {
            #expect(text.contains(component.name), "\(component.name)")
        }
        #expect(text.contains("GNU LESSER GENERAL PUBLIC LICENSE"))
        #expect(text.contains("GNU GENERAL PUBLIC LICENSE"))
    }
}
