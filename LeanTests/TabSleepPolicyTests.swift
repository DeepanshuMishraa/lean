import Testing
@testable import Lean

struct TabSleepPolicyTests {
    @Test("Only inactive tabs without protected activity may sleep")
    func protectsTabActivity() {
        let safe = TabSleepConditions(
            isSelected: false,
            isLoading: false,
            hasActiveDownload: false,
            isPlayingMedia: false,
            isCapturingMedia: false,
            hasUnsavedFormInput: false
        )
        #expect(safe.canSleep)
        var popupOpener = safe
        popupOpener.hasActivePopup = true
        #expect(!popupOpener.canSleep)
        #expect(TabSleepPolicy.canCommitSleep(safe, isStillInactive: true))
        #expect(!TabSleepPolicy.canCommitSleep(safe, isStillInactive: false))
        let becameDirty = TabSleepConditions(
            isSelected: false,
            isLoading: false,
            hasActiveDownload: false,
            isPlayingMedia: false,
            isCapturingMedia: false,
            hasUnsavedFormInput: true
        )
        #expect(!TabSleepPolicy.canCommitSleep(becameDirty, isStillInactive: true))
        #expect(!TabSleepConditions(isSelected: true, isLoading: false, hasActiveDownload: false, isPlayingMedia: false, isCapturingMedia: false, hasUnsavedFormInput: false).canSleep)
        #expect(!TabSleepConditions(isSelected: false, isLoading: true, hasActiveDownload: false, isPlayingMedia: false, isCapturingMedia: false, hasUnsavedFormInput: false).canSleep)
        #expect(!TabSleepConditions(isSelected: false, isLoading: false, hasActiveDownload: true, isPlayingMedia: false, isCapturingMedia: false, hasUnsavedFormInput: false).canSleep)
        #expect(!TabSleepConditions(isSelected: false, isLoading: false, hasActiveDownload: false, isPlayingMedia: true, isCapturingMedia: false, hasUnsavedFormInput: false).canSleep)
        #expect(!TabSleepConditions(isSelected: false, isLoading: false, hasActiveDownload: false, isPlayingMedia: false, isCapturingMedia: true, hasUnsavedFormInput: false).canSleep)
        #expect(!TabSleepConditions(isSelected: false, isLoading: false, hasActiveDownload: false, isPlayingMedia: false, isCapturingMedia: false, hasUnsavedFormInput: true).canSleep)
    }
}
