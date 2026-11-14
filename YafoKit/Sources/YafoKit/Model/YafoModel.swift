import CoreData
import Foundation

/// Das Core-Data-Modell, im Code statt als .xcdatamodeld, damit es im Swift Package
/// ohne Xcode-Compiler funktioniert und im Review lesbar ist.
///
/// Zwei Konfigurationen: `Cloud` für den privaten und den geteilten Store (CloudKit),
/// `Local` für den Abo-Cache, der nie synchronisiert wird.
nonisolated public enum YafoModel {
    public static let cloudConfiguration = "Cloud"
    public static let localConfiguration = "Local"

    /// Ein Modell pro Prozess, sonst meldet Core Data mehrdeutige Entitäten.
    /// Nach dem ersten Laden ist das Modell unveränderlich, daher threadsicher.
    nonisolated(unsafe) public static let shared: NSManagedObjectModel = makeModel()

    private static func makeModel() -> NSManagedObjectModel {
        let family = entity(Family.self, [
            uuid("id"), string("name"), date("createdAt")
        ])
        let member = entity(Member.self, [
            uuid("id"), string("displayName"), string("initials"),
            string("kindRaw", default: MemberKind.adult.rawValue),
            string("cloudKitUserID"), date("leftAt"), date("createdAt")
        ])
        let calendar = entity(EventCalendar.self, [
            uuid("id"), string("name"),
            string("kindRaw", default: CalendarKind.personal.rawValue),
            string("defaultColor"), date("createdAt")
        ])
        let event = entity(Event.self, [
            uuid("id"), string("title"), date("start"), date("end"),
            bool("isAllDay"), string("timeZone"), string("location"), string("notes"),
            string("recurrenceRule"), string("createdBy"), string("importUID"),
            double("defaultAlertOffset", default: AlertDefaults.timedEventOffset),
            date("createdAt"), date("updatedAt"),
            string("kindRaw", default: EventKind.event.rawValue), int64("birthYear")
        ])
        let exception = entity(EventException.self, [
            uuid("id"), date("originalDate"), bool("isCancelled"),
            string("title"), date("start"), date("end"), string("location"), string("notes")
        ])
        let comment = entity(Comment.self, [
            uuid("id"), string("text"), date("createdAt"), date("editedAt")
        ])
        let shopping = entity(ShoppingItem.self, [
            uuid("id"), string("name"), string("quantity"), bool("isChecked"),
            date("checkedAt"), double("sortKey"), date("createdAt"),
            string("categoryRaw")
        ])
        let todo = entity(TodoItem.self, [
            uuid("id"), string("title"), date("dueDate"), bool("isDone"), date("doneAt"),
            string("createdBy"), string("recurrenceRule"),
            double("defaultAlertOffset", default: AlertDefaults.todoOffset),
            date("createdAt")
        ])
        let subscription = entity(CalendarSubscription.self, [
            uuid("id"), string("sourceKey"), string("url"), string("kindRaw"),
            string("region"), string("name"), date("createdAt")
        ])
        let subscribedEvent = entity(SubscribedEvent.self, [
            uuid("id"), string("sourceKey"), string("uid"), string("title"),
            date("start"), date("end"), bool("isAllDay"), string("location"), date("fetchedAt")
        ])
        let appearance = entity(CalendarAppearance.self, [
            uuid("id"), string("calendarID"), string("color"), bool("isVisible", default: true),
            string("eventStyleRaw")
        ])
        let alertPreference = entity(AlertPreference.self, [
            uuid("id"), string("itemID"), double("alertOffset"), bool("isMuted")
        ])
        let readState = entity(ReadState.self, [
            uuid("id"), string("familyID"), date("lastSeenAt")
        ])
        let ownerTransfer = entity(OwnerTransfer.self, [
            uuid("id"), string("newOwnerID"), string("statusRaw"), string("newShareURL"),
            date("startedAt")
        ])

        // Beziehungen. Löschregeln: was an der Familie bzw. am Termin hängt, geht mit.
        relate(family, "members", toMany: true, delete: .cascadeDeleteRule,
               member, "family", toMany: false, inverseDelete: .nullifyDeleteRule)
        relate(family, "calendars", toMany: true, delete: .cascadeDeleteRule,
               calendar, "family", toMany: false, inverseDelete: .nullifyDeleteRule)
        relate(family, "shoppingItems", toMany: true, delete: .cascadeDeleteRule,
               shopping, "family", toMany: false, inverseDelete: .nullifyDeleteRule)
        relate(family, "todoItems", toMany: true, delete: .cascadeDeleteRule,
               todo, "family", toMany: false, inverseDelete: .nullifyDeleteRule)
        relate(family, "ownerTransfers", toMany: true, delete: .cascadeDeleteRule,
               ownerTransfer, "family", toMany: false, inverseDelete: .nullifyDeleteRule)
        relate(calendar, "events", toMany: true, delete: .cascadeDeleteRule,
               event, "calendar", toMany: false, inverseDelete: .nullifyDeleteRule)
        relate(calendar, "subscriptions", toMany: true, delete: .cascadeDeleteRule,
               subscription, "calendar", toMany: false, inverseDelete: .nullifyDeleteRule)
        relate(event, "participants", toMany: true, delete: .nullifyDeleteRule,
               member, "events", toMany: true, inverseDelete: .nullifyDeleteRule)
        relate(event, "exceptions", toMany: true, delete: .cascadeDeleteRule,
               exception, "event", toMany: false, inverseDelete: .nullifyDeleteRule)
        relate(event, "comments", toMany: true, delete: .cascadeDeleteRule,
               comment, "event", toMany: false, inverseDelete: .nullifyDeleteRule)
        relate(member, "comments", toMany: true, delete: .nullifyDeleteRule,
               comment, "author", toMany: false, inverseDelete: .nullifyDeleteRule)
        relate(member, "assignedTodos", toMany: true, delete: .nullifyDeleteRule,
               todo, "assignee", toMany: false, inverseDelete: .nullifyDeleteRule)

        let cloudEntities = [family, member, calendar, event, exception, comment, shopping, todo,
                             subscription, appearance, alertPreference, readState, ownerTransfer]
        let model = NSManagedObjectModel()
        model.entities = cloudEntities + [subscribedEvent]
        model.setEntities(cloudEntities, forConfigurationName: cloudConfiguration)
        model.setEntities([subscribedEvent], forConfigurationName: localConfiguration)
        return model
    }

    // MARK: - Bausteine

    private static func entity(_ type: NSManagedObject.Type,
                               _ attributes: [NSAttributeDescription]) -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = String(describing: type)
        entity.managedObjectClassName = NSStringFromClass(type)
        entity.properties = attributes
        return entity
    }

    private static func attribute(_ name: String, _ type: NSAttributeDescription.AttributeType,
                                  default value: Any? = nil) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.type = type
        attribute.isOptional = true
        attribute.defaultValue = value
        return attribute
    }

    private static func uuid(_ name: String) -> NSAttributeDescription { attribute(name, .uuid) }
    private static func date(_ name: String) -> NSAttributeDescription { attribute(name, .date) }

    private static func string(_ name: String, default value: String? = nil) -> NSAttributeDescription {
        attribute(name, .string, default: value)
    }

    private static func bool(_ name: String, default value: Bool = false) -> NSAttributeDescription {
        attribute(name, .boolean, default: value)
    }

    private static func int64(_ name: String, default value: Int64 = 0) -> NSAttributeDescription {
        attribute(name, .integer64, default: value)
    }

    private static func double(_ name: String, default value: Double = 0) -> NSAttributeDescription {
        attribute(name, .double, default: value)
    }

    private static func relate(_ source: NSEntityDescription, _ name: String, toMany: Bool,
                               delete: NSDeleteRule,
                               _ destination: NSEntityDescription, _ inverseName: String,
                               toMany inverseToMany: Bool, inverseDelete: NSDeleteRule) {
        let forward = relationship(name, to: destination, toMany: toMany, delete: delete)
        let inverse = relationship(inverseName, to: source, toMany: inverseToMany, delete: inverseDelete)
        forward.inverseRelationship = inverse
        inverse.inverseRelationship = forward
        source.properties.append(forward)
        destination.properties.append(inverse)
    }

    private static func relationship(_ name: String, to destination: NSEntityDescription,
                                     toMany: Bool, delete: NSDeleteRule) -> NSRelationshipDescription {
        let relationship = NSRelationshipDescription()
        relationship.name = name
        relationship.destinationEntity = destination
        relationship.isOptional = true
        relationship.minCount = 0
        relationship.maxCount = toMany ? 0 : 1
        relationship.deleteRule = delete
        return relationship
    }
}
