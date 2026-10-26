import Foundation

// MARK: - Typed formula evaluator (v1, Foundation-only)
//
// This is NOT Apple Math Notes: there is no public Math Notes API for
// third-party apps, so InkNote evaluates typed expressions itself.
// Handwritten formula recognition is a future stage (see FutureServices);
// this evaluator is the second stage of that pipeline (expression ->
// result) and is already usable for typed formulas in v1.
//
// Grammar: expression := term (('+'|'-') term)*
//          term       := factor (('*'|'/'|'%') factor)*
//          factor     := number | variable | '(' expression ')' | '-' factor
// Variables are supplied by the caller. Unknown variables and division
// by zero are errors, never silent zeros.

public enum FormulaError: Error, LocalizedError {
    case empty
    case unexpectedCharacter(Character)
    case unexpectedEnd
    case unknownVariable(String)
    case divisionByZero
    public var errorDescription: String? {
        switch self {
        case .empty: return String(localized: "Empty expression")
        case .unexpectedCharacter(let c): return String(format: String(localized: "Unexpected character '%@'"), String(c))
        case .unexpectedEnd: return String(localized: "Unexpected end of expression")
        case .unknownVariable(let v): return String(format: String(localized: "Unknown variable '%@'"), v)
        case .divisionByZero: return String(localized: "Division by zero")
        }
    }
}

public struct FormulaEvaluator {
    public static func evaluate(_ expression: String, variables: [String: Double] = [:]) throws -> Double {
        let chars = Array(expression.filter { !$0.isWhitespace })
        guard !chars.isEmpty else { throw FormulaError.empty }
        var parser = Parser(chars: chars, variables: variables)
        let value = try parser.parseExpression()
        guard parser.index == chars.count else {
            throw FormulaError.unexpectedCharacter(chars[parser.index])
        }
        return value
    }

    private struct Parser {
        var chars: [Character]
        var variables: [String: Double]
        var index = 0

        mutating func parseExpression() throws -> Double {
            var value = try parseTerm()
            while index < chars.count, chars[index] == "+" || chars[index] == "-" {
                let op = chars[index]; index += 1
                let rhs = try parseTerm()
                value = (op == "+") ? value + rhs : value - rhs
            }
            return value
        }
        mutating func parseTerm() throws -> Double {
            var value = try parseFactor()
            while index < chars.count, chars[index] == "*" || chars[index] == "/" || chars[index] == "%" {
                let op = chars[index]; index += 1
                let rhs = try parseFactor()
                if op == "*" { value *= rhs }
                else if op == "/" {
                    guard rhs != 0 else { throw FormulaError.divisionByZero }
                    value /= rhs
                } else { value = value.truncatingRemainder(dividingBy: rhs) }
            }
            return value
        }
        mutating func parseFactor() throws -> Double {
            guard index < chars.count else { throw FormulaError.unexpectedEnd }
            let c = chars[index]
            if c == "-" { index += 1; return -(try parseFactor()) }
            if c == "(" {
                index += 1
                let value = try parseExpression()
                guard index < chars.count, chars[index] == ")" else { throw FormulaError.unexpectedEnd }
                index += 1
                return value
            }
            if c.isNumber || c == "." {
                var text = ""
                while index < chars.count, chars[index].isNumber || chars[index] == "." {
                    text.append(chars[index]); index += 1
                }
                guard let value = Double(text) else { throw FormulaError.unexpectedCharacter(c) }
                return value
            }
            if c.isLetter || c == "_" {
                var name = ""
                while index < chars.count, chars[index].isLetter || chars[index].isNumber || chars[index] == "_" {
                    name.append(chars[index]); index += 1
                }
                guard let value = variables[name] else { throw FormulaError.unknownVariable(name) }
                return value
            }
            throw FormulaError.unexpectedCharacter(c)
        }
    }
}
