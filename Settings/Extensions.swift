//
//  Extensions.swift
//  GuideLight v3
//
//  Swift 6 fix: remove retroactive protocol conformance for SCNVector3.
//  Provide == operator and approx-equal helper without declaring Equatable.
//

import Foundation
import SceneKit

// Exact component-wise equality (avoid declaring Equatable conformance)
public extension SCNVector3 {
    static func == (lhs: SCNVector3, rhs: SCNVector3) -> Bool {
        lhs.x == rhs.x && lhs.y == rhs.y && lhs.z == rhs.z
    }

    /// Approximate equality (useful for floating-point scene math)
    static func approximatelyEqual(_ lhs: SCNVector3, _ rhs: SCNVector3, epsilon: Float = 1e-4) -> Bool {
        abs(lhs.x - rhs.x) <= epsilon &&
        abs(lhs.y - rhs.y) <= epsilon &&
        abs(lhs.z - rhs.z) <= epsilon
    }
}
