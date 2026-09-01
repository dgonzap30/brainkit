import SwiftUI
import XCTest
@testable import LodestarUI

final class ComponentPolicyTests: XCTestCase {
    func testPrimaryActionPolicyIsWhiteAndFortyFourPoints() {
        XCTAssertEqual(LodestarPrimaryActionPolicy.height, 44)
        XCTAssertEqual(LodestarPrimaryActionPolicy.radius, 10)
        XCTAssertEqual(LodestarPrimaryActionPolicy.fillRole, .primary)
    }

    func testCardPolicyUsesFamilyGeometry() {
        XCTAssertEqual(LodestarCardPolicy.inset, 14)
        XCTAssertEqual(LodestarCardPolicy.radius, 10)
        XCTAssertEqual(LodestarCardPolicy.borderWidth, 0.5)
    }

    func testSecondaryActionPolicyIsBorderedAndFortyFourPoints() {
        XCTAssertEqual(LodestarSecondaryActionPolicy.height, 44)
        XCTAssertEqual(LodestarSecondaryActionPolicy.radius, 10)
        XCTAssertEqual(LodestarSecondaryActionPolicy.fillRole, .neutral)
    }

    func testCompactStatePanelIsUnframedAndAllowsNoDetail() {
        let panel = LodestarStatePanel.compact(
            icon: "chart.line.uptrend.xyaxis",
            title: "No trend yet"
        )
        let detail: String = panel.detail

        XCTAssertEqual(detail, "")
        XCTAssertEqual(panel.layout, .compact)
        XCTAssertFalse(panel.layout.isFramed)
        XCTAssertEqual(panel.layout.contentAlignment, .leading)
        XCTAssertEqual(panel.layout.iconSize, 16)
        XCTAssertEqual(panel.layout.contentSpacing, 10)
        XCTAssertEqual(panel.layout.verticalPadding, 16)
        XCTAssertNil(panel.actionLabel)
        XCTAssertNil(panel.action)
    }

    func testHeroStatePanelIsCenteredUnframedAndUsesItsTone() {
        let panel = LodestarStatePanel.hero(
            icon: "camera",
            title: "No photos yet",
            detail: nil,
            tone: .danger
        )
        let detail: String = panel.detail

        XCTAssertEqual(detail, "")
        XCTAssertEqual(panel.layout, .hero)
        XCTAssertFalse(panel.layout.isFramed)
        XCTAssertEqual(panel.layout.contentAlignment, .centered)
        XCTAssertEqual(panel.layout.iconSize, 28)
        XCTAssertEqual(panel.layout.contentSpacing, 12)
        XCTAssertEqual(panel.layout.verticalPadding, 0)
        XCTAssertNil(panel.actionLabel)
        XCTAssertNil(panel.action)
        assertHex(panel.iconForegroundColor, 0xEF4444)

        let neutral = LodestarStatePanel.hero(icon: "camera", title: "No photos yet")
        assertHex(neutral.iconForegroundColor, 0x82828C)
    }

    func testExistingStatePanelInitializerKeepsStringDetailAndCardActionBehavior() {
        var actionInvoked = false
        let panel = LodestarStatePanel(
            icon: "checkmark",
            title: "Ready",
            detail: "Everything is available",
            actionLabel: "Retry",
            action: { actionInvoked = true }
        )
        let detail: String = panel.detail

        XCTAssertEqual(detail, "Everything is available")
        XCTAssertEqual(panel.layout, .card)
        XCTAssertTrue(panel.layout.isFramed)
        XCTAssertEqual(panel.actionLabel, "Retry")
        panel.action?()
        XCTAssertTrue(actionInvoked)
    }

    func testCompactPrimaryActionUsesTheReferenceCapsuleGeometry() {
        let button = LodestarPrimaryButton("Try again", layout: .compactCapsule) {}

        XCTAssertEqual(button.layout, .compactCapsule)
        XCTAssertFalse(button.layout.isFullWidth)
        XCTAssertTrue(button.layout.usesCapsule)
        XCTAssertEqual(button.layout.horizontalPadding, 18)
        XCTAssertEqual(button.layout.verticalPadding, 8)
        XCTAssertEqual(button.layout.fontSize, 13)
        XCTAssertEqual(button.layout.semanticTextStyle, .footnote)
    }

    func testExistingPrimaryButtonCallsKeepTheFullWidthDefault() {
        let button = LodestarPrimaryButton("Continue") {}

        XCTAssertEqual(button.layout, .standard)
        XCTAssertTrue(button.layout.isFullWidth)
        XCTAssertFalse(button.layout.usesCapsule)
    }

    func testProminentRootHeaderStylePreservesReferenceTypography() {
        let style = LodestarHeaderTextStyle.prominentRoot

        XCTAssertEqual(style.eyebrowSize, 10)
        XCTAssertEqual(style.eyebrowTracking, 2.8)
        XCTAssertEqual(style.titleSize, 31)
        XCTAssertEqual(style.titleTracking, 0.5)
        XCTAssertTrue(style.usesHeavyWeight)
        XCTAssertTrue(style.usesCondensedTitle)
        XCTAssertTrue(style.uppercasesTitle)
    }

    func testSettingsHeaderAndRecessedCardPreserveReferenceStyle() {
        let header = LodestarSectionHeaderStyle.settings

        XCTAssertEqual(header.fontSize, 11)
        XCTAssertEqual(header.tracking, 1.6)
        XCTAssertTrue(header.uppercasesTitle)
        XCTAssertTrue(header.usesSecondaryForeground)
        XCTAssertTrue(LodestarCardStyle.recessed.isRecessed)
        XCTAssertEqual(LodestarCardPolicy.recessedFillOpacity, 0.035)
        XCTAssertEqual(LodestarCardPolicy.recessedBorderOpacity, 0.05)
    }

    func testPublicPressFeedbackRemovesScaleAndAnimationForReduceMotion() {
        _ = LodestarPressableButtonStyle()

        XCTAssertEqual(
            LodestarPressFeedbackPolicy.scale(isPressed: true, reduceMotion: false),
            0.97
        )
        XCTAssertEqual(
            LodestarPressFeedbackPolicy.scale(isPressed: true, reduceMotion: true),
            1
        )
        XCTAssertEqual(LodestarPressFeedbackPolicy.opacity(isPressed: true), 0.9)
        XCTAssertNotNil(LodestarPressFeedbackPolicy.animation(reduceMotion: false))
        XCTAssertNil(LodestarPressFeedbackPolicy.animation(reduceMotion: true))
    }

    private func assertHex(
        _ color: Color,
        _ hex: UInt32,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let resolved = color.resolve(in: EnvironmentValues())

        XCTAssertEqual(
            Int((Double(resolved.red) * 255).rounded()),
            Int((hex >> 16) & 0xFF),
            file: file,
            line: line
        )
        XCTAssertEqual(
            Int((Double(resolved.green) * 255).rounded()),
            Int((hex >> 8) & 0xFF),
            file: file,
            line: line
        )
        XCTAssertEqual(
            Int((Double(resolved.blue) * 255).rounded()),
            Int(hex & 0xFF),
            file: file,
            line: line
        )
    }
}
