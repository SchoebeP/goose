import SwiftUI

func firstNumber(in text: String) -> Double? {
  var buffer = ""
  var hasStarted = false

  for character in text {
    if character.isNumber || character == "." || character == "-" {
      buffer.append(character)
      hasStarted = true
      continue
    }
    if hasStarted {
      break
    }
  }

  return Double(buffer)
}
