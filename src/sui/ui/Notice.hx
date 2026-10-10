package sui.ui;

import sui.View;

/**
    A word about what just happened, over the bottom of the window: a toast.

    ```haxe
    ui(<Notice presented={noticeShown_} message="« Vaisselle » faite — merci !" kind="success"
        actionLabel="Annuler" onAction={undo} dismissLabel="Fermer"/>)
    ```

    Canon: `Notice` carries `presented` (`Bool`) with `onPresented`,
    `message`, `kind` (optional: `success`, `info`, `warning`, `error`),
    `actionLabel` with `onAction` (optional, together) and `dismissLabel`.

    A `success` or `info` notice leaves on its own after a few seconds; a
    `warning` or `error` stays, with a close button, until closed. Either way
    the renderer writes `false` back, and doing the act closes it too.

    The node draws nothing where it stands: the toast belongs to the window,
    so the node can sit anywhere in the screen it reports on.
**/
@:node("Notice")
class Notice extends View {
    @:cell("presented", "onPresented", "Bool") public var presentedBinding:String;
    @:prop public var message:String;
    @:prop public var kind:Null<String>;
    @:prop public var actionLabel:Null<String>;
    @:prop public var dismissLabel:String;
    @:action("onAction") public var action:Null<() -> Void>;

    public function new(presentedBinding:String, message:String, ?kind:String, ?actionLabel:String,
            dismissLabel:String, ?action:() -> Void) {
        super();
        this.viewType = "Notice";
        this.presentedBinding = presentedBinding;
        this.message = message;
        this.kind = kind;
        this.actionLabel = actionLabel;
        this.dismissLabel = dismissLabel;
        this.action = action;
    }
}
