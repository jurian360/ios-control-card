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
