import AuthenticationServices
import XCTest
@testable import Heimherz

/// Liest JSON in der Form, die Apples Encoder für `ASExportedCredentialData` schreibt (Credential Exchange Format 1.0, Feldnamen wie dort),
/// und prüft die Übersetzung in `ImportKonto`. Alle Daten sind erfunden.
final class CredentialImportAdapterTests: XCTestCase {
    private let json = #"""
    {
      "accounts" : [
        {
          "collections" : [],
          "email" : "mia@example.com",
          "fullName" : "Mia",
          "id" : "EQ",
          "username" : "mia",
          "items" : [
            {
              "creationAt" : 1767225600,
              "modifiedAt" : 1767225600,
              "id" : "AQ",
              "title" : "GitHub",
              "favorite" : true,
              "tags" : ["arbeit"],
              "scope" : { "androidApps" : [], "urls" : ["https:\/\/github.com\/login"] },
              "credentials" : [
                { "type" : "basic-auth",
                  "username" : { "fieldType" : "string", "value" : "mia" },
                  "password" : { "fieldType" : "concealed-string", "value" : "demo-passwort-1" } },
                { "type" : "passkey", "credentialId" : "-_8BAg", "key" : "c2NobHVlc3NlbA", "rpId" : "github.com",
                  "userDisplayName" : "Mia", "userHandle" : "-vs", "username" : "mia" },
                { "type" : "totp", "algorithm" : "sha256", "digits" : 8, "issuer" : "GitHub", "period" : 60, "secret" : "AEBAGBAFAYDQQCIK", "username" : "mia" },
                { "type" : "note", "content" : { "fieldType" : "string", "value" : "Arbeitskonto" } }
              ]
            },
            {
              "creationAt" : 1767225600,
              "modifiedAt" : 1767225600,
              "id" : "Ag",
              "title" : "",
              "credentials" : [
                { "type" : "passkey", "credentialId" : "CQkJ", "key" : "c2NobHVlc3NlbDI", "rpId" : "example.com",
                  "userDisplayName" : "", "userHandle" : "AQ", "username" : "bob@example.com" }
              ]
            },
            {
              "creationAt" : 1767225600,
              "modifiedAt" : 1767225600,
              "id" : "Bw",
              "title" : "Stripe",
              "credentials" : [
                { "type" : "api-key",
                  "key" : { "fieldType" : "concealed-string", "value" : "sk_demo" },
                  "keyType" : { "fieldType" : "string", "value" : "secret" },
                  "url" : { "fieldType" : "string", "value" : "https:\/\/api.example.com" },
                  "username" : { "fieldType" : "string", "value" : "acct_1" } }
              ]
            },
            {
              "creationAt" : 1767225600,
              "modifiedAt" : 1767225600,
              "id" : "CA",
              "title" : "Büro",
              "credentials" : [
                { "type" : "drivers-license",
                  "country" : { "fieldType" : "country-code", "value" : "DE" },
                  "fullName" : { "fieldType" : "string", "value" : "Max Muster" },
                  "licenseClass" : { "fieldType" : "string", "value" : "B" },
                  "licenseNumber" : { "fieldType" : "string", "value" : "D-1" } }
              ]
            },
            {
              "creationAt" : 1767225600,
              "modifiedAt" : 1767225600,
              "id" : "Cg",
              "title" : "Ferienhaus",
              "credentials" : [
                { "type" : "note", "content" : { "fieldType" : "string", "value" : "Schlüssel im Briefkasten" } }
              ]
            }
          ]
        }
      ],
      "exporterDisplayName" : "Passwörter",
      "exporterRpId" : "com.apple.passwords",
      "timestamp" : 1767225600,
      "version" : { "major" : 1, "minor" : 0 }
    }
    """#

    private func daten() throws -> ASExportedCredentialData {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return try d.decode(ASExportedCredentialData.self, from: Data(json.utf8))
    }

    func testUebersetzungAllerArten() throws {
        let r = CredentialImportAdapter.konten(aus: try daten())
        XCTAssertEqual(r.konten.count, 3)
        XCTAssertEqual(r.uebersprungen, 2, "API-Schlüssel und Führerschein kennt Lumen Cloud nicht")

        let github = r.konten[0]
        XCTAssertEqual([github.art, github.titel, github.benutzer, github.passwort], [Eintrag.artLogin, "GitHub", "mia", "demo-passwort-1"])
        XCTAssertEqual(github.urls, ["https://github.com/login"])
        XCTAssertTrue(github.favorit)
        XCTAssertEqual(github.notiz, "Arbeitskonto")
        XCTAssertEqual(github.passkeys, [ImportPasskey(credentialId: "-_8BAg", rpId: "github.com", userName: "mia", userDisplayName: "Mia", userHandle: "-vs", schluessel: "c2NobHVlc3NlbA")])
        let totp = try XCTUnwrap(TOTP.einstellung(aus: github.totp))
        XCTAssertEqual(totp.geheim, Data([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]))
        XCTAssertEqual([totp.stellen, totp.periode], [8, 60])
        XCTAssertEqual(totp.algorithmus, .sha256)
        XCTAssertTrue(github.totp.contains("secret=AEBAGBAFAYDQQCIK"))

        let nurPasskey = r.konten[1]
        XCTAssertEqual([nurPasskey.titel, nurPasskey.benutzer, nurPasskey.passwort], ["", "bob@example.com", ""])
        XCTAssertEqual(nurPasskey.passkeys.map(\.rpId), ["example.com"])

        let notiz = r.konten[2]
        XCTAssertEqual([notiz.art, notiz.titel, notiz.notiz], [Eintrag.artNotiz, "Ferienhaus", "Schlüssel im Briefkasten"])
    }

    func testGanzerWegInDenTresor() throws {
        let r = CredentialImportAdapter.konten(aus: try daten())
        let (t, z) = ImportAbbildung.einarbeiten(Tresor(), r.konten, uebersprungenVorher: r.uebersprungen, jetzt: Date(timeIntervalSince1970: 1_792_886_400))
        XCTAssertEqual(z, ImportZaehler(neu: 3, aktualisiert: 0, passkeys: 2, uebersprungen: 2))
        XCTAssertEqual(PasswoerterLogik.zaehler(in: t)[.passkeys], 2)
        XCTAssertEqual(PasswoerterLogik.zaehler(in: t)[.codes], 1)
        XCTAssertEqual(PasswoerterLogik.zaehler(in: t)[.alle], 3)
    }
}
