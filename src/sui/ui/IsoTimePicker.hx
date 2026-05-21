package sui.ui;

import sui.View;

/**
    Native SwiftUI `DatePicker` set to `.hourAndMinute` mode and
    bound to a `State<String>` holding a 24-hour time in `"HH:mm"`
    form. Companion to [IsoDatePicker]; same `Binding<Date>`
    adapter pattern but with a shared `HH:mm` formatter.

    ```haxe
    new IsoTimePicker("Début", "editorStartTime")
    new IsoTimePicker("Fin", "editorEndTime")
    ```

    Generates (roughly):
    ```swift
    DatePicker("Début", selection: Binding(
        get: { suiIsoTimeParse(appState.editorStartTime) ?? Date() },
        set: { appState.editorStartTime = suiIsoTimeFormat($0) }
    ), displayedComponents: .hourAndMinute)
    ```

    The string format is fixed at `HH:mm` (zero-padded 24-hour),
    UTC-anchored + POSIX-locale, so round-trips are lossless
    independent of the user's regional time formatting prefs.
**/
class IsoTimePicker extends View {
    public var label:String;
    public var isoStateName:String;

    public function new(label:String, isoStateName:String) {
        super();
        this.viewType = "IsoTimePicker";
        this.label = label;
        this.isoStateName = isoStateName;
    }
}
