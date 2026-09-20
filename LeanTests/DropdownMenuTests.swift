import Testing
@testable import Lean

struct DropdownMenuTests {
    @Test("Presentation binding opens and closes the requested menu")
    @MainActor
    func presentationBindingTracksMenu() {
        let state = DropdownMenuState()
        let binding = state.presentationBinding(for: "font")

        binding.wrappedValue = true
        #expect(state.activeId == "font")
        #expect(binding.wrappedValue)

        binding.wrappedValue = false
        #expect(state.activeId == nil)
    }

    @Test("Opening another dropdown replaces the active menu")
    @MainActor
    func onlyOneMenuIsActive() {
        let state = DropdownMenuState()

        state.toggle("font")
        state.toggle("search")

        #expect(!state.isActive("font"))
        #expect(state.isActive("search"))
    }
}
