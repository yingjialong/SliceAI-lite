import XCTest
@testable import Windowing

/// ScreenAwarePositioner 单元测试：验证居中/翻转/边界夹紧三类几何行为
final class ScreenAwarePositionerTests: XCTestCase {

    /// 屏幕 1920x1080（左下 0,0），工具栏尺寸 300x40
    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let size = CGSize(width: 300, height: 40)

    /// 锚点远离屏幕边缘时，窗口应水平居中于锚点下方，并保留 offset 间距
    func test_placesBelowAnchor() {
        let pos = ScreenAwarePositioner()
        let origin = pos.position(anchor: CGPoint(x: 800, y: 500),
                                  size: size, screen: screen, offset: 8)
        // 期望：居中横对齐、下方 8 px
        XCTAssertEqual(origin.x, 800 - size.width / 2, accuracy: 0.01)
        XCTAssertEqual(origin.y, 500 - 8 - size.height, accuracy: 0.01)
    }

    /// 锚点靠近屏幕底部导致下方放置会越界时，窗口应翻转到锚点上方
    func test_flipsAboveWhenBottomOutOfScreen() {
        let pos = ScreenAwarePositioner()
        let origin = pos.position(anchor: CGPoint(x: 800, y: 20),    // 离屏幕底部仅 20
                                  size: size, screen: screen, offset: 8)
        // 应翻到 anchor 上方
        XCTAssertEqual(origin.y, 20 + 8, accuracy: 0.01)
    }

    /// 锚点靠近屏幕左缘时，窗口水平位置应被夹紧到屏幕可见区域内
    func test_clampsLeftWhenOffScreen() {
        let pos = ScreenAwarePositioner()
        let origin = pos.position(anchor: CGPoint(x: 10, y: 500),
                                  size: size, screen: screen, offset: 8)
        XCTAssertGreaterThanOrEqual(origin.x, screen.minX)
    }

    /// 锚点靠近屏幕右缘时，窗口右边缘应被夹紧在屏幕可见区域内
    func test_clampsRightWhenOffScreen() {
        let pos = ScreenAwarePositioner()
        let origin = pos.position(anchor: CGPoint(x: 1910, y: 500),
                                  size: size, screen: screen, offset: 8)
        XCTAssertLessThanOrEqual(origin.x + size.width, screen.maxX)
    }
}
