//
//  PreferencesAccounts.swift
//  Balance
//
//  Created by Christian Baroni on 2/14/17.
//  Copyright © 2017 Balance. All rights reserved.
//
//  Generated by PaintCode
//  http://www.paintcodeapp.com
//



import Cocoa

public struct PreferencesAccounts {

    //// Drawing Methods

    public static func drawAccountPreferencesBackground(frame: NSRect = NSRect(x: 0, y: 0, width: 193, height: 252)) {
        //// Color Declarations
        let shadowBaseColor = NSColor(deviceRed: 0.761, green: 0.761, blue: 0.761, alpha: 1)

        //// Shadow Declarations
        let whiteShadow = NSShadow()
        whiteShadow.shadowColor = NSColor.white.withAlphaComponent(0.36)
        whiteShadow.shadowOffset = NSSize(width: 0, height: -0.5)
        whiteShadow.shadowBlurRadius = 0

        //// shadowBase Drawing
        let shadowBasePath = NSBezierPath(roundedRect: NSRect(x: frame.minX + 0.5, y: frame.minY + 0.5, width: frame.width - 1, height: frame.height - 1), xRadius: 5.5, yRadius: 5.5)
        NSGraphicsContext.saveGraphicsState()
        whiteShadow.set()
        shadowBaseColor.setFill()
        shadowBasePath.fill()
        NSGraphicsContext.restoreGraphicsState()



        //// innerBase Drawing
        let innerBasePath = NSBezierPath(roundedRect: NSRect(x: frame.minX + 1, y: frame.minY + 1, width: frame.width - 2, height: frame.height - 2), xRadius: 5, yRadius: 5)
        NSColor.white.setFill()
        innerBasePath.fill()
    }

    public static func drawSelectedAccount(frame targetFrame: NSRect = NSRect(x: 0, y: 0, width: 185, height: 31)) {
        //// General Declarations
        let context = NSGraphicsContext.current!.cgContext
        
        //// Resize to Target Frame
        NSGraphicsContext.saveGraphicsState()
        let resizing = ResizingBehavior.aspectFit
        let resizedFrame: NSRect = resizing.apply(rect: NSRect(x: 0, y: 0, width: 185, height: 31), target: targetFrame)
        context.translateBy(x: resizedFrame.minX, y: resizedFrame.minY)
        context.scaleBy(x: resizedFrame.width / 185, y: resizedFrame.height / 31)


        //// Color Declarations
        let selectedColor = NSColor(deviceRed: 0, green: 0.443, blue: 0.922, alpha: 1)

        //// selectedBackground Drawing
        let selectedBackgroundPath = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 185, height: 31), xRadius: 4, yRadius: 4)
        selectedColor.setFill()
        selectedBackgroundPath.fill()
        
        NSGraphicsContext.restoreGraphicsState()

    }

    public static func drawAccountColorCircle(frame targetFrame: NSRect = NSRect(x: 0, y: 0, width: 9, height: 9), color: NSColor) {
        //// General Declarations
        let context = NSGraphicsContext.current!.cgContext
        let resizing = ResizingBehavior.aspectFit
        
        //// Resize to Target Frame
        NSGraphicsContext.saveGraphicsState()
        let resizedFrame: NSRect = resizing.apply(rect: NSRect(x: 0, y: 0, width: 9, height: 9), target: targetFrame)
        context.translateBy(x: resizedFrame.minX, y: resizedFrame.minY)
        context.scaleBy(x: resizedFrame.width / 9, y: resizedFrame.height / 9)


        //// circle Drawing
        let circlePath = NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: 9, height: 9))
        color.setFill()
        circlePath.fill()
        
        NSGraphicsContext.restoreGraphicsState()

    }
}
