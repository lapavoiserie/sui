import sui.App;
import sui.View;
import sui.ui.*;
import rui.Signal;

/**
    Phase A demo — sui state on the shared `rui` core.

    Two things at once:

    1. **A showcase** of sui's controls (TextField, Toggle, Slider, Stepper,
       Picker, ProgressView, List/ForEach) inside a Form/NavigationStack.
    2. **A reactivity bench.** Every control is bound to a Haxe `State` that now
       extends `rui.state.State`. The "Haxe mirror" section reads those states
       back, so a value typed in SwiftUI has to travel Swift -> Haxe -> Swift to
       show up. The live journal records every change and which side wrote it.

    On launch it also runs a scripted self-test and traces PASS/FAIL lines, so
    the contract is checkable from a log rather than by eye.
**/
class StateShowcaseApp extends App {
    static function main() {}

    // Bound to SwiftUI controls — these are written from *both* sides.
    @:state var userName:String = "Ada";
    @:state var notify:Bool = true;
    @:state var brightness:Float = 0.6;
    @:state var quantity:Int = 3;

    // Written from Haxe only.
    @:state var clicks:Int = 0;
    @:state var journal:String = "(en attente d'un changement)";

    // Proof that sui states are now tracked by rui effects.
    var effectRuns:Int = 0;

    public function new() {
        super();
        appName = "StateShowcase";
        bundleIdentifier = "com.sui.stateshowcase";

        // A rui effect over a sui state: this is what the shared core buys us.
        // It re-runs whenever `clicks` changes, whoever wrote it.
        new Effect(() -> {
            clicks.get();
            effectRuns++;
        });

        // Journal every change and its origin.
        userName.onValueChanged(v -> note('userName = "$v"'));
        notify.onValueChanged(v -> note("notify = " + v));
        brightness.onValueChanged(v -> note("brightness = " + round2(v)));
        quantity.onValueChanged(v -> note("quantity = " + v));

        selfTest();
    }

    function note(entry:String):Void {
        journal.set(entry);
        trace("[journal] " + entry);
    }

    static function round2(v:Float):Float {
        return Math.round(v * 100) / 100;
    }

    /**
        Scripted check of the contract the port rests on. Traced, not asserted,
        so a failure is visible in the log without killing the app.
    **/
    function selfTest():Void {
        var fails = 0;
        inline function check(label:String, ok:Bool) {
            if (!ok) fails++;
            trace((ok ? "[PASS] " : "[FAIL] ") + label);
        }

        // 1. An application write updates the value and re-runs rui effects.
        var before = effectRuns;
        clicks.set(1);
        check("app write updates value", clicks.get() == 1);
        check("app write re-runs the rui effect", effectRuns == before + 1);

        // 2. An unchanged write does not re-run effects (the shared core
        //    compares before notifying). sui still mirrors it to Swift.
        before = effectRuns;
        clicks.set(1);
        check("unchanged write does not re-run the effect", effectRuns == before);

        // 3. A write coming *from* SwiftUI reaches Haxe. This is the path a
        //    TextField binding takes: the C bridge calls _applyFromSwift, which
        //    now routes through applyExternal — effects and onValueChanged run,
        //    but nothing is pushed back to Swift.
        before = effectRuns;
        sui.state.State._applyFromSwift("clicks", "42");
        check("SwiftUI write reaches Haxe", clicks.get() == 42);
        check("SwiftUI write re-runs the rui effect", effectRuns == before + 1);

        // 4. Type coercion on the way in, per state type.
        sui.state.State._applyFromSwift("notify", "false");
        check("Bool coerced from SwiftUI", notify.get() == false);
        sui.state.State._applyFromSwift("brightness", "0.25");
        check("Float coerced from SwiftUI", Math.abs(brightness.get() - 0.25) < 1e-9);
        sui.state.State._applyFromSwift("userName", "Grace");
        check("String coerced from SwiftUI", userName.get() == "Grace");

        // 5. peek() reads without subscribing — used by the shared-memory
        //    bridge helpers, which must not register dependencies.
        check("peek matches get", quantity.peek() == quantity.get());

        // Put the app back where the UI expects it.
        clicks.set(0);
        notify.set(true);
        brightness.set(0.6);
        userName.set("Ada");

        trace(fails == 0 ? "[SELFTEST] ALL PASSED" : '[SELFTEST] $fails FAILED');
    }

    override function body():View {
        return new NavigationStack(
            new Form([
                new Section("Contrôles SwiftUI — ils écrivent dans Haxe", [
                    new TextField("Votre nom", "userName"),
                    new Toggle("Notifications", "notify"),
                    new Slider("brightness", 0.0, 1.0),
                    new Stepper("Quantité", "quantity", 1, 99)
                ]),

                new Section("Miroir Haxe — relu depuis l'état partagé", [
                    Text.bind('userName = ${userName.value}'),
                    Text.bind('notify = ${notify.value}'),
                    Text.bind('brightness = ${brightness.value}'),
                    Text.bind('quantity = ${quantity.value}'),
                    new ProgressView("Luminosité", "brightness", 1.0)
                ]),

                new Section("Écritures applicatives — depuis Haxe", [
                    Text.bind('clicks = ${clicks.value}')
                        .font(FontStyle.Headline),
                    new HStack(null, 12, [
                        new Button("+1", () -> {
                            clicks.value++;
                            note("clicks = " + clicks.peek() + " (Haxe)");
                        }),
                        new Button("Même valeur", () -> {
                            clicks.set(clicks.peek());
                            note("écriture inchangée (aucun effet rejoué)");
                        }),
                        new Button("Reset", () -> {
                            clicks.set(0);
                            note("clicks remis à 0 (Haxe)");
                        })
                    ])
                ]),

                new Section("Journal", [
                    Text.bind('${journal.value}')
                        .foregroundColor(ColorValue.Secondary)
                ])
            ]).navigationTitle("État partagé — sui sur rui")
        );
    }
}
