//
//  ServerJobResult.swift
//  funico-server-core
//
//  Created by Damian Van de Kauter on 07/08/2026.
//

import Foundation

/// How a job run ended.
///
/// This type exists to fix a defect that is currently shipping. `InvoiceJob+Scheduler.swift`
/// maps *every* finished job to `.canceled`, so a job that succeeded and a job that blew up
/// are displayed identically — "Canceled" — and the user has no way to tell them apart.
///
/// The distinction rides on `ServerEventEnvelope`. It cannot ride on the legacy
/// `"id;iso8601"` codec, which has exactly one terminal state and no room for a reason.
public enum ServerJobResult: Sendable, Hashable, Codable {

    case completed
    case cancelled
    case failed(String)

    public var isSuccess: Bool {
        self == .completed
    }

    /// Human-readable label. `failed` deliberately does not inline the reason — a message
    /// of arbitrary length does not belong in a status chip.
    public var title: String {
        switch self {
        case .completed: "Completed"
        case .cancelled: "Cancelled"
        case .failed: "Failed"
        }
    }

    public var failureReason: String? {
        switch self {
        case .failed(let reason): reason
        case .completed, .cancelled: nil
        }
    }
}
