//
//  OpenAIDescriptionService.swift
//  GuideLight v3
//
//  AI-powered room and doorway descriptions for navigation
//  CORRECTED VERSION: Compatible with actual Room and Doorway data models
//

import Foundation

// MARK: - OpenAI Description Service
class OpenAIDescriptionService {
    
    // MARK: - Configuration
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    private let model = "gpt-3.5-turbo"  // Fast and cost-effective
    
    // MARK: - Initialization
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    // MARK: - Room Description Generation
    
    /// Generate intelligent room description for voice announcement
    func generateRoomDescription(for room: Room) async throws -> String {
        let prompt = """
        Create a concise audio description for a blind user entering this room. Focus on practical navigation information:

        Room Details:
        - Name: \(room.name)
        - Type: \(room.type.rawValue.replacingOccurrences(of: "_", with: " "))
        - Floor Surface: \(room.floorSurface.rawValue)
        - Description: \(room.description ?? "none provided")

        Requirements:
        - Maximum 25 words
        - Must mention: "You'll be walking on [floor surface]"
        - Include relevant audio cues based on room type and floor surface
        - Sound natural when spoken aloud
        - Prioritize navigation-relevant information
        - Use present tense and active voice

        Audio context hints by room type:
        - kitchen: mention appliances, potential echo from hard surfaces
        - bathroom: mention water sounds, tile echo if applicable
        - bedroom: mention quiet space, soft surfaces
        - living_room: mention open space
        - hallway: mention corridor, transitional space
        - office: mention quiet workspace
        - garage: mention echo, concrete surfaces typically

        Floor surface audio characteristics:
        - tile/marble: high echo, hard footsteps
        - carpet: low echo, soft footsteps
        - hardwood: medium echo, distinct footsteps
        - concrete: high echo, hard footsteps
        - linoleum: low to medium echo

        Example: "You are in the Kitchen with tile flooring. You'll be walking on tile. Listen for appliances. High echo environment."
        """
        
        return try await generateDescription(prompt: prompt)
    }
    
    // MARK: - Doorway Description Generation
    
    /// Generate intelligent doorway crossing description
    func generateDoorwayDescription(
        doorway: Doorway,
        fromRoomId: UUID,
        toRoomId: UUID,
        fromRoomName: String,
        toRoomName: String
    ) async throws -> String {
        
        let action = doorway.action(from: fromRoomId.uuidString, to: toRoomId.uuidString)
        let doorTypeInfo = doorway.doorType.rawValue.replacingOccurrences(of: "_", with: "-")
        
        let prompt = """
        Create a concise audio instruction for a blind user approaching this doorway:

        Doorway Details:
        - Name: \(doorway.name)
        - Type: \(doorTypeInfo)
        - Action Required: \(action.rawValue)
        - From: \(fromRoomName) → To: \(toRoomName)
        - Door Width: \(String(format: "%.1f", doorway.width))m
        - Audio Landmark: \(doorway.audioLandmark ?? "none")
        - Description: \(doorway.description ?? "none")

        Door type guidance:
        - hinged-left: "Left-hinged door"
        - hinged-right: "Right-hinged door"  
        - sliding: "Sliding door"
        - automatic: "Automatic door"
        - open-doorway: "Open doorway"
        - double-door: "Double door"

        Action instructions:
        - push: "push to open" or "push to enter"
        - pull: "pull to open" or "pull to enter"
        - slide: "slide to open"
        - automatic: "will open automatically"
        - walk_through: "walk through"

        Requirements:
        - Maximum 20 words
        - Must mention the hinge type (left-hinged/right-hinged) if applicable
        - Must specify push/pull action clearly
        - Include door width if narrow (<1.0m) or wide (>1.2m)
        - Sound like natural navigation instructions
        - Use imperative mood (command form)

        Examples:
        - "Right-hinged door, push to enter Kitchen"
        - "Left-hinged door ahead, pull to enter Bedroom"
        - "Wide automatic door to Living Room, will open automatically"
        """
        
        return try await generateDescription(prompt: prompt)
    }
    
    // MARK: - Fallback Descriptions
    
