//
//  File.swift
//  
//
//  Created by Ido on 30/08/2023.
//

import Foundation

typealias AnyMNSettingsContainer = any MNSettingsContainer

protocol MNSettingsElement {
    var name : String { get }
}

protocol MNSettingsContainer : AnyObject, MNSettingsElement {

    init(name:MNSKey)
    
    
    
    
}
