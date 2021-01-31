//
//  SVGView.swift
//  SVGView
//
//  Created by Alisa Mylnikova on 20/07/2020.
//

import SwiftUI

public struct SVGParser {

    static public func parse(fileURL: URL) -> SVGNode {
        let xml = DOMParser.parse(fileURL: fileURL)
        return parse(xml: xml)
    }

    static public func parse(xml: XMLElement) -> SVGNode {
        let defMap = createDefMap(xml: xml)
        return parseInternal(xml: xml, defMap: defMap)!
    }

    static func parseInternal(xml: XMLElement, defMap: [String: XMLElement], ignoreDefs: Bool = true) -> SVGNode? {
        if ignoreDefs, SVGConstants.defTags.contains(xml.name) {
            return nil
        }

        let styleDict = xml.attributes.filter { SVGConstants.availableStyleAttributes.contains($0.key) }
        let nonStyleDict = xml.attributes.filter { !SVGConstants.availableStyleAttributes.contains($0.key) }

        let collector = SVGAttributesCollector.shared
        collector.styleStack.pushStyle(styleDict)

        var result: SVGNode?
        let contents = xml.contents.compactMap { $0 as? XMLElement }
        if isGroup(xml: xml) { // group
            var nodes = [SVGNode]()
            for child in contents {
                if let node = parseInternal(xml: child, defMap: defMap, ignoreDefs: ignoreDefs) {
                    nodes.append(node)
                }
            }
            if let svg = parseViewport(nonStyleDict, nodes) {
                result = svg
            } else {
                result = SVGGroup(contents: nodes)
            }
        }
        else {
            let collectedStyle = collector.styleStack.currentStyle()
            if xml.name == "use", // def
               let useId = nonStyleDict["xlink:href"]?.replacingOccurrences(of: "#", with: ""),
               let def = defMap[useId],
               let useNode = parseInternal(xml: def, defMap: defMap, ignoreDefs: ignoreDefs) {

                useNode.transform = CGAffineTransform(
                    translationX: SVGHelper.parseCGFloat(nonStyleDict, "x"),
                    y: SVGHelper.parseCGFloat(nonStyleDict, "y"))
                result = useNode
            }
            else { // simple node
                result = SVGHelper.parseNode(xml: xml, attributes: nonStyleDict, style: collectedStyle)
            }
        }

        let transform = SVGHelper.parseTransform(nonStyleDict["transform"] ?? "")
        result?.transform = result?.transform.concatenating(transform) ?? CGAffineTransform.identity

        result?.opacity = SVGHelper.parseOpacity(styleDict, "opacity")

        if let clipId = SVGHelper.parseUse(styleDict["clip-path"]),
           let clipNode = defMap[clipId],
           let clip = parseInternal(xml: clipNode, defMap: defMap, ignoreDefs: false) {
            result?.clip = SVGUserSpaceNode(node: clip, userSpace: parse(userSpace: clipNode.attributes["clipPathUnits"]))
        }

        result?.id = SVGHelper.parseId(nonStyleDict)

        collector.styleStack.popStyle()

        return result
    }

    static func isGroup(xml: XMLElement) -> Bool {
        switch xml.name {
        case "g", "svg":
            return true
        default:
            return false
        }
    }

    static func parseViewport(_ attributes: [String : String], _ nodes: [SVGNode]) -> SVGViewport? {
        let widthAttributeNil = attributes["width"] == nil
        let heightAttributeNil = attributes["height"] == nil
        let viewBoxAttributeNil = attributes["viewBox"] == nil

        if widthAttributeNil && heightAttributeNil && viewBoxAttributeNil {
            return .none
        }

        let w = SVGHelper.parseDimension(attributes, "width") ?? SVGLength(percent: 100)
        let h = SVGHelper.parseDimension(attributes, "height") ?? SVGLength(percent: 100)

        var viewBox: CGRect?
        if let viewBoxString = attributes["viewBox"] {
            let nums = viewBoxString.components(separatedBy: .whitespaces).map { Double($0) }
            if nums.count == 4, let x = nums[0], let y = nums[1], let w = nums[2], let h = nums[3] {
                viewBox = CGRect(x: x, y: y, width: w, height: h)
            }
        }

        let par = SVGHelper.parsePreserveAspectRation(string: attributes["preserveAspectRatio"])
        return SVGViewport(width: w, height: h, viewBox: viewBox, preserveAspectRatio: par, contents: nodes)
    }

    static func parse(userSpace: String?) -> SVGUserSpaceNode.UserSpace {
        if let value = userSpace, let result = SVGUserSpaceNode.UserSpace(rawValue: value) {
            return result
        }
        return SVGUserSpaceNode.UserSpace.objectBoundingBox
    }
 
    static func createDefMap(xml: XMLElement) -> [String: XMLElement] {
        var map = [String: XMLElement]()
        createDefMapRecursive(xml: xml, map: &map)
        return map
    }

    static func createDefMapRecursive(xml: XMLElement, map: inout [String: XMLElement]) {
        if let id = SVGHelper.parseId(xml.attributes){
            map[id] = xml
        }
        if xml.contents.count > 0 { // group
            for child in xml.contents {
                if let child = child as? XMLElement {
                    createDefMapRecursive(xml: child, map: &map)
                }
            }
        }
    }
}

class SVGAttributesCollector {

    let styleStack = StyleStack()

    static let shared = SVGAttributesCollector()
}