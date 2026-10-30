#if !APP_STORE
import Foundation
import Testing
@testable import romm

struct DuoMenuLayoutTests {
    @Test func horizontalDivisionKeepsMenuBelowTheHinge() {
        #expect(DuoMenuLayout.frame(
            in: CGSize(width: 600, height: 900),
            division: CGRect(x: 0, y: 440, width: 600, height: 20)
        ) == CGRect(x: 0, y: 460, width: 600, height: 440))
    }

    @Test func verticalDivisionKeepsMenuInTheTrailingPane() {
        #expect(DuoMenuLayout.frame(
            in: CGSize(width: 900, height: 600),
            division: CGRect(x: 440, y: 0, width: 20, height: 600)
        ) == CGRect(x: 460, y: 0, width: 440, height: 600))
    }

    @Test func aDivisionCanBeALineWithoutArea() {
        #expect(DuoMenuLayout.frame(
            in: CGSize(width: 600, height: 900),
            division: CGRect(x: 0, y: 450, width: 600, height: 0)
        ) == CGRect(x: 0, y: 450, width: 600, height: 450))
    }

    @Test(arguments: [CGRect?.none, .some(.null), .some(.infinite),
                      .some(CGRect(x: 1000, y: 0, width: 20, height: 900)),
                      .some(CGRect(x: 0, y: 0, width: 600, height: 900))])
    func unavailableOrUnusableDivisionKeepsTheExistingPresentation(division: CGRect?) {
        #expect(DuoMenuLayout.frame(in: CGSize(width: 600, height: 900), division: division)
                == CGRect(x: 0, y: 0, width: 600, height: 900))
    }
}
#endif
