//
//  ControlCard+CoreDataProperties.swift
//  Control Card
//
//  Created by Raoul Brahim on 11-03-2025.
//
//

import Foundation
import CoreData


extension ControlCard {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ControlCard> {
        return NSFetchRequest<ControlCard>(entityName: "ControlCard")
    }

    @NSManaged public var timestamp: Date?
    @NSManaged public var row: Int16
    @NSManaged public var col1: String?
    @NSManaged public var col2: String?
    @NSManaged public var col3: String?
    @NSManaged public var col4: String?
    @NSManaged public var col1Locked: Bool
    @NSManaged public var col2Locked: Bool
    @NSManaged public var col3Locked: Bool
    @NSManaged public var col4Locked: Bool
    @NSManaged public var rowLocked: Bool
    @NSManaged public var rally: Rally?

}

extension ControlCard : Identifiable {

}
