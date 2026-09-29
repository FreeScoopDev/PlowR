//
//  ServiceIconTests.swift
//  PlowRTests
//

import Testing
@testable import PlowR

/// Service icons on the route screen and the proposal PDF.
struct ServiceIconTests {

    // "service" contains "ice", so these showed a snowflake on the route and
    // on the client's PDF; "street" contains "tree".
    @Test(arguments: [
        ("Lawn Service", "leaf.fill"),
        ("Tree Service", "tree.fill"),
        ("Office Cleaning", "sparkles"),
        ("Street Sweeping", "wrench.and.screwdriver.fill"),
        ("Price Adjustment", "wrench.and.screwdriver.fill"),
    ])
    func aKeywordMustStartAWord(name: String, symbol: String) {
        #expect(ServiceIcon.symbol(for: name) == symbol)
    }

    @Test(arguments: [
        ("Snow Plowing", "snowflake"),
        ("Ice Control", "thermometer.snowflake"),
        ("De-icing", "thermometer.snowflake"),
        ("Salting", "thermometer.snowflake"),
        ("Lawn Mowing", "leaf.fill"),
        ("Mulching", "tree.fill"),
        ("Sidewalk Shoveling", "figure.walk"),
        ("Driveway Cleaning", "sparkles"),
        ("Edging", "scissors"),
        ("Hedge Trimming", "scissors"),
        ("Debris Removal", "trash.fill"),
        ("Overseeding", "drop.fill"),
    ])
    func everyServiceStillGetsItsIcon(name: String, symbol: String) {
        #expect(ServiceIcon.symbol(for: name) == symbol)
    }
}
