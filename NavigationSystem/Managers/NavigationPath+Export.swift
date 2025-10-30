//
//  NavigationPath+Export.swift
//  GuideLight v3
//
//  Created by Indraneel Rakshit on 10/23/25.
//

import Foundation
import simd

extension NavigationPath {
    /// Debug-only JSON for logs: includes doorwayId + inferred from/to room IDs
    /// Pass `map` so we can look up doorways and their connected rooms.
    func toDebugJSON(map: IndoorMap) -> [String: Any] {
        var nodes: [[String: Any]] = []

        for (idx, wp) in waypoints.enumerated() {
            var node: [String: Any] = [
                "step": idx + 1,
                "nodeId": wp.id.uuidString,
                "nodeName": wp.name,
                "nodeType": wp.type.rawValue,
                "position": [
                    "x": wp.position.x,
                    "y": wp.position.y,
                    "z": wp.position.z
                ],
                "roomId": wp.roomId ?? ""
            ]

            // Include distanceToNext if you track it in memory (optional)
            if idx < waypoints.count - 1 {
                let d = simd_distance(wp.position, waypoints[idx + 1].position)
                node["distanceToNext"] = d
            }

            // Extra fields for doorway nodes
            if wp.type == .doorway, let did = wp.doorwayId {
                node["doorwayId"] = did

                // Infer from/to for debugging: prefer neighbor waypoint rooms
                var fromRoomId: String?
                var toRoomId: String?

                if idx > 0 {
                    fromRoomId = waypoints[idx - 1].roomId
                }
                if idx < waypoints.count - 1 {
                    toRoomId = waypoints[idx + 1].roomId
                }

                // If neighbors were not informative, use the doorway connectivity
                if fromRoomId == nil || toRoomId == nil,
                   let door = map.doorways.first(where: { $0.id.uuidString == did }) {

                    let a = door.connectsRooms.roomA
                    let b = door.connectsRooms.roomB

                    if fromRoomId == nil && toRoomId != nil {
                        fromRoomId = (toRoomId == a) ? b : a
                    } else if toRoomId == nil && fromRoomId != nil {
                        toRoomId = (fromRoomId == a) ? b : a
                    } else if fromRoomId == nil && toRoomId == nil {
                        // Fallback: preserve intended direction based on path index parity,
                        // or just pick A->B (debug-only field).
                        fromRoomId = a
                        toRoomId = b
                    }
                }

                if let f = fromRoomId { node["from_room_id"] = f }
                if let t = toRoomId   { node["to_room_id"]   = t }
            }

            nodes.append(node)
        }

        return [
            "pathCalculated": Date().timeIntervalSince1970,
            "startNode": waypoints.first?.name ?? "",
            "endNode": waypoints.last?.name ?? "",
            "totalSteps": waypoints.count,
            "totalDistance": totalDistance,
            "path": nodes
        ]
    }
}
