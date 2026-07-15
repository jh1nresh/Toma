import Foundation
import UserNotifications

protocol ReminderScheduling {
    func requestAuthorization() async -> Bool
    func scheduleTomorrowMorning(for plan: TomorrowPlan, identifier: String) async throws
    func cancel(identifier: String)
    func isPending(identifier: String) async -> Bool
    func isDelivered(identifier: String) async -> Bool
}

struct LocalReminderScheduler: ReminderScheduling {
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) == true
        @unknown default:
            return false
        }
    }

    func scheduleTomorrowMorning(for plan: TomorrowPlan, identifier: String) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Toma 幫你準備好了"
        content.body = plan.items.first(where: \.isEnabled)?.text ?? "打開電子雞看看明日計畫。"
        content.sound = .default

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        var components = Calendar.current.dateComponents([.year, .month, .day], from: tomorrow)
        components.hour = 8
        components.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try await center.add(request)
    }

    func cancel(identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    func isPending(identifier: String) async -> Bool {
        await center.pendingNotificationRequests().contains { $0.identifier == identifier }
    }

    func isDelivered(identifier: String) async -> Bool {
        await center.deliveredNotifications().contains { $0.request.identifier == identifier }
    }
}
