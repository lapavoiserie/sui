package sui.ui;

import sui.View;

/**
    Native SwiftUI `DatePicker` bound to a `State<String>` holding
    an ISO-8601 date in `YYYY-MM-DD` form. Sui generates a
    `Binding<Date>` adapter that round-trips through a shared
    `DateFormatter` so the picker can present a real macOS / iOS
    date wheel + popover while the Haxe side keeps its string
    representation.

    ```haxe
    new IsoDatePicker("Début", "editorStartDateIso")
    new IsoDatePicker("Fin", "editorEndDateIso").labelsHidden()
    ```

    Generates (roughly):
    ```swift
    DatePicker("Début", selection: Binding(
        get: { suiIsoParse(appState.editorStartDateIso) ?? Date() },
        set: { appState.editorStartDateIso = suiIsoFormat($0) }
    ), displayedComponents: .date)
    ```

    The `suiIsoParse` / `suiIsoFormat` helpers are emitted once at
    the top of `ContentView.swift` (when any `IsoDatePicker` is in
    the view tree) and share a single UTC-anchored
    `yyyy-MM-dd` `DateFormatter`.

    Use `.labelsHidden()` on the modifier chain when the label is
    redundant — e.g. when an HStack already shows the field name
    on the left.
**/
class IsoDatePicker extends View {
    public var label:String;
    public var isoStateName:String;

    public function new(label:String, isoStateName:String) {
        super();
        this.viewType = "IsoDatePicker";
        this.label = label;
        this.isoStateName = isoStateName;
    }
}
