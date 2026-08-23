//
//  Rally+CoreDataProperties.swift
//  Control Card
//
//  Created by Raoul Brahim on 11-03-2025.
//
//

import Foundation
import CoreData


extension Rally {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Rally> {
        return NSFetchRequest<Rally>(entityName: "Rally")
    }

    @NSManaged public var rallyCode: String?
    @NSManaged public var rallyName: String?
    @NSManaged public var eqNumber: Int16
    @NSManaged public var eqId: Int16
    @NSManaged public var cardNumber: Int16
    /// The stage's own name, as the points system calls it.
    @NSManaged public var cardName: String?
    /// Driver / navigator of this equipe, when the entry list holds them.
    @NSManaged public var crewName: String?
    @NSManaged public var cardId: Int16
    @NSManaged public var isFinalized: Bool
    @NSManaged public var controlecards: NSSet?

}

// MARK: Generated accessors for controlecards
extension Rally {

    @objc(addControlecardsObject:)
    @NSManaged public func addToControlecards(_ value: ControlCard)

    @objc(removeControlecardsObject:)
    @NSManaged public func removeFromControlecards(_ value: ControlCard)

    @objc(addControlecards:)
    @NSManaged public func addToControlecards(_ values: NSSet)

    @objc(removeControlecards:)
    @NSManaged public func removeFromControlecards(_ values: NSSet)

}

extension Rally : Identifiable {

}
