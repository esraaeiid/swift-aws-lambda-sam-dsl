//
//
//
//

import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

extension DeploymentDescriptorGenerator {
    func generatePatternPropertyDeclaration(for name: String, with type: JSONType, isRequired: Bool) -> MemberBlockItemListSyntax {
        var memberDecls = [MemberBlockItemListSyntax]()

        // TODO: handle regex pattern with function
        // TODO: handle min,max Properties
        if let objectSchema = type.object() {
            if let patternProperties = objectSchema.patternProperties {
                for (pattern, patternValue) in patternProperties {
                    if case .anyOf(let jsonTypes) = patternValue {
                        print("🏓 I am Generate Declaration with 'patternProperties' and 'hasAnyOf' for: \(name)")
                        memberDecls.append(self.generateAnyOfDeclaration(for: name, with: jsonTypes, isRequired: isRequired))
                    } else if case .type(let jsonType) = patternValue {
                        if let stringSchema = jsonType.stringSchema() {
                            let swiftType = jsonType.swiftType(for: name)
                            memberDecls.append(MemberBlockItemListSyntax { generateDictionaryVariable(for: name, with: swiftType, isRequired: isRequired) })
                            print("🏓 I am Generate Declaration with 'type', 'String' for: \(name))")
                        } else  if let object = jsonType.object() {
                            let properties = object.properties ?? [:]
                            let structDecl = generateStructDeclaration(for: name, with: properties, isRequired: type.required)
                            memberDecls.append(MemberBlockItemListSyntax { structDecl }.with(\.leadingTrivia, .newlines(2)))
                            
                            let variableDecl = generateDictionaryVariable(for: name,
                                                                          with: jsonType.swiftType(for: name),
                                                                          isRequired: isRequired)
                            memberDecls.append(MemberBlockItemListSyntax { variableDecl })
                            print("🏓 I am Generate Declaration with 'object' for: \(name)")
                            
                        }  else  if let reference = jsonType.reference {
                            print("🏓 I am Generate Declaration with 'reference' for: \(name)")
                            let referenceType = reference.contains(":") ? reference.toSwiftAWSEnumCase() :
                            String(reference.split(separator: "/").last ?? "unknown")
                            let variableDecl = generateDictionaryVariable(for: name, with: referenceType, isRequired: isRequired)
                            memberDecls.append(MemberBlockItemListSyntax { variableDecl })
                        }
                    }
                }
            }
        }

        print("🏓 I am PatternProperty for: \(name)")
        return MemberBlockItemListSyntax {
            for memberDecl in memberDecls {
                memberDecl
            }
        }
    }
}