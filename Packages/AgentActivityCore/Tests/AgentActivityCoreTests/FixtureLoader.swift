import Foundation

enum FixtureLoader {
    static func body(named fixtureName: String) throws -> Data {
        guard let fixtureURL = Bundle.module.url(
            forResource: fixtureName,
            withExtension: "json"
        ) else {
            throw FixtureLoadingError.missingFixture(fixtureName)
        }
        return try Data(contentsOf: fixtureURL)
    }
}

enum FixtureLoadingError: Error {
    case missingFixture(String)
}
