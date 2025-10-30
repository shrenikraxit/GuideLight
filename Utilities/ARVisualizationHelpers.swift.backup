//
//  ARVisualizationHelpers.swift
//  GuideLight v3
//
//  Glowing chevron breadcrumbs + glowing ring markers (Next + Destination)
//  Includes camera HDR/exposure helper for extra "neon" punch.
//

import Foundation
import ARKit
import SceneKit
import UIKit

// MARK: - AR Visualization Helpers
class ARVisualizationHelpers {
    
    // MARK: Camera punch (call once after ARSCNView is created)
    /// Boosts HDR/exposure so emissive materials pop more (safe no-op if unavailable).
    @MainActor
    static func applyCameraGlowPunch(to sceneView: ARSCNView) {
        func setCamera(_ cam: SCNCamera) {
            cam.wantsHDR = true
            cam.wantsExposureAdaptation = true
            cam.exposureOffset = 0.0       // try +0.3 for even more glow
            cam.minimumExposure = -1.0
            cam.maximumExposure =  1.0
        }
        if let cam = sceneView.pointOfView?.camera { setCamera(cam) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak sceneView] in
            if let cam = sceneView?.pointOfView?.camera { setCamera(cam) }
        }
    }
    
    // MARK: - Beacon Marker (calibration) — unchanged logic
    static func createBeaconMarker(beacon: Beacon, in sceneView: ARSCNView) -> SCNNode {
        let node = SCNNode()
        
        let sphere = SCNSphere(radius: 0.08)
        sphere.firstMaterial?.diffuse.contents = UIColor.cyan
        sphere.firstMaterial?.emission.contents = UIColor.cyan
        sphere.firstMaterial?.transparency = 0.9
        let sphereNode = SCNNode(geometry: sphere)
        node.addChildNode(sphereNode)
        
        let scaleUp = SCNAction.scale(to: 1.3, duration: 0.8)
        scaleUp.timingMode = .easeInEaseOut
        let scaleDown = SCNAction.scale(to: 1.0, duration: 0.8)
        scaleDown.timingMode = .easeInEaseOut
        sphereNode.runAction(.repeatForever(.sequence([scaleUp, scaleDown])))
        
        let h = abs(beacon.position.y)
        let line = SCNCylinder(radius: 0.01, height: CGFloat(max(0.05, h)))
        line.firstMaterial?.diffuse.contents = UIColor.cyan.withAlphaComponent(0.5)
        let lineNode = SCNNode(geometry: line)
        lineNode.position = SCNVector3(0, -Float(line.height) / 2.0, 0)
        node.addChildNode(lineNode)
        
        let nameNode = makeFloatingLabel(text: beacon.name, textColor: .white, bgOpacity: 0.85)
        nameNode.position = SCNVector3(0, 0.22, 0)
        node.addChildNode(nameNode)
        
        let distanceNode = makeFloatingLabel(text: "0.0m", textColor: .white, bgOpacity: 0.6)
        distanceNode.name = "distanceLabel"
        distanceNode.position = SCNVector3(0, 0.30, 0)
        node.addChildNode(distanceNode)
        
        node.position = SCNVector3(beacon.position.x, beacon.position.y, beacon.position.z)
        return node
    }
    
    // MARK: - NEW: Glowing rotating ring (used for Next + Destination)
    /// Creates a glowing ring with subtle shell, inner glow, ground halo, slow rotation, and optional label.
    static func createGlowingRing(at position: simd_float3,
                                  color: UIColor,
                                  labelText: String?) -> SCNNode {
        let node = SCNNode()
        
        // Core torus
        let torus = SCNTorus(ringRadius: 0.18, pipeRadius: 0.015)
        let core = SCNMaterial()
        core.lightingModel = .constant
        core.diffuse.contents   = color.withAlphaComponent(0.95)
        core.emission.contents  = color
        core.blendMode          = .add
        core.writesToDepthBuffer = false
        if #available(iOS 15.0, *) { core.emission.intensity = 1.6 }
        torus.materials = [core]
        
        let ring = SCNNode(geometry: torus)
        ring.eulerAngles = SCNVector3(Float.pi / 2, 0, 0) // vertical ring facing camera
        node.addChildNode(ring)
        
        // Subtle glow shell (slightly larger scale)
        let shellGeom = torus.copy() as! SCNGeometry
        let shellMat = core.copy() as! SCNMaterial
        shellMat.diffuse.contents  = color.withAlphaComponent(0.25)
        shellMat.emission.contents = color.withAlphaComponent(0.35)
        if #available(iOS 15.0, *) { shellMat.emission.intensity = 1.9 }
        shellGeom.materials = [shellMat]
        let shell = SCNNode(geometry: shellGeom)
        shell.eulerAngles = ring.eulerAngles
        shell.scale = SCNVector3(1.10, 1.10, 1.10)
        node.addChildNode(shell)
        
        // Inner glow sphere
        let inner = SCNNode(geometry: SCNSphere(radius: 0.06))
        inner.geometry?.firstMaterial?.lightingModel = .constant
        inner.geometry?.firstMaterial?.diffuse.contents  = color.withAlphaComponent(0.18)
        inner.geometry?.firstMaterial?.emission.contents = color.withAlphaComponent(0.25)
        inner.geometry?.firstMaterial?.blendMode = .add
        node.addChildNode(inner)
        
        // Ground halo
        let halo = makeGroundHalo(color: color, sizeMeters: 0.48)
        halo.position = SCNVector3(0, -0.18, 0)
        node.addChildNode(halo)
        
        // Slow spin
        let rot = SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 12.0)
        ring.runAction(.repeatForever(rot))
        shell.runAction(.repeatForever(rot))
        
        // Optional label
        if let labelText {
            let label = makeFloatingLabel(text: labelText, textColor: .white, bgOpacity: 0.9)
            label.position = SCNVector3(0, 0.28, 0)
            node.addChildNode(label)
        }
        
        node.position = SCNVector3(position.x, position.y, position.z)
        return node
    }
    
    // MARK: - Floating label (Sprite-like, billboard)
    static func makeFloatingLabel(text: String, textColor: UIColor, bgOpacity: CGFloat) -> SCNNode {
        let padding: CGFloat = 8
        let font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let imgSize = CGSize(width: size.width + padding * 2, height: size.height + padding * 2)
        
        UIGraphicsBeginImageContextWithOptions(imgSize, false, 2.0)
        let ctx = UIGraphicsGetCurrentContext()!
        let rect = CGRect(origin: .zero, size: imgSize)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 12)
        ctx.setFillColor(UIColor.black.withAlphaComponent(bgOpacity).cgColor)
        ctx.addPath(path.cgPath)
        ctx.fillPath()
        (text as NSString).draw(in: CGRect(x: padding, y: padding, width: size.width, height: size.height),
                                withAttributes: attributes)
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        
        let metersPerPoint: CGFloat = 0.0012
        let plane = SCNPlane(width: imgSize.width * metersPerPoint, height: imgSize.height * metersPerPoint)
        plane.cornerRadius = 0.02
        let mat = SCNMaterial()
        mat.diffuse.contents = image
        mat.isDoubleSided = true
        plane.materials = [mat]
        
        let node = SCNNode(geometry: plane)
        node.constraints = [SCNBillboardConstraint()]
        node.castsShadow = false
        return node
    }
    
    // MARK: - Ground halo (soft radial puddle of light)
    // NOTE: internal (not private) so the factory enum can call it.
    static func makeGroundHalo(color: UIColor, sizeMeters: CGFloat) -> SCNNode {
        let plane = SCNPlane(width: sizeMeters, height: sizeMeters)
        let img = radialGlowImage(size: CGSize(width: 256, height: 256),
                                  color: color,
                                  innerAlpha: 0.55,
                                  outerAlpha: 0.08)
        let m = SCNMaterial()
        m.diffuse.contents = img
        m.emission.contents = img
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        m.blendMode = .add
        plane.materials = [m]
        
        let n = SCNNode(geometry: plane)
        n.eulerAngles.x = -Float.pi / 2
        n.castsShadow = false
        return n
    }
    
    private static func radialGlowImage(size: CGSize, color: UIColor, innerAlpha: CGFloat, outerAlpha: CGFloat) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, 2.0)
        let ctx = UIGraphicsGetCurrentContext()!
        let colors = [color.withAlphaComponent(innerAlpha).cgColor,
                      color.withAlphaComponent(outerAlpha).cgColor,
                      UIColor.clear.cgColor] as CFArray
        let locs: [CGFloat] = [0.0, 0.35, 1.0]
        let space = CGColorSpaceCreateDeviceRGB()
        let grad = CGGradient(colorsSpace: space, colors: colors, locations: locs)!
        let c = CGPoint(x: size.width/2, y: size.height/2)
        ctx.drawRadialGradient(grad, startCenter: c, startRadius: 0, endCenter: c, endRadius: size.width/2, options: [])
        let img = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return img
    }
    
    // MARK: - Crosshair Alignment (legacy support)
    static func calculateCrosshairAlignment(to targetNode: SCNNode, in sceneView: ARSCNView) -> Float {
        let screenPosition = sceneView.projectPoint(targetNode.position)
        let screenCenter = CGPoint(x: sceneView.bounds.width / 2, y: sceneView.bounds.height / 2)
        let dx = screenPosition.x - Float(screenCenter.x)
        let dy = screenPosition.y - Float(screenCenter.y)
        let pixelDistance = sqrt(dx * dx + dy * dy)
        let maxDistance: Float = 150.0
        let minDistance: Float = 30.0
        if pixelDistance < minDistance { return 1.0 }
        if pixelDistance > maxDistance { return 0.0 }
        return 1.0 - ((pixelDistance - minDistance) / (maxDistance - minDistance))
    }
    
    static func updateMarkerAlignment(node: SCNNode, alignment: Float) {
        guard let sphereNode = node.childNodes.first,
              let sphere = sphereNode.geometry as? SCNSphere else { return }
        let color: UIColor = alignment > 0.85 ? .systemGreen : (alignment > 0.6 ? .systemYellow : .cyan)
        sphere.firstMaterial?.diffuse.contents = color
        sphere.firstMaterial?.emission.contents = color
    }
    
    static func updateDistanceLabel(on node: SCNNode, distance: Float) {
        guard let distanceNode = node.childNode(withName: "distanceLabel", recursively: true),
              let plane = distanceNode.geometry as? SCNPlane else { return }
        let imgNode = makeFloatingLabel(text: String(format: "%.1fm", distance), textColor: .white, bgOpacity: 0.6)
        plane.firstMaterial?.diffuse.contents = (imgNode.geometry as? SCNPlane)?.firstMaterial?.diffuse.contents
    }
    
    static func makeBillboard(node: SCNNode) {
        node.constraints = [SCNBillboardConstraint()]
    }
}

