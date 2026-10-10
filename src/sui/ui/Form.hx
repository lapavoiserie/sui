package sui.ui;

import sui.View;

/**
    The rows of one entry, their labels lined up. Maps to SwiftUI's `Form`,
    drawn as columns: each label right-aligned against the column of controls,
    as a macOS dialog draws them.

    ```haxe
    ui(<Form>
        <Section>
            <Field label="Quoi"><TextInput text={title_}/></Field>
            <Picker label="Fréquence" selectedIndex={preset_}>{presets}</Picker>
        </Section>
    </Form>)
    ```

    Canon: `Form` carries its rows as children. A control with a label of its
    own is a row by itself; `Field` is the row for one without. An untitled
    `Section` is the gap between groups.
**/
@:node("Form")
@:content("content")
class Form extends View {
    public function new(content:Array<View>) {
        super();
        this.viewType = "Form";
        this.children = content == null ? [] : content;
    }
}
