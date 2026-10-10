package sui.ui;

import sui.View;

/**
    "Are you sure?" -- a question with one act and a way out. Maps to
    SwiftUI's `.confirmationDialog`, which macOS draws as an alert.

    ```haxe
    ui(<ConfirmDialog presented={archiving_} title="Archiver la tâche ?"
        message="Son historique est conservé." confirmLabel="Archiver"
        cancelLabel="Annuler" destructive={true} onConfirm={archive}/>)
    ```

    Canon: `ConfirmDialog` carries `presented` (`Bool`) with `onPresented`,
    `title`, `message` (optional), `confirmLabel`, `cancelLabel`,
    `destructive` (optional, `Bool`) and the act `onConfirm`. Answering
    either way closes it: the renderer writes `false` back.

    **Both labels are the application's.** A library supplying "Cancel" would
    be writing in a language it does not know -- the argument the canon makes
    about a `Disclosure` summary -- and a dialog half in French and half in
    English reads as broken.

    `destructive` asks for the act to be drawn as one that destroys. A hint,
    failing soft: the words still say what the button does.
**/
@:node("ConfirmDialog")
class ConfirmDialog extends View {
    @:cell("presented", "onPresented", "Bool") public var presentedBinding:String;
    @:prop public var title:String;
    @:prop public var message:Null<String>;
    @:prop public var confirmLabel:String;
    @:prop public var cancelLabel:String;
    @:prop public var destructive:Bool;
    @:action("onConfirm") public var action:Null<() -> Void>;

    public function new(presentedBinding:String, title:String, ?message:String, confirmLabel:String,
            cancelLabel:String, destructive:Bool = false, ?action:() -> Void) {
        super();
        this.viewType = "ConfirmDialog";
        this.presentedBinding = presentedBinding;
        this.title = title;
        this.message = message;
        this.confirmLabel = confirmLabel;
        this.cancelLabel = cancelLabel;
        this.destructive = destructive;
        this.action = action;
    }
}