// MARK: - Breadcrumbs Color Factory
enum BreadcrumbsColorFactory {
    static func uiColor(from scheme: String) -> UIColor {
        switch scheme {
        case "Green":   return .systemGreen
        case "Cyan":    return .cyan
        case "Yellow":  return .systemYellow
        case "Magenta": return .systemPink
        case "White":   return .white
        case "Orange":  return .systemOrange
        case "Blue":    return .systemBlue
        default:        return .cyan
        }
    }
}

// MARK: - Chevron Breadcrumb Factory (neon lines + subtle shell + halo)
enum BreadcrumbArrowFactory {
    /// Single-piece neon chevron with a small glow shell + ground halo.
    static func makeBreadcrumbArrowNode(color: UIColor,
                                        glow: Bool,
                                        pulseSeconds: Double,
                                        scale: CGFloat = 1.0) -> SCNNode {
        
        // Shape tuning (meters)
        let barLength: CGFloat = 0.32 * scale
        let barWidth:  CGFloat = 0.070 * scale
        let corner:    CGFloat = barWidth * 0.48
        let thick:     CGFloat = 0.0045 * scale
        let angleDeg:  CGFloat = 32
        let angleRad:  CGFloat = angleDeg * .pi / 180
        
        // Build union path of two rounded legs (apex at 0,0; forward = +Y)
        let baseRect = CGRect(x: -barWidth/2, y: 0, width: barWidth, height: barLength)
        func legPath(rot: CGFloat) -> UIBezierPath {
            let p = UIBezierPath(roundedRect: baseRect, cornerRadius: corner)
            p.apply(CGAffineTransform(rotationAngle: rot))
            return p
        }
        let path = UIBezierPath()
        path.append(legPath(rot: +angleRad))
        path.append(legPath(rot: -angleRad))
        path.usesEvenOddFillRule = false
        
        // Core neon geometry (bright line)
        let coreShape = SCNShape(path: path, extrusionDepth: thick)
        let coreMat = SCNMaterial()
        coreMat.lightingModel = .constant
        coreMat.diffuse.contents   = UIColor(cgColor: color.withAlphaComponent(0.98).cgColor)
        coreMat.emission.contents  = color
        coreMat.blendMode          = .add
        coreMat.writesToDepthBuffer = false
        if #available(iOS 15.0, *) { coreMat.emission.intensity = 1.75 }
        coreShape.materials = [coreMat]
        
        let node = SCNNode(geometry: coreShape)
        node.pivot = SCNMatrix4Identity
        node.position.y = 0.015
        node.castsShadow = false
        
        // Single subtle shell (reads as glow, not a second chevron)
        let shellGeom = (coreShape.copy() as! SCNGeometry)
        let shellMat = coreMat.copy() as! SCNMaterial
        shellMat.diffuse.contents  = color.withAlphaComponent(0.22)
        shellMat.emission.contents = color.withAlphaComponent(0.32)
        if #available(iOS 15.0, *) { shellMat.emission.intensity = 1.85 }
        shellGeom.materials = [shellMat]
        let shellNode = SCNNode(geometry: shellGeom)
        shellNode.scale = SCNVector3(1.08, 1.08, 1.0)
        node.addChildNode(shellNode)
        
        // Ground halo plane (puddle of light)
        let halo = ARVisualizationHelpers.makeGroundHalo(color: color, sizeMeters: 0.40 * scale)
        halo.position = SCNVector3(0, -0.015, 0)
        node.addChildNode(halo)
        
        // Breathing pulse (opacity) + slight emission bump
        if glow && pulseSeconds > 0.1 {
            let up = SCNAction.customAction(duration: pulseSeconds/2.0) { _, _ in
                if #available(iOS 15.0, *) {
                    coreMat.emission.intensity  = 1.95
                    shellMat.emission.intensity = 2.05
                }
            }
            let fadeUp = SCNAction.fadeOpacity(to: 1.0, duration: pulseSeconds/2.0)
            let down = SCNAction.customAction(duration: pulseSeconds/2.0) { _, _ in
                if #available(iOS 15.0, *) {
                    coreMat.emission.intensity  = 1.75
                    shellMat.emission.intensity = 1.85
                }
            }
            let fadeDown = SCNAction.fadeOpacity(to: 0.92, duration: pulseSeconds/2.0)
            node.runAction(.repeatForever(.sequence([up, fadeUp, down, fadeDown])))
        } else {
            node.opacity = 1.0
        }
        
        // Orientation: keep upright (forward = +Y).
        return node
    }
}
