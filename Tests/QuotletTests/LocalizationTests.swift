import XCTest
@testable import Quotlet

final class LocalizationTests: XCTestCase {

    func testSystemLanguageDetectionSeparatesSimplifiedAndTraditional() {
        XCTAssertEqual(Lang.from("zh-Hans-CN"), .zh)
        XCTAssertEqual(Lang.from("zh-CN"), .zh)
        XCTAssertEqual(Lang.from("zh-Hans-HK"), .zh)
        XCTAssertEqual(Lang.from("zh-Hant-TW"), .zhHant)
        XCTAssertEqual(Lang.from("zh-Hant-HK"), .zhHant)
        XCTAssertEqual(Lang.from("zh-TW"), .zhHant)
        XCTAssertEqual(Lang.from("zh-HK"), .zhHant)
        XCTAssertEqual(Lang.from("ja-JP"), .ja)
        XCTAssertEqual(Lang.from("ko-KR"), .ko)
        XCTAssertEqual(Lang.from("fr-FR"), .en)
        XCTAssertEqual(Lang(rawValue: "zh-Hant"), .zhHant)
    }

    func testTraditionalConversionUsesTaiwanTerms() {
        XCTAssertEqual(ZhHant.convert("设置"), "設定")
        XCTAssertEqual(ZhHant.convert("退出登录"), "登出")
        XCTAssertEqual(ZhHant.convert("网络连接失败"), "網路連線失敗")
        // 运行时拼出来的文字：数字隔开的每段分别查表
        XCTAssertEqual(ZhHant.convert("还有 4天9小时"), "還有 4天9小時")
        // 表里没有的整段，按更短的词和单字转换
        XCTAssertEqual(ZhHant.convert("本周日"), "本週日")
        // 非中文原样保留，中文引号换成「」
        XCTAssertEqual(ZhHant.convert("Claude Code “设置”"), "Claude Code 「設定」")
        XCTAssertEqual(ZhHant.convert("Quotlet 5h 42%"), "Quotlet 5h 42%")
    }
}
