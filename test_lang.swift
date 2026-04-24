import Foundation
import Translation

@available(macOS 15.0, *)
func test() async {
    let availability = LanguageAvailability()
    let langs = await availability.supportedLanguages
    for lang in langs {
        print(lang.minimalIdentifier)
    }
}

if #available(macOS 15.0, *) {
    let sema = DispatchSemaphore(value: 0)
    Task {
        await test()
        sema.signal()
    }
    sema.wait()
}
