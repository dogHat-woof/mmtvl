import Testing
@testable import MMTVL

struct SettingsPhoneRemoteTests {
    private func rowIDs(_ model: SettingsModel) -> [String] {
        model.sections.flatMap(\.rows).map(\.id)
    }

    @Test func rootRowShowsOnOff() {
        let (model, _) = makeSettingsModel()
        #expect(model.row(id: "phoneRemote")?.value == "On")
        #expect(model.row(id: "phoneRemote")?.action == .push(.phoneRemote))

        var settings = AppSettings()
        settings.phoneRemoteEnabled = false
        let (off, _) = makeSettingsModel(settings: settings)
        #expect(off.row(id: "phoneRemote")?.value == "Off")
    }

    @Test func pageRowsFollowTheStatus() {
        let (model, recorder) = makeSettingsModel()
        model.perform(.push(.phoneRemote))
        #expect(model.pageTitle == "Phone Remote")
        // Enabled but not running: address, no pair row; no phones: no forget row.
        recorder.phoneRemote = PhoneRemoteSettingsStatus(isRunning: false, problem: "Starting…")
        model.refreshStatus()
        #expect(rowIDs(model).contains("phone.address"))
        #expect(!rowIDs(model).contains("phone.pair"))
        #expect(!rowIDs(model).contains("phone.forget"))
        #expect(model.row(id: "phone.enabled")?.detail == "Starting…")
        #expect(model.row(id: "phone.address")?.value == "No network connection")

        recorder.phoneRemote = PhoneRemoteSettingsStatus(isRunning: true, address: "http://192.168.1.20:8765",
                                                         pairedCount: 2, connectedCount: 1)
        model.refreshStatus()
        #expect(rowIDs(model).contains("phone.pair"))
        #expect(rowIDs(model).contains("phone.forget"))
        #expect(model.row(id: "phone.address")?.value == "http://192.168.1.20:8765")
        #expect(model.row(id: "phone.count")?.value == "2")
        #expect(model.row(id: "phone.count")?.detail == "1 connected now")
        #expect(model.row(id: "phone.accessibility")?.value == "Not Allowed")
    }

    @Test func toggleAppliesSetting() {
        let (model, recorder) = makeSettingsModel()
        model.perform(.push(.phoneRemote))
        model.perform(.toggle(.phoneRemoteEnabled))
        #expect(recorder.appliedSettings.last?.phoneRemoteEnabled == false)
        #expect(model.row(id: "phone.enabled")?.value == "Off")
        #expect(!rowIDs(model).contains("phone.address"))
    }

    @Test func pairingFollowsThePairPage() {
        let (model, recorder) = makeSettingsModel()
        model.perform(.push(.phoneRemote))
        #expect(recorder.pairingCalls.isEmpty)
        model.perform(.push(.pairPhone))
        #expect(recorder.pairingCalls == [true])
        model.press(.back)
        #expect(recorder.pairingCalls == [true, false])
        #expect(model.page == .phoneRemote)
    }

    @Test func resetEndsPairing() {
        let (model, recorder) = makeSettingsModel()
        model.perform(.push(.phoneRemote))
        model.perform(.push(.pairPhone))
        model.reset()
        #expect(recorder.pairingCalls == [true, false])
    }

    @Test func screenDidCloseEndsPairingOnlyWhilePairing() {
        let (model, recorder) = makeSettingsModel()
        model.perform(.push(.phoneRemote))
        model.screenDidClose()
        #expect(recorder.pairingCalls.isEmpty)
        model.perform(.push(.pairPhone))
        model.screenDidClose()
        #expect(recorder.pairingCalls == [true, false])
    }

    @Test func pairPageShowsTheQRCode() {
        let (model, recorder) = makeSettingsModel()
        model.perform(.push(.phoneRemote))
        model.perform(.push(.pairPhone))
        #expect(model.pageImage == .symbol("iphone"))
        #expect(model.row(id: "pair.code")?.value == "—")

        let url = "http://192.168.1.20:8765/#pair=1234"
        recorder.phoneRemote = PhoneRemoteSettingsStatus(isRunning: true, address: "http://192.168.1.20:8765",
                                                         pairingCode: "1234", pairingURL: url, lastPairedName: "iPhone")
        model.refreshStatus()
        #expect(model.pageImage == .qrCode(url))
        #expect(model.row(id: "pair.code")?.value == "1234")
        #expect(model.row(id: "pair.done")?.title == "Paired \"iPhone\"")
        #expect(model.focusableRowIDs == ["pair.close"])
    }

    @Test func forgetAllConfirms() {
        let (model, recorder) = makeSettingsModel()
        model.perform(.push(.phoneRemote))
        model.perform(.push(.confirmForgetPhones))
        model.perform(.forgetAllPhones)
        #expect(recorder.forgets == 1)
        #expect(model.page == .phoneRemote)
    }

    @Test func qrCodeImage() throws {
        let image = try #require(QRCodeImage.make("http://192.168.1.20:8765/#pair=1234"))
        #expect(image.width > 0)
        #expect(image.width % 10 == 0)
    }
}
