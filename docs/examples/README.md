# Examples

sui includes 18 example apps demonstrating different features. Each is a complete, runnable project in the `examples/` directory.

## All Examples

| Example | Key Features | Complexity |
|---------|-------------|------------|
| [hello-world](examples/hello-world.md) | Text, VStack, Spacer, modifiers | Beginner |
| [counter](examples/counter.md) | @:state, Button, StateAction, Text.bind | Beginner |
| [todo-app](examples/todo-app.md) | Observable, ForEach, Form, CustomSwift | Intermediate |
| navigation | NavigationStack, NavigationLink | Beginner |
| modifiers-demo | TextField, Toggle, Slider, Sheet, Alert | Intermediate |
| [components](examples/README.md) | ViewComponent, @:swiftBinding | Intermediate |
| [bridge-demo](examples/bridge-demo.md) | @:expose, CustomSwift | Intermediate |
| [async-fetch](examples/async-fetch.md) | BridgeCallLoading, async bridge | Intermediate |
| ios-tabs | TabView, platform UI | Beginner |
| ipad-split | NavigationSplitView | Beginner |
| settings-demo | Form, ScrollView, Sections | Beginner |
| visionos-cube | visionOS APIs | Advanced |
| normal-haxe | Closures, onAppear, task, onDisappear | Intermediate |
| form-demo | Stepper, DatePicker, Gauge, ProgressView, GroupBox, Link | Intermediate |
| visual-effects | blur, scaleEffect, rotationEffect, state-bound modifiers | Intermediate |
| grid-gallery | LazyVGrid, ContentUnavailableView, ConditionalView, gestures | Intermediate |
| image-filters | brightness, contrast, saturation, grayscale, sliders | Intermediate |
| animations | Animated actions, .animation(), .transition(), spring/bounce | Intermediate |

## Running an Example

```bash
cd examples/hello-world
haxelib run sui run macos
```

## Annotated Walkthroughs

- **[Hello World](examples/hello-world.md)** &mdash; Your first app
- **[Counter](examples/counter.md)** &mdash; State management basics
- **[Todo App](examples/todo-app.md)** &mdash; Building a real app
- **[Bridge Demo](examples/bridge-demo.md)** &mdash; Calling Haxe from Swift
- **[Async Fetch](examples/async-fetch.md)** &mdash; Async bridge operations
