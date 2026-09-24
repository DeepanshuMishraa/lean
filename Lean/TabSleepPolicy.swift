struct TabSleepConditions {
    let isSelected: Bool
    let isLoading: Bool
    let hasActiveDownload: Bool
    let isPlayingMedia: Bool
    let isCapturingMedia: Bool
    let hasUnsavedFormInput: Bool
    var hasActivePopup = false

    var canSleep: Bool {
        !isSelected && !isLoading && !hasActiveDownload && !isPlayingMedia
            && !isCapturingMedia && !hasUnsavedFormInput && !hasActivePopup
    }
}

enum TabSleepPolicy {
    static func canCommitSleep(_ conditions: TabSleepConditions, isStillInactive: Bool) -> Bool {
        isStillInactive && conditions.canSleep
    }
}
