//
//  NavigationARView.swift
//  GuideLight v3
//
//  Glowing chevron breadcrumbs + Glowing markers (Next + Destination).
//  Swift-6 safe (MainActor hops), spacing de-dup, forward orientation.
//

import SwiftUI
import ARKit
import SceneKit

struct NavigationARView: UIViewRepresentable {
    @ObservedObject var viewModel: NavigationViewModel
    let session: ARSession

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.automaticallyUpdatesLighting = true
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        view.scene = SCNScene()
        view.session = session
        view.delegate = context.coordinator

        // Optional veil for contrast (tweak/disable if you like)
        let veil = UIView(frame: .zero)
        veil.backgroundColor = UIColor.black.withAlphaComponent(0.22)
        veil.isUserInteractionEnabled = false
        veil.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(veil)
        NSLayoutConstraint.activate([
            veil.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            veil.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            veil.topAnchor.constraint(equalTo: view.topAnchor),
            veil.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Roots
        let breadcrumbsRoot = SCNNode()
        breadcrumbsRoot.name = "breadcrumbsRoot"
        view.scene.rootNode.addChildNode(breadcrumbsRoot)

        let waypointsRoot = SCNNode()
        waypointsRoot.name = "waypointsRoot"
        view.scene.rootNode.addChildNode(waypointsRoot)

        context.coordinator.sceneView = view
        context.coordinator.breadcrumbsRoot = breadcrumbsRoot
        context.coordinator.waypointsRoot = waypointsRoot

        // Extra neon pop
        ARVisualizationHelpers.applyCameraGlowPunch(to: view)

        context.coordinator.startBreadcrumbsTimer(viewModel: viewModel)
        context.coordinator.refreshWaypointMarkers(viewModel: viewModel)
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        context.coordinator.handleStateChanges(viewModel: viewModel)
        context.coordinator.refreshWaypointMarkersIfNeeded(viewModel: viewModel)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, ARSCNViewDelegate {
        weak var sceneView: ARSCNView?
        var breadcrumbsRoot: SCNNode?
        var waypointsRoot: SCNNode?

        private var breadcrumbsTimer: Timer?
        private var lastUpdateTime: TimeInterval = 0
        private var lastCameraPos: simd_float3?
        private var lastCameraYaw: Float = 0
        private var lastWaypointIndex: Int = -1
        private var lastMarkersIndex: Int = -1

        private let minMoveForUpdate: Float = 0.25
        private let minYawForUpdate:  Float = .pi/18

        deinit { breadcrumbsTimer?.invalidate() }

        func startBreadcrumbsTimer(viewModel: NavigationViewModel) {
            breadcrumbsTimer?.invalidate()
            breadcrumbsTimer = Timer.scheduledTimer(withTimeInterval: 0.30, repeats: true) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.updateIfNeeded(viewModel: viewModel)
                }
            }
        }

        func handleStateChanges(viewModel: NavigationViewModel) {
            if case .arrived = viewModel.navigationState {
                fadeOutBreadcrumbs()
                clearWaypointMarkers()
            }
            if viewModel.showArrivalMessage {
                bloomLastBreadcrumbs()
            }
        }

        func refreshWaypointMarkersIfNeeded(viewModel: NavigationViewModel) {
            if viewModel.currentWaypointIndex != lastMarkersIndex {
                refreshWaypointMarkers(viewModel: viewModel)
            }
        }

        private func getSettings() -> (enabled: Bool, lengthM: Float, spacingM: Float, glow: Bool, pulse: Double, color: UIColor) {
            let ud = UserDefaults.standard
            let enabled = ud.object(forKey: "breadcrumbsEnabled") as? Bool ?? true
            let lengthM = Float(ud.double(forKey: "breadcrumbsTrailLengthM").nonZeroOr(8.0))
            let spacingM = Float(ud.double(forKey: "breadcrumbsSpacingM").nonZeroOr(0.8))
            let glow     = ud.object(forKey: "breadcrumbsGlowEnabled") as? Bool ?? true
            let pulse    = ud.double(forKey: "breadcrumbsPulseSeconds").nonZeroOr(1.8)
            let scheme   = ud.string(forKey: "breadcrumbsColorScheme") ?? "Cyan"
            let color    = BreadcrumbsColorFactory.uiColor(from: scheme)
            return (enabled, max(1.0, lengthM), max(0.1, spacingM), glow, max(0.1, pulse), color)
        }

        // MARK: - Breadcrumbs update

        private func updateIfNeeded(viewModel: NavigationViewModel) {
            guard let sceneView = sceneView else { return }
            let settings = getSettings()
            guard settings.enabled else { clearBreadcrumbs(); return }

            guard case .navigating = viewModel.navigationState,
                  let frame = sceneView.session.currentFrame,
                  let path = viewModel.currentPath else {
                clearBreadcrumbs(); return
            }

            let camTransform = frame.camera.transform
            let camPos = simd_float3(camTransform.columns.3.x,
                                     camTransform.columns.3.y,
                                     camTransform.columns.3.z)

            let forward = frame.camera.transform.columns.2
            let cameraYaw = atan2(-forward.x, -forward.z)

            let movedEnough = (lastCameraPos == nil) || simd_distance(lastCameraPos!, camPos) > minMoveForUpdate
            let turnedEnough = abs(cameraYaw - lastCameraYaw) > minYawForUpdate
            let waypointChanged = (viewModel.currentWaypointIndex != lastWaypointIndex)

            let now = CACurrentMediaTime()
            let timeOk = now - lastUpdateTime > 0.25
            guard movedEnough || turnedEnough || waypointChanged || timeOk else { return }

            let samples = sampleAhead(from: camPos,
                                      path: path,
                                      startIndex: viewModel.currentWaypointIndex,
                                      spacing: settings.spacingM,
                                      maxDistance: settings.lengthM)

            renderBreadcrumbs(samplesWorld: samples, color: settings.color, glow: settings.glow, pulse: settings.pulse)

            lastCameraPos = camPos
            lastCameraYaw = cameraYaw
            lastWaypointIndex = viewModel.currentWaypointIndex
            lastUpdateTime = now
        }

        private func sampleAhead(from cameraPos: simd_float3,
                                 path: NavigationPath,
                                 startIndex: Int,
                                 spacing: Float,
                                 maxDistance: Float) -> [simd_float3] {

            var controlPoints: [simd_float3] = [cameraPos]
            let wps = path.waypoints
            guard startIndex < wps.count else { return [] }
            controlPoints.append(wps[startIndex].position)
            if startIndex + 1 < wps.count {
                for i in (startIndex+1)..<wps.count { controlPoints.append(wps[i].position) }
            }

            var out: [simd_float3] = []
            var accum: Float = 0.0
            var remaining = maxDistance

            for i in 0..<(controlPoints.count - 1) {
                var a = controlPoints[i]
                let b = controlPoints[i+1]
                a.y = min(a.y, b.y) + 0.01

                let seg = b - a
                let segLen = simd_length(seg)
                if segLen <= 0.001 { continue }

                var dist: Float = (spacing - accum)
                if out.isEmpty { dist = 0 }  // first point at segment start

                while dist <= segLen && remaining > 0 {
                    let t = dist / segLen
                    var p = a + t * seg
                    p.y = min(a.y, b.y) + 0.015
                    out.append(p)
                    dist += spacing
                    remaining -= spacing
                }
                let leftover = segLen - ((dist - spacing))
                accum = max(0, spacing - leftover)
                if remaining <= 0 { break }
            }

            // Denser near turns
            var dense: [simd_float3] = []
            for i in 0..<out.count {
                dense.append(out[i])
                if i+2 < out.count {
                    let v1 = simd_normalize(out[i+1] - out[i])
                    let v2 = simd_normalize(out[i+2] - out[i+1])
                    if simd_dot(v1, v2) < 0.75 {
                        let mid = (out[i+1] + out[i+2]) * 0.5
                        dense.append(simd_float3(mid.x, mid.y + 0.003, mid.z))
                    }
                }
            }

            // De-duplicate: enforce a minimum gap so chevrons don't stack
            let minGap = max(0.5 * spacing, 0.35) // at least 35 cm
            var filtered: [simd_float3] = []
            for p in dense {
                if let last = filtered.last, simd_distance(last, p) < minGap { continue }
                filtered.append(p)
            }
            return filtered
        }

        // MARK: - Rendering

        private func renderBreadcrumbs(samplesWorld: [simd_float3], color: UIColor, glow: Bool, pulse: Double) {
            guard let root = breadcrumbsRoot else { return }

            let proto = BreadcrumbArrowFactory.makeBreadcrumbArrowNode(color: color, glow: glow, pulseSeconds: pulse, scale: 1.0)

            let existing = root.childNodes
            let needed = samplesWorld.count
            if existing.count < needed {
                for _ in existing.count..<needed { root.addChildNode(proto.clone()) }
            } else if existing.count > needed {
                for i in stride(from: existing.count - 1, through: needed, by: -1) {
                    existing[i].removeFromParentNode()
                }
            }

            let nodes = root.childNodes
            for (i, p) in samplesWorld.enumerated() {
                guard i < nodes.count else { break }
                let node = nodes[i]
                node.position = SCNVector3(p.x, p.y, p.z)

                // Point the chevron forward along the path (NO 180° flip)
                let nextP = (i + 1 < samplesWorld.count) ? samplesWorld[i+1] : samplesWorld[i]
                let dir = simd_normalize(nextP - p)
                let yaw = atan2(dir.x, dir.z)
                let baseX: Float = -Float.pi / 2  // lay flat on the floor
                node.eulerAngles = SCNVector3(baseX, yaw, 0)
            }
        }

        private func clearBreadcrumbs() { breadcrumbsRoot?.childNodes.forEach { $0.removeFromParentNode() } }

        private func fadeOutBreadcrumbs() {
            guard let root = breadcrumbsRoot else { return }
            let fade = SCNAction.fadeOut(duration: 0.6)
            root.runAction(fade) { [weak root] in
                root?.childNodes.forEach { $0.removeFromParentNode() }
                root?.opacity = 1.0
            }
        }

        private func bloomLastBreadcrumbs() {
            guard let root = breadcrumbsRoot else { return }
            let last = root.childNodes.suffix(4)
            for n in last {
                let up = SCNAction.scale(to: 1.25, duration: 0.15)
                let down = SCNAction.scale(to: 1.0, duration: 0.25)
                n.runAction(.sequence([up, down]))
            }
        }

        // MARK: - Waypoint markers

        func refreshWaypointMarkers(viewModel: NavigationViewModel) {
            guard let root = waypointsRoot else { return }
            root.childNodes.forEach { $0.removeFromParentNode() }
            lastMarkersIndex = viewModel.currentWaypointIndex

            guard case .navigating = viewModel.navigationState,
                  let path = viewModel.currentPath,
                  viewModel.currentWaypointIndex < path.waypoints.count else { return }

            let nextWP = path.waypoints[viewModel.currentWaypointIndex]
            let isAlsoFinal = (nextWP.id == path.waypoints.last?.id)

            if isAlsoFinal {
                // Final destination → show spinning star marker
                let destNode = ARVisualizationHelpers.createDestinationStarMarker(
                    at: nextWP.position,          // simd_float3
                    color: .systemGreen,
                    labelText: "Destination",
                    includeRingShell: true,
                    starSize: 0.34,
                    thickness: 0.014,
                    spinSeconds: 7.0
                )
                destNode.name = "Destination"
                root.addChildNode(destNode)
            } else {
                // Show yellow "Next" ring + green destination ring
                let nextNode = ARVisualizationHelpers.createGlowingRing(at: nextWP.position,
                                                                        color: .systemYellow,
                                                                        labelText: "")
                root.addChildNode(nextNode)

                if let last = path.waypoints.last {
                    let destNode = ARVisualizationHelpers.createGlowingRing(at: last.position,
                                                                            color: .systemGreen,
                                                                            labelText: "")
                    destNode.name = "Destination"
                    root.addChildNode(destNode)
                }
            }
        }

        private func clearWaypointMarkers() { waypointsRoot?.childNodes.forEach { $0.removeFromParentNode() } }
    }
}

// MARK: - Small Double helper
private extension Double {
    func nonZeroOr(_ fallback: Double) -> Double { self == 0 ? fallback : self }
}
