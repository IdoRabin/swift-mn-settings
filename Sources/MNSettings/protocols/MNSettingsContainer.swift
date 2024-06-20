//
//  File.swift
//  
//
// Created by Ido Rabin for Bricks on 17/1/2024.

import Foundation

typealias AnyMNSettingsContainer = any MNSettingsContainer

protocol MNSettingsElement {
    var name : String { get }
}

protocol MNSettingsContainer : AnyObject, MNSettingsElement {

    init(name:MNSKey)
    
    
    
    
}