    /// Generate simple room description without AI (fallback)
    func generateSimpleRoomDescription(for room: Room) -> String {
        var components: [String] = []
        
        components.append("You are in the \(room.name)")
        components.append("You'll be walking on \(room.floorSurface.rawValue)")
        
        // Add room-specific audio context based on type
                switch room.type {
                case .kitchen:
                    components.append("Listen for appliances")
                case .bathroom:
                    components.append("Listen for water sounds")
                case .bedroom:
                    components.append("Quiet sleeping area")
                case .living:
                    components.append("Open living space")
                case .hallway:
                    components.append("Corridor passage")
                case .office:
                    components.append("Quiet workspace")
                case .garage:
                    components.append("Large space with echo")
                case .entrance:
                    components.append("Entry area")
                case .lobby:
                    components.append( "Main entrance lobby")
                case .stairwell:
                    components.append( "Staircase")
                case .elevator:
                    components.append( "Elevator")
                case .classroom:
                    components.append( "Schoolroom")
                case .lab:
                    components.append( "Research lab")
                case .cafeteria:
                    components.append( "Cafeteria")
                case .auditorium:
                    components.append( "Auditorium")
                case .storage:
                    components.append("Storage area")
                case .laundry:
                    components.append("Utility room")
                case .general:
                    break // No specific context
                }
        
        // Add floor surface audio hints
        switch room.floorSurface {
        case .tile, .marble:
            components.append("High echo environment")
        case .carpet:
            components.append("Low echo, soft surface")
        case .hardwood:
            components.append("Medium echo")
        case .concrete:
            components.append("High echo, hard surface")
        case .linoleum:
            components.append("Low echo")
        }
        
        return components.joined(separator: ". ") + "."
    }
    
    /// Generate simple doorway description without AI (fallback)
    func generateSimpleDoorwayDescription(
        doorway: Doorway,
        fromRoomId: UUID,
        toRoomId: UUID,
        toRoomName: String
    ) -> String {
        let action = doorway.action(from: fromRoomId.uuidString, to: toRoomId.uuidString)
        
        var doorDescription = ""
        switch doorway.doorType {
        case .hinged_left:
            doorDescription = "Left-hinged door"
        case .hinged_right:
            doorDescription = "Right-hinged door"
        case .sliding:
            doorDescription = "Sliding door"
        case .automatic:
            doorDescription = "Automatic door"
        case .open_doorway:
            doorDescription = "Open doorway"
        case .double_door:
            doorDescription = "Double door"
        case .swinging_both:
            doorDescription = "Swinging door"
        }
        
        var actionDescription = ""
        switch action {
        case .push:
            actionDescription = "push to open"
        case .pull:
            actionDescription = "pull to open"
        case .slide:
            actionDescription = "slide to open"
        case .automatic:
            actionDescription = "will open automatically"
        case .walkThrough:
            actionDescription = "walk through"
        }
        
        return "\(doorDescription), \(actionDescription) to enter \(toRoomName)"
    }
    
    // MARK: - Private OpenAI API Call
    
    private func generateDescription(prompt: String) async throws -> String {
        let requestBody = OpenAIRequest(
            model: model,
            messages: [
                OpenAIMessage(role: "system", content: "You are an expert in creating concise, practical audio navigation instructions for blind users."),
                OpenAIMessage(role: "user", content: prompt)
            ],
            max_tokens: 60,  // Keep responses short
            temperature: 0.3  // Low creativity for consistency
        )
        
        let jsonData = try JSONEncoder().encode(requestBody)
        
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OpenAIError.apiError("API request failed")
        }
        
        let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        
        guard let content = openAIResponse.choices.first?.message.content else {
            throw OpenAIError.noContent
        }
        
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - OpenAI API Models

struct OpenAIRequest: Codable {
    let model: String
    let messages: [OpenAIMessage]
    let max_tokens: Int
    let temperature: Double
}

struct OpenAIMessage: Codable {
    let role: String
    let content: String
}

struct OpenAIResponse: Codable {
    let choices: [OpenAIChoice]
}

struct OpenAIChoice: Codable {
    let message: OpenAIMessage
}

// MARK: - Error Handling

enum OpenAIError: Error, LocalizedError {
    case apiError(String)
    case noContent
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .apiError(let message):
            return "OpenAI API Error: \(message)"
        case .noContent:
            return "No content received from OpenAI"
        case .networkError:
            return "Network error occurred"
        }
    }
}
