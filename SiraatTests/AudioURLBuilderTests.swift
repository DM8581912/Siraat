import XCTest
@testable import Siraat

final class AudioURLBuilderTests: XCTestCase {
    func testAlafasyURLZeroPadded() {
        let url = AudioURLBuilder.url(reciterID: QuranReciter.misharyAlafasy.rawValue, surah: 1, ayah: 1)
        XCTAssertEqual(url?.absoluteString, "https://everyayah.com/data/Alafasy_128kbps/001001.mp3")
    }

    func testThreeDigitPadding() {
        let url = AudioURLBuilder.url(reciterID: QuranReciter.sudais.rawValue, surah: 2, ayah: 255)
        XCTAssertEqual(url?.absoluteString, "https://everyayah.com/data/Abdurrahmaan_As-Sudais_192kbps/002255.mp3")
    }

    func testUnknownReciterReturnsNil() {
        XCTAssertNil(AudioURLBuilder.url(reciterID: 9999, surah: 1, ayah: 1))
    }

    func testInvalidInputsReturnNil() {
        XCTAssertNil(AudioURLBuilder.url(reciterID: QuranReciter.misharyAlafasy.rawValue, surah: 0, ayah: 1))
        XCTAssertNil(AudioURLBuilder.url(reciterID: QuranReciter.misharyAlafasy.rawValue, surah: 1, ayah: 0))
    }

    // QuranAudioPlayer's playback-advance decision (pure, no AVPlayer).
    func testNextIndexAdvances() {
        XCTAssertEqual(QuranAudioPlayer.nextIndex(current: 0, queueCount: 3, repeatSingle: false, repeatRange: nil), 1)
    }

    func testNextIndexStopsAtEnd() {
        XCTAssertNil(QuranAudioPlayer.nextIndex(current: 2, queueCount: 3, repeatSingle: false, repeatRange: nil))
    }

    func testNextIndexRepeatSingleStaysPut() {
        XCTAssertEqual(QuranAudioPlayer.nextIndex(current: 1, queueCount: 3, repeatSingle: true, repeatRange: nil), 1)
    }

    func testNextIndexRepeatRangeLoopsBack() {
        XCTAssertEqual(QuranAudioPlayer.nextIndex(current: 2, queueCount: 5, repeatSingle: false, repeatRange: 0...2), 0)
        XCTAssertEqual(QuranAudioPlayer.nextIndex(current: 0, queueCount: 5, repeatSingle: false, repeatRange: 0...2), 1)
    }
}
